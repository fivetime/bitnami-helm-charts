<!--- app-name: kubetron -->

# kubetron packaged by Broadcom

kubetron is a thin Kubernetes-to-Neutron/Octavia orchestration layer that gives standard, unmodified Kubernetes/Helm workloads a VM-like persistent network identity on OpenStack OVN tenant networks. It reconciles `NetworkPortClaim` resources into Neutron ports, injects Multus attachments through an admission webhook, wires Services to Octavia OVN load balancers, and can optionally serve claims from its own aggregated apiserver.

## TL;DR

```console
helm install my-release oci://REGISTRY_NAME/REPOSITORY_NAME/kubetron
```

> Look up `REGISTRY_NAME` and `REPOSITORY_NAME` in the deployment prerequisites.

## Introduction

This chart bootstraps a [kubetron](https://github.com/fivetime/kubetron) control plane on a [Kubernetes](https://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

kubetron does **not** replace your primary CNI. It is an orchestration layer: the K8s control plane stays authoritative for scheduling/health/EndpointSlices, while the data plane lives entirely in OVN (reached through Neutron/Octavia). Pods enrolled into kubetron are attached to an OVN logical switch through `ovs-cni` (via Multus), which structurally isolates each tenant.

## Understanding rolling tags versus immutable tags

It is strongly recommended to use immutable tags in a production environment. This ensures your deployment does not change automatically if the same tag is updated with a different image. **This applies not only to the kubetron image but especially to `ovs-cni` on your nodes** — kubetron depends on `ovs-cni` writing `external_ids:iface-id` on each pod's OVS interface, and a `:latest` `ovs-cni` image with `imagePullPolicy: IfNotPresent` can leave different nodes frozen on different historical builds, so a pod's Neutron port silently stays `DOWN` on the nodes that cached an older build. Pin `ovs-cni` (and kubetron) to an immutable tag or a `@sha256:` digest.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8.0+
- [Multus CNI](https://github.com/k8snetworkplumbingwg/multus-cni) and [ovs-cni](https://github.com/k8snetworkplumbingwg/ovs-cni) (with its marker DaemonSet) installed and healthy on the cluster
- Reachable OpenStack Neutron/Octavia APIs, and an admin application credential provided as a Secret (default name `neutron-keystone-admin`)
- When `webhook.certManager.enabled=true` (the default): [cert-manager](https://cert-manager.io) plus the referenced issuer (default `ClusterIssuer/cluster-internal-ca-issuer`)

## Installing the Chart

Provide the OpenStack admin credential Secret first (keys follow the `OS_*` convention, as published by OpenStack-Helm's `neutron-keystone-admin` Secret), then install:

```console
helm install my-release oci://REGISTRY_NAME/REPOSITORY_NAME/kubetron \
  --namespace kubetron-system --create-namespace \
  --set openstack.existingSecret=neutron-keystone-admin
```

These commands deploy kubetron on the Kubernetes cluster in the default configuration: a highly available (2-replica, leader-elected) manager, the `NetworkPortClaim` CRD, the admission webhooks, RBAC, a PodDisruptionBudget and a NetworkPolicy.

> **Tip**: List all releases using `helm list`

## Uninstalling the Chart

To uninstall/delete the `my-release` deployment:

```console
helm uninstall my-release --namespace kubetron-system
```

By default (`crds.keep=true`) the `NetworkPortClaim` CRD is annotated with `helm.sh/resource-policy: keep`, so existing claims survive an uninstall. Delete the CRD manually if you really want to remove them.

## Architecture

The chart deploys two components:

| Component | Default | Description |
|-----------|---------|-------------|
| **manager** | always on | controller-runtime Deployment. Reconciles `NetworkPortClaim` → Neutron port, runs the mutating admission webhooks (Pod / claim / VMI), reconciles Service → Octavia OVN LB, and stamps shard labels. HA via leader election. |
| **apiserver** | opt-in (`apiserver.enabled=true`) | Aggregated apiserver that serves `NetworkPortClaim` from kubetron's **own** etcd (bundled StatefulSet) instead of the CRD. For very large deployments where claim storage / watch fan-out should leave the core apiserver. |

The CRD and the aggregated apiserver are **mutually exclusive** — enabling the apiserver serves the same API group that the CRD would, so set `crds.install=false` when `apiserver.enabled=true`. Migrating a live cluster between the two modes is a deliberate data migration (see the upstream `DESIGN §10.5`).

### Sharding: one release per Neutron/OVN cluster

kubetron scales horizontally by **sharding per Neutron/OVN cluster** (upstream `DESIGN §10.3`: *"分片边界 = 一个 Neutron/OVN 集群"*). A shard is **not** just a scheduling slice — each shard talks to its **own** Neutron API endpoint with its **own** admin credentials, and cross-shard L3 is handled by `ovn-ic-central`. Adding a cluster is a discrete, linear step: add Neutron + a kubetron shard + wire it into OVN-IC.

Because each shard is a distinct backend with distinct credentials, the natural unit is **one Helm release per Neutron/OVN cluster** — every release runs its own manager (`controller.shard`, `openstack.*`, `nodeSelector`, …) and can be upgraded/rolled back independently. The **cluster-singleton** resources (the CRD, the admission webhook + its serving certificate and Service, the aggregated apiserver, and the cluster-scoped RBAC/ServiceAccount) are created by exactly **one** owner release and shared by the rest.

**Single cluster** (the common case): install one release with the defaults — it owns the shared resources and runs the manager. Nothing else to do.

**Multiple clusters**:

```console
# 1) Owner release: shared control plane + the manager for cluster-1
helm install kubetron oci://REGISTRY_NAME/REPOSITORY_NAME/kubetron \
  --namespace kubetron-system --create-namespace \
  --set controller.shard=cluster1 \
  --set openstack.existingSecret=neutron-admin-cluster1 \
  --set openstack.networkEndpointOverride=http://neutron-server.cluster1.svc:9696/

# 2) Follower release(s): manager only, attached to the owner's shared control plane
helm install kubetron-c2 oci://REGISTRY_NAME/REPOSITORY_NAME/kubetron \
  --namespace kubetron-system \
  --set sharedResources.create=false \
  --set controlPlaneName=kubetron \
  --set controller.shard=cluster2 \
  --set openstack.existingSecret=neutron-admin-cluster2 \
  --set openstack.networkEndpointOverride=http://neutron-server.cluster2.svc:9696/
```

A follower (`sharedResources.create=false`) deploys **only** its manager, PodDisruptionBudget and NetworkPolicy; it reuses the owner's ServiceAccount, serving certificate and webhook Service (matched via a cross-release control-plane label, independent of the release name). `controlPlaneName` must equal the owner's fullname, and all releases must share one namespace. A claim is routed to a shard by its namespace's `kubetron-network` ConfigMap (`shard` key). This pairs naturally with GitOps (one argo Application per cluster) or an argo ApplicationSet.

### Several Kubernetes clusters on one Neutron/OVN

Nodes of two (or more) Kubernetes clusters can join the **same** OVN: each node's
`ovn-controller` points at the same OVN SB and their tunnel endpoints are mutually
routable. Pods then share tenant logical switches across clusters and reach each other
directly at L2 — Cilium ClusterMesh is *not* required for that, since full Pods are off
the cluster CNI entirely. (ClusterMesh remains useful for **dual-attached** Pods, whose
`eth0` stays on Cilium: with a global Service they can also reach K8s Services in the
other cluster.)

In that topology **every installation must set `controller.clusterID`, and each cluster
must use a different value.** The orphan collectors query Neutron and Octavia
cluster-wide, but a given installation can only see the claims and Services of its own
Kubernetes cluster — so another cluster's live port or load balancer is indistinguishable
from an orphan and would be deleted. `clusterID` scopes ownership
(`device_owner=kubetron:<id>`, `kubetron_<id>_<ns>_<svc>`) so each installation reclaims
only what it created. Two further constraints apply:

- **Node names must be unique across the clusters**, because the OVN chassis name is
  derived from the node name (plus `controller.nodeChassisSuffix`); a collision points
  `binding:host_id` at the wrong machine.
- A Service's load balancer only carries **its own cluster's** endpoints. A VIP fronting
  Pods from both clusters is reachable at the data-plane level (the OVN load balancer is
  attached to the logical switch, which knows nothing about Kubernetes), but has to be
  created out of band.

Unlike `controller.shard`, which differs per release, `clusterID` is a property of the
Kubernetes cluster: **all releases in the same cluster must share the same value.**

## Enrolling a workload

Label the workload's Pods (or the StatefulSet / VMI template) and reference a claim:

```yaml
apiVersion: kubetron.network.kubevirt.io/v1alpha1
kind: NetworkPortClaim
metadata:
  name: my-app
  namespace: my-namespace
spec:
  network: my-tenant-network        # Neutron network name or id
  credentialSecretRef: my-tenant-credential   # Secret with the tenant app credential
---
# Pod / StatefulSet template metadata:
#   labels:
#     kubetron.network.kubevirt.io/enabled: "true"
#   annotations:
#     kubetron.network.kubevirt.io/port-claims: my-app
```

List claims with `kubectl get networkportclaims -A` (short name `npc`).

## Parameters

The chart is fully parameterised; every value is documented inline in [`values.yaml`](./values.yaml). The most relevant knobs:

### Common parameters

| Name                | Description                                                              | Value           |
| ------------------- | ------------------------------------------------------------------------ | --------------- |
| `kubeVersion`       | Force target Kubernetes version (using Helm capabilities if not set)      | `""`            |
| `nameOverride`      | String to partially override kubetron.fullname                           | `""`            |
| `fullnameOverride`  | String to fully override kubetron.fullname                               | `""`            |
| `namespaceOverride` | String to fully override the namespace                                   | `""`            |
| `controlPlaneName`  | Name of the shared control plane to attach to (cross-release wiring)     | `""`            |
| `sharedResources.create` | Create the cluster-singleton resources (owner release only)         | `true`          |
| `commonLabels`      | Labels to add to all deployed resources                                  | `{}`            |
| `commonAnnotations` | Annotations to add to all deployed resources                             | `{}`            |
| `extraDeploy`       | Array of extra objects to deploy with the release                        | `[]`            |

### Image parameters

| Name                | Description                        | Value                |
| ------------------- | ---------------------------------- | -------------------- |
| `image.registry`    | kubetron image registry            | `ghcr.io`            |
| `image.repository`  | kubetron image repository          | `fivetime/kubetron`  |
| `image.tag`         | kubetron image tag                 | `0.11.9`             |
| `image.pullPolicy`  | kubetron image pull policy         | `IfNotPresent`       |
| `image.pullSecrets` | kubetron image pull secrets        | `[]`                 |

### OpenStack connection parameters

| Name                                | Description                                                                       | Value                                                        |
| ----------------------------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `openstack.existingSecret`          | Secret with the admin OpenStack credentials (envFrom, `OS_*` keys)                | `neutron-keystone-admin`                                     |
| `openstack.domainNameSecretKey`     | Key in `existingSecret` to project into `OS_DOMAIN_NAME`                          | `OS_PROJECT_DOMAIN_NAME`                                     |
| `openstack.networkEndpointOverride` | Pin the Neutron endpoint (bypass the Keystone catalog alias)                      | `http://neutron-server.openstack.svc.cluster.local:9696/`   |

### Manager (controller + webhook) parameters

| Name                                  | Description                                                                | Value            |
| ------------------------------------- | -------------------------------------------------------------------------- | ---------------- |
| `replicaCount`                        | Number of manager replicas for this release/shard (hot standbys)           | `2`              |
| `controller.shard`                    | This release's shard = the Neutron/OVN cluster it manages                  | `default`        |
| `controller.clusterID`                | Identity of THIS K8s cluster; set only when several kubetron installations share one Neutron/Octavia (scopes port ownership + LB names so each GC reclaims only its own) | `""`             |
| `controller.enforceShardPlacement`    | Inject a shard nodeSelector into full Pods so they cannot land on another shard's OVN nodes | `false`          |
| `controller.leaderElect`              | Enable leader election (required when `replicaCount > 1`)                   | `true`           |
| `controller.gcInterval`               | Orphan Neutron port garbage-collector interval                             | `5m`             |
| `controller.nodeChassisSuffix`        | Suffix appended to the node name to form the OVN chassis hostname          | `""`             |
| `controller.defaultDNSNameservers`    | Placeholder resolver(s) for full Pods' `dnsPolicy:None`                     | `[]`             |
| `resourcesPreset`                     | Manager resources preset                                                    | `micro`          |
| `resources`                           | Manager resource requests/limits (recommended for production)              | `{}`             |
| `pdb.create`                          | Create a PodDisruptionBudget for the manager                               | `true`           |
| `autoscaling.enabled`                 | Enable Horizontal Pod Autoscaling for the manager                          | `false`          |

### Webhook and TLS parameters

| Name                             | Description                                                            | Value                          |
| -------------------------------- | --------------------------------------------------------------------- | ------------------------------ |
| `webhook.failurePolicy`          | Admission failure policy (`Fail`/`Ignore`)                            | `Fail`                         |
| `webhook.pods.enabled`           | Register the Pod mutating webhook                                     | `true`                         |
| `webhook.claims.enabled`         | Register the NetworkPortClaim mutating webhook (shard stamping)       | `true`                         |
| `webhook.vm.enabled`             | Register the KubeVirt VMI mutating webhook                            | `true`                         |
| `webhook.certManager.enabled`    | Issue serving certs with cert-manager (else Helm self-signed)         | `true`                         |
| `webhook.certManager.issuerRef.kind` | cert-manager issuer kind                                          | `ClusterIssuer`                |
| `webhook.certManager.issuerRef.name` | cert-manager issuer name                                          | `cluster-internal-ca-issuer`   |

### CRD and aggregated apiserver parameters

| Name                             | Description                                                            | Value            |
| -------------------------------- | --------------------------------------------------------------------- | ---------------- |
| `crds.install`                   | Install the NetworkPortClaim CRD                                      | `true`           |
| `crds.keep`                      | Keep the CRD on `helm uninstall`                                      | `true`           |
| `apiserver.enabled`              | Deploy the aggregated apiserver + etcd instead of the CRD            | `false`          |
| `apiserver.replicaCount`         | Aggregated apiserver replicas                                         | `2`              |
| `apiserver.etcd.replicaCount`    | Bundled etcd replicas (use an odd number for quorum)                 | `1`              |
| `apiserver.etcd.persistence.size`| Size of the etcd PVC                                                  | `8Gi`            |

### Metrics and NetworkPolicy parameters

| Name                             | Description                                                            | Value            |
| -------------------------------- | --------------------------------------------------------------------- | ---------------- |
| `metrics.enabled`                | Expose Prometheus metrics                                             | `true`           |
| `metrics.serviceMonitor.enabled` | Create a Prometheus Operator ServiceMonitor                          | `false`          |
| `networkPolicy.enabled`          | Create a NetworkPolicy for the manager                               | `true`           |

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`, or provide a YAML file with `-f values.yaml`. See [`values.yaml`](./values.yaml) for the complete, documented parameter set.

For an end-to-end, real-world deployment walkthrough and the full validation test matrix, see [DEPLOY.md](./DEPLOY.md).

## Troubleshooting

- **A full pod stays `NotReady` with condition `kubetron.network.kubevirt.io/PortActive=False`.** This is by design: kubetron injects a readiness gate that only turns True once the pod's Neutron port is `ACTIVE` (i.e. `ovn-controller` has programmed the flows on the node's `br-int` and set `external_ids:ovn-installed=true`). A pod that is `1/1 Running` in `kubectl get pod` (that column is *container* readiness) but whose pod `Ready` condition is False has a data plane that is not up. Inspect the claim's port with `openstack port show <portID> -c status` — `DOWN` means the node did not bind it.

- **The port is `DOWN` on some nodes but `ACTIVE` on others.** The node's `ovs-cni` did not write `external_ids:iface-id` on the pod's OVS interface, so `ovn-controller` cannot match it to a logical port. The usual cause is `ovs-cni` running an inconsistent/older build on those nodes (a `:latest` tag drifting across nodes — see [Understanding rolling tags versus immutable tags](#understanding-rolling-tags-versus-immutable-tags)) or a node type where the `OvnPort` cni-arg is not delivered. Verify with `ovs-vsctl --columns=name,external_ids find interface external_ids:iface-id=<portID>` on the node's OVS.

- **The node running the chassis must match `controller.nodeChassisSuffix`.** kubetron writes `binding:host_id = <nodeName><nodeChassisSuffix>`; that value must equal the `hostname` the node's `ovn-controller` registers as its chassis, or OVN will not admit the port. Confirm with `openstack network agent list` (the `Host` column).

- **`ping` fails but TCP works between pods on the same network.** That is the Neutron security group, not the data plane — the default SG does not allow ICMP. kubetron does not manage security groups (tenants self-serve them in Neutron); open ICMP in the port's SG if you need `ping`.

## License

Copyright &copy; Broadcom, Inc. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at <http://www.apache.org/licenses/LICENSE-2.0>.
