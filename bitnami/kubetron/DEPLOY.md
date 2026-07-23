<!--- app-name: kubetron -->

# kubetron — Deployment & End-to-End Validation Guide

This document describes **how we actually deploy this chart** on a live OpenStack-on-Kubernetes
cluster, and the **complete end-to-end test matrix we validated** on that deployment. Sensitive,
site-specific values are redacted with `<angle-bracket>` placeholders — substitute your own.

It complements the [README.md](./README.md): the README is the chart reference, this is the
operational runbook.

---

## 0. Prerequisites — must already be READY before you start

This chart is a **thin orchestration layer**. It assumes the data plane and the surrounding
platform already exist and are healthy. Bring these up first and verify them independently:

### 0.1 OpenStack — Neutron / OVN / OVS ready

- **Neutron API reachable from the cluster.** kubetron talks to it over the in-cluster Service,
  e.g. `http://neutron-server.<openstack-ns>.svc.cluster.local:9696`. Do **not** rely on the
  Keystone catalog `neutron` alias — pin the real Service via `openstack.networkEndpointOverride`
  (see §1.3), it is redeploy-proof.
- **OVN is the Neutron backend**, with `ovn-controller` running on every node that will host
  kubetron pods, and each node registered as a chassis whose **hostname matches
  `<nodeName><node-fqdn-suffix>`** (e.g. `compute1.example.local`). Verify:

  ```console
  openstack network agent list      # 'Host' column = chassis hostname per node; all Alive=True
  ```

  > ⚠️ This is the single most important environmental invariant. kubetron writes
  > `binding:host_id = <nodeName><controller.nodeChassisSuffix>`; if that string does not match a
  > real, alive chassis, OVN never admits the port and it stays `DOWN`.

- **An external network exists** (for Floating IPs), e.g. `public`, shared, with a subnet from your
  external range. Note its ID — you need it for the FIP matrix.
- **Octavia with the OVN provider** is deployed (for the Service/LoadBalancer matrix). Octavia must
  itself be able to reach Neutron (it calls Neutron by catalog name server-side).

### 0.2 CNI plane

- **Multus CNI** installed cluster-wide.
- **`ovs-cni` (plugin + marker DaemonSet)** installed and healthy on every OVN-capable node.

  > ⚠️ **Pin `ovs-cni` to an immutable tag or `@sha256:` digest — never `:latest`.** kubetron
  > depends on `ovs-cni` writing `external_ids:iface-id` on each pod's OVS interface. A `:latest`
  > image with `imagePullPolicy: IfNotPresent` can leave different nodes frozen on different
  > historical builds; on nodes that cached a build without correct `OvnPort→iface-id` support,
  > the pod's veth lands on `br-int` with **empty `external_ids`**, `ovn-controller` cannot match
  > it to a logical port, and the Neutron port stays `DOWN` (pod ends up `NotReady`). Confirm all
  > nodes run the same digest: `kubectl -n <cni-ns> get pod -l app.kubernetes.io/name=ovs-cni -o jsonpath='{range .items[*]}{.spec.nodeName}{" "}{.status.containerStatuses[0].imageID}{"\n"}{end}'`

- Do **not** co-install OVN-Kubernetes (it fights for `br-int`).

### 0.3 Certificates

- **cert-manager** installed, plus the issuer referenced by the chart (default
  `ClusterIssuer/<your-cluster-issuer>`). kubetron uses it to issue the webhook (and, if enabled,
  the aggregated apiserver) serving certificate; `cainjector` injects the CA bundle.
- Alternatively set `webhook.certManager.enabled=false` to have Helm self-sign (no dependency).

### 0.4 KubeVirt (only for the VM matrix in §3.5)

- **KubeVirt deployed and `Deployed`:**

  ```console
  kubectl get kubevirt -A     # PHASE should be Deployed
  ```

### 0.5 Credentials

- An **admin OpenStack application/username credential** as a Secret in the release namespace,
  default name `neutron-keystone-admin`, with `OS_*` keys (as published by OpenStack-Helm):
  `OS_AUTH_URL`, `OS_USERNAME`, `OS_PASSWORD` (or `OS_APPLICATION_CREDENTIAL_*`), `OS_PROJECT_NAME`,
  `OS_PROJECT_DOMAIN_NAME`, `OS_USER_DOMAIN_NAME`, `OS_REGION_NAME`. Keep it in-cluster; never bake
  credentials into values.

- The **kubetron image** must be pullable by the cluster (an internal registry / Harbor mirroring
  the CI image is typical). **Pin an immutable tag**, not `latest`.

---

## 1. Deploy kubetron via Helm

### 1.1 Namespace and admin credential

```console
kubectl create namespace kubetron-system

# The admin credential is usually copied from the OpenStack namespace so it never leaves the
# cluster. Keys are the OS_* variables listed in §0.5.
kubectl -n kubetron-system get secret neutron-keystone-admin   # verify it exists
```

### 1.2 Values file (redacted)

Save as `values-prod.yaml`. Every `<...>` is site-specific:

```yaml
image:
  registry: <registry>                 # e.g. internal Harbor mirroring the CI image
  repository: <repo>/kubetron
  tag: <immutable-tag>                 # a semver or @sha256 digest — NOT "latest"
  pullPolicy: IfNotPresent

openstack:
  existingSecret: neutron-keystone-admin
  # gophercloud needs OS_DOMAIN_NAME when scoping by OS_PROJECT_NAME; OpenStack-Helm only ships
  # OS_PROJECT_DOMAIN_NAME, so project it in via this key (default already does this):
  domainNameSecretKey: OS_PROJECT_DOMAIN_NAME
  # Pin the real Neutron Service, bypassing the fragile Keystone catalog alias:
  networkEndpointOverride: "http://neutron-server.<openstack-ns>.svc.cluster.local:9696/"

controller:
  # MUST match how ovn-controller registers each chassis (see §0.1). Empty => node name verbatim.
  nodeChassisSuffix: "<node-fqdn-suffix>"      # e.g. ".example.local"
  gcInterval: 5m
  # Full pods run dnsPolicy:None; supply a resolver reachable over the OVN network. Authority is
  # the Neutron subnet's dns_nameservers — this is only the placeholder for the DNSNone requirement.
  defaultDNSNameservers:
    - "<resolver-ipv4>"
    - "<resolver-ipv6>"

webhook:
  certManager:
    enabled: true
    issuerRef:
      kind: ClusterIssuer
      name: <your-cluster-issuer>

# Defaults are production-sane: replicaCount=2 (HA, leader-elected), PDB on, NetworkPolicy on,
# CRD mode (apiserver.enabled=false). Set resources for production instead of resourcesPreset.
resources:
  requests: { cpu: 100m, memory: 128Mi }
  limits:   { cpu: 500m, memory: 256Mi }
```

### 1.3 Install

Validate against the live cluster first (this catches API-version / CRD issues that
`helm template` alone cannot):

```console
helm install kubetron oci://REGISTRY_NAME/REPOSITORY_NAME/kubetron \
  -n kubetron-system -f values-prod.yaml --dry-run=server

helm install kubetron oci://REGISTRY_NAME/REPOSITORY_NAME/kubetron \
  -n kubetron-system -f values-prod.yaml --wait --timeout 5m
```

### 1.4 Verify the control plane is healthy

```console
# manager 2/2, leader elected
kubectl -n kubetron-system get deploy kubetron
kubectl -n kubetron-system logs -l app.kubernetes.io/instance=kubetron | grep -E "Successfully acquired lease|Starting workers"

# CRD present
kubectl get crd networkportclaims.kubetron.network.kubevirt.io

# webhook serving cert issued and CA injected into all 3 webhooks
kubectl -n kubetron-system get certificate kubetron-webhook-cert          # READY=True
kubectl get mutatingwebhookconfiguration kubetron-kubetron-system \
  -o jsonpath='{range .webhooks[*]}{.name}{" caBundle="}{.clientConfig.caBundle | length}{"\n"}{end}'
```

Expected: manager `2/2`, one `Successfully acquired lease ...-default`, all controllers
(`networkportclaim`, `pod`, `service`, `statefulset`, `virtualmachineinstance`, `dnszone`) started,
webhook cert `READY=True`, and a non-empty caBundle on `pods.`, `claims.`, `vmis.` webhooks.

### 1.5 Smoke test (one claim binds to a Neutron port)

```console
kubectl create ns <test-ns>
# tenant credential Secret (see §3.1 for how to mint an app credential)
kubectl -n <test-ns> apply -f - <<'EOF'
apiVersion: kubetron.network.kubevirt.io/v1alpha1
kind: NetworkPortClaim
metadata: { name: smoke }
spec: { network: <a-neutron-network>, credentialSecretRef: <tenant-cred-secret> }
EOF
kubectl -n <test-ns> wait npc/smoke --for=jsonpath='{.status.phase}'=Bound --timeout=60s
kubectl -n <test-ns> get npc smoke -o custom-columns=PHASE:.status.phase,IP:.status.ips[0]
```

`PHASE=Bound` with an IP from the network's subnet means manager → Neutron works end to end.

---

## 2. Node scheduling note (read before the matrix)

kubetron webhook injects a `br-int` resource request, so pods only schedule onto nodes advertising
that resource. **But "has br-int" ≠ "can carry a full pod":** a pod only becomes truly ready when
its Neutron port turns `ACTIVE` (kubetron's `PortActive` readiness gate). On heterogeneous clusters
(e.g. real compute nodes + nested/incus "compute" nodes), constrain full pods to the node class
whose OVS/OVN data plane actually works — typically the real compute role:

```yaml
nodeSelector: { node-role.kubernetes.io/compute: "true" }
tolerations:  [ { key: node-role.kubernetes.io/compute, operator: Exists, effect: NoSchedule } ]
```

If a pod is stuck `NotReady` with condition `kubetron.network.kubevirt.io/PortActive=False`, its
port never went `ACTIVE` on that node — see [README Troubleshooting](./README.md#troubleshooting).

---

## 3. End-to-end test matrix (what we validated)

All of the following was run against the Helm deployment above. Summary of the result:

| Dimension | What it proves | Result |
|-----------|----------------|--------|
| Pod matrix — full form | single OVN nic = port IP, off the primary CNI, `dnsPolicy:None` | ✅ |
| Pod matrix — same-network | two pods on one tenant net reach each other | ✅ |
| Pod matrix — **cross-network isolation** | pods on two separate routers/nets are isolated | ✅ |
| Pod matrix — StatefulSet auto-mint | webhook auto-creates one claim per ordinal (§7) | ✅ |
| Pod matrix — probe rewrite | `httpGet` → exec-localhost (full pod podIP unreachable by kubelet) | ✅ |
| Pod matrix — cross-node | replicas spread across compute nodes | ✅ |
| **Service (Octavia OVN LB)** | VIP in a separate subnet, east-west, failover, cascade delete | **13/13** |
| **Floating IP (north-south)** | external client → FIP → pod, source-IP preserved, egress isolation | **9/9** |
| **VM (KubeVirt live-migration)** | VMI identity, double-bind window, migrate node, identity preserved | **20/20** |

### 3.1 Prepare tenant credential + two routers + two networks

kubetron's tenant boundary is the OpenStack **application credential**, not the namespace. Mint one
and store it in the shape the CRD expects (`authURL`, `applicationCredentialID`,
`applicationCredentialSecret`):

```console
# Run openstack CLI with the admin credential (e.g. a short-lived pod that mounts neutron-keystone-admin
# via envFrom, or your own openstack client). Then:
openstack application credential create kt-matrix-cred -f value -c id -c secret
#   -> <APPCRED_ID>  <APPCRED_SECRET>

kubectl create ns kt-matrix
kubectl -n kt-matrix create secret generic kt-matrix-cred \
  --from-literal=authURL="http://keystone-api.<openstack-ns>.svc.cluster.local:5000/v3" \
  --from-literal=applicationCredentialID="<APPCRED_ID>" \
  --from-literal=applicationCredentialSecret="<APPCRED_SECRET>"
```

Two routers + two tenant networks (each routed to the external net) — used for routing and
**cross-tenant isolation**:

```console
for X in a b; do
  R=kt-mtx-router-$X ; N=kt-mtx-net-$X
  [ "$X" = a ] && CIDR=10.100.1.0/24 || CIDR=10.100.2.0/24
  openstack router create $R
  openstack router set --external-gateway <external-net> $R
  openstack network create $N
  openstack subnet create ${N}-v4 --network $N --subnet-range $CIDR --dns-nameserver <resolver-ipv4>
  openstack router add subnet $R ${N}-v4
done
```

### 3.2 Pod matrix

Namespace ConfigMap (drives StatefulSet auto-mint), three explicit claims, three full pods, and a
StatefulSet:

```console
kubectl -n kt-matrix apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: { name: kubetron-network }
data: { network: kt-mtx-net-a, credentialSecretRef: kt-matrix-cred }
---
apiVersion: kubetron.network.kubevirt.io/v1alpha1
kind: NetworkPortClaim
metadata: { name: a1 }
spec: { network: kt-mtx-net-a, credentialSecretRef: kt-matrix-cred }
---
apiVersion: kubetron.network.kubevirt.io/v1alpha1
kind: NetworkPortClaim
metadata: { name: a2 }
spec: { network: kt-mtx-net-a, credentialSecretRef: kt-matrix-cred }
---
apiVersion: kubetron.network.kubevirt.io/v1alpha1
kind: NetworkPortClaim
metadata: { name: b1 }
spec: { network: kt-mtx-net-b, credentialSecretRef: kt-matrix-cred }
EOF
for c in a1 a2 b1; do kubectl -n kt-matrix wait npc/$c --for=jsonpath='{.status.phase}'=Bound --timeout=60s; done
```

Full pods `a1`,`a2` (net-a), `b1` (net-b) and an auto-minting StatefulSet — note the `enabled`
label + `port-claims` annotation (the StatefulSet uses the `$(ordinal)` placeholder):

```console
kubectl -n kt-matrix apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: a1, labels: { kubetron.network.kubevirt.io/enabled: "true" }, annotations: { kubetron.network.kubevirt.io/port-claims: a1 } }
spec:
  nodeSelector: { node-role.kubernetes.io/compute: "true" }
  tolerations: [ { key: node-role.kubernetes.io/compute, operator: Exists, effect: NoSchedule } ]
  containers: [ { name: app, image: <python-image>, command: ["python3","-m","http.server","8080"] } ]
---
# ...a2 (port-claims: a2, net-a) and b1 (port-claims: b1, net-b) identically...
---
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: web }
spec:
  serviceName: web
  replicas: 2
  selector: { matchLabels: { app: web } }
  template:
    metadata:
      labels: { app: web, kubetron.network.kubevirt.io/enabled: "true" }
      annotations: { kubetron.network.kubevirt.io/port-claims: "web-$(ordinal)-port" }
    spec:
      nodeSelector: { node-role.kubernetes.io/compute: "true" }
      tolerations: [ { key: node-role.kubernetes.io/compute, operator: Exists, effect: NoSchedule } ]
      containers: [ { name: app, image: <python-image>, command: ["python3","-m","http.server","8080"] } ]
EOF
```

Verify each dimension:

```console
# [full form] a1 has ONE nic = its OVN IP, and dnsPolicy:None resolver
kubectl -n kt-matrix exec a1 -- ip -o -4 addr show eth0
kubectl -n kt-matrix exec a1 -- cat /etc/resolv.conf | grep nameserver

A2=$(kubectl -n kt-matrix get npc a2 -o jsonpath='{.status.ips[0]}' | cut -d/ -f1)
B1=$(kubectl -n kt-matrix get npc b1 -o jsonpath='{.status.ips[0]}' | cut -d/ -f1)

# [same net]  a1 -> a2 reachable (TCP; ping needs ICMP opened in the SG — see §4)
kubectl -n kt-matrix exec a1 -- python3 -c "import socket;s=socket.socket();s.settimeout(4);s.connect(('$A2',8080));print('same-net OK')"

# [cross net] a1 -> b1 ISOLATED (two routers/nets)
kubectl -n kt-matrix exec a1 -- python3 -c "import socket;s=socket.socket();s.settimeout(4)
try: s.connect(('$B1',8080)); print('ISOLATION BROKEN')
except Exception: print('isolated OK')"

# [STS auto-mint] web-0-port / web-1-port were auto-created, ownerRef=StatefulSet
kubectl -n kt-matrix get npc web-0-port web-1-port -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,OWNER:.metadata.ownerReferences[0].kind

# [probe rewrite] a pod with an httpGet probe gets it rewritten to exec-localhost by the webhook
#   (create a pod with readinessProbe.httpGet and inspect .spec.containers[0].readinessProbe)

# [cross-node] replicas land on different compute nodes
kubectl -n kt-matrix get pod -l app=web -o wide
```

### 3.3 Service — Octavia OVN LoadBalancer (13 checks)

Use the upstream suite from the kubetron repo. It is self-contained (mints its own tenant, ensures
a routed service subnet, deploys backends, and verifies the LB end to end). It talks to the same
manager/webhook regardless of how kubetron was deployed:

```console
cd <kubetron-repo>
NET=<a-routed-tenant-network> bash tests/e2e-svc.sh
# Expected: SVC RESULT: PASS=13 FAIL=0
```

It proves: tenant app credential, service subnet ensured+routed, VIP allocated **in the service
subnet**, LB id persisted on the Service, east-west client→VIP serves a backend, failover on backend
deletion (EndpointSlice→member update), re-join on scale, and cascade LB delete on Service delete.

### 3.4 Floating IP — north-south (9 checks)

Override the tenant network / project to **your** test network so it never touches an
environment-owned tenant:

```console
cd <kubetron-repo>
FIP_NET=<your-test-net> \
FIP_PROJECT=<your-project-id> \
FIP_EXT_NET=<external-net-id> \
PUB_PROJECT=<external-net-owning-project-id> \
bash tests/e2e-fip.sh
# Expected: FIP RESULT: PASS=9 FAIL=0
```

It proves: SG applied Neutron-side to the port, full pod Ready, FIP allocated+associated, OVN
`dnat_and_snat` installed, **external client → FIP:8080 reaches the full pod**, source-IP preserved,
and full-pod egress isolation from the primary-CNI overlay.

### 3.5 VM — KubeVirt live migration (20 checks)

Requires KubeVirt ready (§0.4):

```console
cd <kubetron-repo>
NET=<a-tenant-network> bash tests/e2e-vm.sh
# Expected: VM RESULT: PASS=20 FAIL=0
```

It proves: per-claim NAD minted with `OvnPort`, VMI admitted+mutated (claim MAC injected), launcher
inherits the identity but is **not** mutated by the pod webhook, `host_id == launcher chassis`,
Neutron port ACTIVE, `pod → VM` over OVN, and a full live migration — double-bind window
(`migrationTargetPod` set), node actually changes, window closes, `host_id` converges to the target
chassis, **identity preserved (same portID)**, and `pod → VM` still works after migration.

---

## 4. Troubleshooting / lessons learned

- **Full pod `NotReady`, condition `PortActive=False`.** The Neutron port never went `ACTIVE` on
  its node. `kubectl get pod` showing `1/1 Running` is *container* readiness — check the pod's
  `Ready` condition and `openstack port show <portID> -c status`. Root causes below.
- **Port `DOWN` on some nodes only → `ovs-cni` didn't write `iface-id`.** On the affected node,
  `ovs-vsctl --columns=name,external_ids find interface external_ids:iface-id=<portID>` returns
  nothing and the pod's veth shows `external_ids : {}`. Almost always a **drifted `ovs-cni :latest`
  image** (different digest per node under `IfNotPresent`) — pin an immutable tag/digest and
  redeploy the `ovs-cni` DaemonSet so every node runs the same build.
- **Port `DOWN` on all nodes → chassis mismatch.** `controller.nodeChassisSuffix` must make
  `<nodeName><suffix>` equal the chassis hostname in `openstack network agent list`.
- **`ping` fails but TCP works.** Neutron default SG does not allow ICMP; kubetron does not manage
  SGs. Open ICMP in the port's SG if you need `ping`. Data-plane health is proven by TCP + port
  `ACTIVE`.
- **Never use `:latest` for kubetron or ovs-cni images.** See
  [README](./README.md#understanding-rolling-tags-versus-immutable-tags).

---

## 5. Cleanup

```console
# test workloads
kubectl delete ns kt-matrix
# test topology (only what you created)
for X in a b; do
  openstack router unset --external-gateway kt-mtx-router-$X
  openstack router remove subnet kt-mtx-router-$X kt-mtx-net-$X-v4
  openstack router delete kt-mtx-router-$X
  openstack network delete kt-mtx-net-$X
done
openstack application credential delete kt-matrix-cred

# the release (CRD is kept by default — crds.keep=true — to protect live claims)
helm uninstall kubetron -n kubetron-system
```

> The upstream `tests/e2e-*.sh` suites self-clean their own namespaces and Neutron objects
> (they use `kubetron-*e2e*` naming and never touch environment-owned resources).
