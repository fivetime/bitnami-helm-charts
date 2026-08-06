<!--- app-name: OVN Chassis -->

# OVN Chassis packaged by Broadcom

Turns Kubernetes nodes into OVN chassis attached to an **external** OVN control plane. It runs `ovn-controller` — and, optionally, Open vSwitch — as a host-network DaemonSet and points it at a Southbound database you already operate.

It deploys **no Northbound, no Southbound and no northd**. That absence is the design: several Kubernetes clusters can share one OVN without any of them owning it.

## TL;DR

```console
helm install my-release oci://REGISTRY_NAME/REPOSITORY_NAME/ovn-chassis \
  --set ovn.southbound.address=tcp:10.0.0.1:6642
```

That is the whole minimum configuration. One address.

## Introduction

Attaching a Kubernetes cluster to an OVN that something else runs — DevStack, OpenStack-Helm, a distro OVN, a hardware SDN — normally means taking a chart built to deploy the *entire* OVN and switching most of it off. You disable three StatefulSets, two Services and a Deployment, discover that one of the `manifests.*` keys you switched off is dead and never read, clear a dependency that waits forever on a Service you just removed, and then work out why the container still will not start when the database address is plainly correct.

This chart is the subtraction done once. What is left is a DaemonSet, a ConfigMap and a ServiceAccount.

### Why `ovn-controller` directly

The usual OVN container image ships `ovnkube.sh`, an entrypoint inherited from ovn-kubernetes, where the databases are always StatefulSets in the same namespace. Before starting anything it calls `ready_to_start_node()`, which lists EndpointSlices for `ovn-ovsdb-nb` and `ovn-ovsdb-sb` and blocks until it finds some — **counting** them, never dialling them. Point that script at a database outside the cluster and it waits forever on a gate that has nothing to do with whether the database is reachable. The workaround is to conjure selector-less Services and hand-written EndpointSlices so a check that measures nothing can pass.

This chart runs `ovn-controller` itself, so the gate is not there to work around. Readiness instead asks the thing that matters:

```console
ovn-appctl -t ovn-controller connection-status   # must say "connected"
```

A chassis that is up but disconnected accepts no port bindings, so reporting it Ready would hand traffic to a node that cannot carry it.

## Parameters

### Global parameters

| Name                      | Description                        | Value  |
| ------------------------- | ---------------------------------- | ------ |
| `global.imageRegistry`    | Global Docker image registry       | `""`   |
| `global.imagePullSecrets` | Global Docker registry secret names | `[]`  |

### OVN control plane connection

| Name                        | Description                                                                                  | Value   |
| --------------------------- | -------------------------------------------------------------------------------------------- | ------- |
| `ovn.southbound.address`    | OVN Southbound DB remote(s). **REQUIRED** — the chart refuses to render without it            | `""`    |
| `ovn.northbound.address`    | OVN Northbound DB remote(s). Optional; only used by CLI tools inside the pod                  | `""`    |
| `ovn.tls.enabled`           | Use SSL/TLS for the Southbound connection                                                     | `false` |
| `ovn.tls.existingSecret`    | Secret with `tls.crt`, `tls.key`, `ca.crt`                                                    | `""`    |

`ovn-controller` speaks to the Southbound and nothing else — it never opens the Northbound. So `ovn.southbound.address` is the whole integration, and the Northbound is wired in only so `ovn-nbctl` works when you exec into the pod.

The address is passed to ovsdb as a `--remote`, which is what makes relays and HA a values-only change:

| Value                                     | What it gives you                                                                 |
| ----------------------------------------- | --------------------------------------------------------------------------------- |
| `tcp:10.0.0.1:6642`                       | a single database — DevStack, an all-in-one                                        |
| `tcp:10.0.0.1:6642,tcp:10.0.0.2:6642`     | a RAFT cluster, with client-side failover                                          |
| `tcp:ovsdb-relay.ovn.svc:6642`            | an **ovsdb-relay** fan-out                                                         |
| `ssl:10.0.0.1:6642`                       | TLS — set `ovn.tls.*` as well                                                      |

Relays are worth reaching for earlier than people expect. Every chassis holds an open monitor on the Southbound, so the leader's fan-out cost grows with the fleet; relays absorb that read load and the chassis cannot tell the difference. Both `tcp://host:port` and `tcp:host:port` are accepted — the first is what the docs tend to write, the second is what ovsdb parses, and the chart converts.

### Chassis identity and tunnelling

| Name                    | Description                                                            | Value     |
| ----------------------- | ---------------------------------------------------------------------- | --------- |
| `ovn.systemID`          | Chassis system-id. Empty ⇒ the Kubernetes node name                     | `""`      |
| `ovn.encapType`         | `geneve` or `vxlan`                                                     | `geneve`  |
| `ovn.encapInterface`    | Interface whose first IPv4 becomes the tunnel endpoint                  | `""`      |
| `ovn.encapAddress`      | Tunnel endpoint set literally; wins over `encapInterface`               | `""`      |
| `ovn.bridge`            | Integration bridge                                                      | `br-int`  |
| `ovn.monitorAll`        | Monitor the whole SB rather than only the rows this chassis needs       | `false`   |
| `ovn.availabilityZones` | Value for the `availability-zones=` CMS option                          | `""`      |
| `ovn.extraCMSOptions`   | Extra `ovn-cms-options`, comma-separated                                | `""`      |
| `ovn.extraExternalIDs`  | Extra `Open_vSwitch.external_ids`, as a map                             | `{}`      |
| `ovn.logLevel`          | `emer`, `err`, `warn`, `info`, `dbg`                                    | `info`    |

**The chassis name defaults to the node name.** It is stable across reboots with nothing to persist, and `ovn-sbctl show` becomes readable instead of a wall of UUIDs. When several clusters share one OVN this makes node-name uniqueness a hard constraint across *all* of them: two chassis with the same system-id are one chassis to the Southbound, and they will fight over port bindings.

**Check the tunnel endpoint before you trust it.** With neither `encapAddress` nor `encapInterface` set, each chassis announces its Kubernetes node IP. That is right only when the node's primary address is also your overlay underlay. If the OVN's existing chassis tunnel over a dedicated network, these nodes join on the wrong one — and it does not fail loudly. As long as the two networks are mutually routable the tunnels come up and traffic flows; what you get is a split underlay and an MTU that no longer matches what Neutron computed, with no symptom until something fragments. Compare before and after:

```console
ovn-sbctl --columns=chassis_name,ip --format=table list encap
```

### Distributed chassis gateway

| Name                   | Description                                                     | Value   |
| ---------------------- | ----------------------------------------------------------------- | ------- |
| `ovn.gateway.enabled`  | Advertise `enable-chassis-as-gw`                                  | `false` |

Off by default, and that default is load-bearing rather than merely conservative. Enabling it makes Neutron eligible to schedule tenant routers' external gateway ports onto these nodes. A chassis that claims to be a gateway but has no working provider bridge becomes a black hole: the gateway is scheduled there, north-south traffic follows, and nothing comes back — while the port binds and the router reports healthy.

So the chart refuses to render `gateway.enabled=true` unless you have also either asked it to create the provider bridge or acknowledged that you built one yourself by setting `ovn.provider.bridgeMappings` explicitly.

For a cluster where only some nodes are gateways, install the chart twice with different `nodeSelector`s rather than trying to express it in one release.

### Provider network

| Name                             | Description                                                      | Value        |
| -------------------------------- | ------------------------------------------------------------------ | ------------ |
| `ovn.provider.bridge`            | Provider bridge name                                               | `br-ex`      |
| `ovn.provider.physicalNetwork`   | Neutron physnet mapped to it                                       | `external`   |
| `ovn.provider.createBridge`      | Create the bridge if missing                                       | `false`      |
| `ovn.provider.interface`         | Physical interface to enslave. **Must have no IP**                 | `""`         |
| `ovn.provider.bridgeMappings`    | Full mapping string, overriding the physnet:bridge pair            | `""`         |

`physicalNetwork` must name a physnet Neutron actually knows, or provider ports will not bind. Pointing it at a physnet that does not exist is a deliberate and safe choice when these nodes should carry no provider traffic at all.

**This chart never migrates an IP onto the bridge.** Doing that from a container means flushing an address off a live NIC and hoping the re-add succeeds; if the pod is killed in between, the node is off the network and nothing in the cluster can reach it to fix it. The entrypoint refuses to enslave an interface that has an IPv4 address. Use an address-less NIC, or build the bridge out of band.

### Open vSwitch (optional component)

| Name                             | Description                                                       | Value                  |
| -------------------------------- | ------------------------------------------------------------------- | ---------------------- |
| `openvswitch.enabled`            | Run Open vSwitch in this DaemonSet                                  | `true`                 |
| `openvswitch.dbPath`             | Host directory holding `conf.db`. Must survive reboots              | `/var/lib/openvswitch` |
| `openvswitch.runPath`            | Host directory for sockets — what `ovs-cni` looks for               | `/run/openvswitch`     |
| `openvswitch.ptcpPort`           | Also listen for ovsdb on this TCP port. `0` disables                | `0`                    |
| `openvswitch.loadKernelModule`   | Init container that `modprobe openvswitch`                          | `true`                 |
| `openvswitch.extraOtherConfig`   | Extra `Open_vSwitch.other_config`, as a map                         | `{}`                   |

Enabled by default because a stock node has no OVS, and `ovn-controller` without OVS is inert. Turn it off when something else already owns Open vSwitch on these nodes — distro packages under systemd, another chart, an OVS that `ovs-cni` is already using — and this chart attaches to that instead.

Two things about this that are easy to get wrong:

**`conf.db` is deliberately not under `/run`.** That is a tmpfs, so a reboot destroys the database and with it the chassis identity and every bridge and port. Charts that put it there need a second mechanism — a node annotation, usually — to put the identity back afterwards.

**One socket, one owner.** `/run/openvswitch/db.sock` can be held by exactly one `ovsdb-server`. If the node also runs OVS under systemd, the two take turns claiming it on every restart, and whichever loses takes `br-int` away from its clients with no error anywhere: `ovs-cni` simply starts reporting `failed to find bridge br-int`. Before enabling this component, on every targeted node:

```console
systemctl mask ovsdb-server.service ovs-vswitchd.service
```

Masking works even where the units do not exist yet, which is the point — do it before OVS ever lands.

### What is exposed on the node, and what is not

Exactly one thing is: `openvswitch.runPath` (`/run/openvswitch`), holding `db.sock` and the ovsdb/vswitchd control sockets. It is a hostPath because **other components consume it** — `ovs-cni` opens `db.sock` on every CNI ADD, and so does anything else on the node that manages OVS ports, ovn-bgp-agent included.

`ovn-controller`'s pidfile and unixctl socket are pod-local (an emptyDir at `/run/ovn`) and deliberately not on the host. Nothing outside the pod consumes them, and exposing them would only invite debugging from the node — which needs `ovs-vsctl`/`ovn-appctl` binaries a containerised deployment does not install, and installing them drags in the Open vSwitch systemd units that then fight this chart for `db.sock`. The rule the chart follows: a hostPath is for a consumer, never for convenience.

Debug through the pod:

```console
kubectl exec ds/RELEASE -c ovs-vswitchd   -- ovs-vsctl show
kubectl exec ds/RELEASE -c ovn-controller -- ovn-appctl -t ovn-controller connection-status
```

**On watching OVN events.** The unixctl socket is a command channel, not an event bus, so its absence costs an agent nothing. Programs that *watch* OVN — ovn-bgp-agent is the usual one — open ovsdb monitors instead: one against the Southbound, one against `openvswitch.runPath/db.sock`. Both are available here. (`/run/ovn` carries a database socket only where the Northbound itself runs on that host, which on a chassis node it does not.)

### Image, deployment and security parameters

See `values.yaml`; the annotated `@param` comments there are the reference. The image defaults to `quay.io/airshipit/ovn`, which carries `ovsdb-server`, `ovs-vswitchd`, `ovn-controller` and the CLI tools in one layer — which is why this chart needs only one image for both components.

**Version rule:** `ovn-controller` must not be *newer* than the Southbound it connects to. OVN supports central-first upgrades, so an older chassis against a newer SB is a supported state; the reverse is not.

Both components run privileged, and there is no useful way around it: `ovs-vswitchd` programs the kernel datapath and `ovn-controller` drives netlink and the OVS control socket. The `containerSecurityContext` knobs exist so you can tighten them for a specific kernel/CNI combination, not because the defaults are expected to be enough.

Nothing in this chart calls the Kubernetes API. There is no Role and no ClusterRole; the ServiceAccount exists only to give the pod an identity, and its token is not mounted.

## Examples

Attach to a DevStack all-in-one, tunnelling over a dedicated underlay:

```console
helm install b oci://REGISTRY_NAME/REPOSITORY_NAME/ovn-chassis -n openstack \
  --set ovn.southbound.address=tcp:10.32.32.130:6642 \
  --set ovn.northbound.address=tcp:10.32.32.130:6641 \
  --set ovn.encapInterface=ovn-int
```

Attach through an ovsdb-relay, on a subset of nodes, with OVS already on the host:

```console
helm install edge oci://REGISTRY_NAME/REPOSITORY_NAME/ovn-chassis -n openstack \
  --set ovn.southbound.address=tcp:ovsdb-relay.ovn.svc.cluster.local:6642 \
  --set openvswitch.enabled=false \
  --set nodeSelector.ovn-chassis=enabled
```

Gateway nodes, as a second release alongside a plain-compute one:

```console
helm install gw oci://REGISTRY_NAME/REPOSITORY_NAME/ovn-chassis -n openstack \
  --set ovn.southbound.address=tcp:10.32.32.130:6642 \
  --set ovn.gateway.enabled=true \
  --set ovn.provider.createBridge=true \
  --set ovn.provider.interface=eth1 \
  --set nodeSelector.ovn-gateway=enabled
```

## Troubleshooting

| Symptom                                                   | Where to look                                                                                     |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Pod Running, never Ready                                  | Readiness is `connection-status`. The SB is refusing or unreachable — check the address and TLS.  |
| `waiting for /run/openvswitch/db.sock`                    | `openvswitch.enabled=false` but nothing else provides OVS, or it uses a different rundir.          |
| Ready, but no chassis in `ovn-sbctl show`                 | A second chassis is using the same system-id — check for a node-name collision across clusters.    |
| Chassis appears, tunnels to the wrong addresses           | `ovn.encapInterface` — see the warning above.                                                      |
| `ovs-cni: failed to find bridge br-int`                   | Socket ownership. Mask the host OVS units.                                                         |
| Provider traffic black-holed on gateway nodes             | `br-ex` does not actually reach the provider network on that node.                                 |

## License

Copyright &copy; Broadcom, Inc. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at <http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
