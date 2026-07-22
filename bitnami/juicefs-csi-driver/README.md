<!--- app-name: JuiceFS CSI Driver -->

# JuiceFS CSI Driver (Bitnami-style Helm Chart)

The JuiceFS CSI Driver provisions and mounts [JuiceFS](https://juicefs.com) volumes in Kubernetes. It runs in **mountpod mode**: a highly available controller (StatefulSet) provisions volumes, a node DaemonSet handles publish/unpublish, and each mounted volume is served by a dynamically-launched **mount pod** running the JuiceFS client. Applications consume volumes through standard PVCs with `ReadWriteOnce`, `ReadWriteMany`, or `ReadOnlyMany` access modes.

It is packaged following the [Bitnami common library](https://github.com/bitnami/charts/tree/main/bitnami/common) conventions (`common.*` helpers, `@section`/`@param` values, per-resource toggles, HA via PDB/anti-affinity/leader election).

## TL;DR

```console
# common is declared as a dependency; fetch it first
helm dependency build

helm install my-release . \
  --namespace juicefs --create-namespace \
  --set defaultMountImage.ce=<your-registry>/juicefs:<tag>
```

Then create a StorageClass (see [StorageClass and backend](#storageclass-and-backend)) and a PVC.

> The `common` chart is a declared dependency, **not vendored**. Run `helm dependency build` (or `helm dependency update`) before `helm install`/`helm template`, otherwise rendering fails with missing `common.*` templates.

## Introduction

Unlike in-kernel filesystems (CephFS, NFS), JuiceFS is a **FUSE/userspace** filesystem: the `juicefs mount` process *is* the filesystem, and it must stay alive for the whole life of the mount. This chart isolates that process into a per-(node × volume) **mount pod**, which brings:

- **Independent upgrades** — restarting/upgrading the CSI node plugin does not tear down running mounts.
- **Crash isolation** — one volume's mount failure does not affect other volumes or the node plugin.
- **Independent client image** — the CSI control plane and the mount pod use **different images** (see below).

### Two images, two roles

| Component | Image | Role |
| --------- | ----- | ---- |
| Controller + Node plugins | `image.*` (default `docker.io/juicedata/juicefs-csi-driver`) | Orchestration only — provisioning, publish/unpublish, launching mount pods. Never touches the backend storage. |
| **Mount pod** | `defaultMountImage.ce` | The JuiceFS client that performs the FUSE mount and connects to the metadata engine + object storage. **This is the data plane.** |

`defaultMountImage.ce` is the **fork touchpoint**: point it at a JuiceFS client image built with **ceph (RADOS) + TiKV** support so mount pods can reach that backend. The upstream CSI plugin image works as-is for the control plane.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8+
- A JuiceFS **volume already formatted** on your metadata engine + object storage (this chart mounts volumes; it does not format them)
- For the ceph + TiKV backend:
  - A reachable **TiKV/PD** cluster (`tikv://<pd>:2379/<volume>`)
  - A **Ceph** cluster with pool(s) and a cephx user; its `ceph.conf` + keyring provided as a Secret and injected into mount pods (see [Ceph config injection](#ceph-config-injection))
  - A JuiceFS client image built with **ceph + TiKV** support, set as `defaultMountImage.ce`

## Installing the Chart

```console
helm dependency build
helm install my-release . -n juicefs --create-namespace -f my-values.yaml
```

## Uninstalling the Chart

```console
helm uninstall my-release -n juicefs
```

This removes the Kubernetes objects. StorageClasses created by the chart are removed; **dynamically-provisioned PVs are governed by their `reclaimPolicy`**. It does not touch the JuiceFS volume data (metadata in TiKV, objects in Ceph) — that is external to the chart.

## Configuration and installation details

### Mount mode

`mountMode` selects how the JuiceFS client runs. This chart supports:

- `mountpod` (default, recommended) — one mount pod per (node × volume), managed by the node plugin.
- `process` — the client runs as a process inside the node plugin (`--by-process`). No mount pods; loses per-volume isolation.

`sidecar`/`serverless` modes need the upstream admission webhook and are out of scope.

### Resource naming and mode detection

The upstream driver binary picks its role by **substring-matching `POD_NAME`** against `csi-controller` / `csi-node`, and the controller locates node pods by the label `app=juicefs-csi-node` (with a hardcoded DaemonSet-name fallback). This chart wires all of that up for you:

- the StatefulSet is named `…-csi-controller`, the DaemonSet `…-csi-node`, so pod names carry the required substrings;
- node pods carry `app=juicefs-csi-node`;
- the controller gets `JUICEFS_CSI_NODE_DS_NAME` pointing at the DaemonSet.

If you set `fullnameOverride`, keep it such that the rendered names still contain `csi-controller`/`csi-node` (e.g. `fullnameOverride: juicefs` yields `juicefs-csi-controller` / `juicefs-csi-node`). This avoids the redundant `<release>-<chart>` prefix while satisfying the binary's expectations.

### StorageClass and backend

Each entry in `storageClasses` renders a StorageClass **plus** a backend Secret holding the JuiceFS format/mount parameters. For the ceph + TiKV backend:

```yaml
storageClasses:
  - name: juicefs-sc
    enabled: true
    reclaimPolicy: Delete
    allowVolumeExpansion: true
    backend:
      name: myjfs                                  # volume name
      metaurl: tikv://pd-host:2379/myjfs           # TiKV metadata engine
      storage: ceph
      bucket: ceph://juicefs-pool                  # Ceph pool
      accessKey: ceph                              # cephx user name
      secretKey: client.juicefs                    # cephx client id
      configs: "{ceph-client-conf: /etc/ceph}"     # inject ceph secret into mount pods
    mountOptions: []
    parameters: {}
```

Supported `backend` keys: `name`, `metaurl`, `storage`, `bucket`, `accessKey`, `secretKey`, `token`, `envs`, `configs`, `trashDays`, `formatOptions`. Set `existingSecret` on the StorageClass to reuse a pre-created backend Secret instead. Use `pathPattern` (requires `controller.provisioner=true`) to control the sub-directory layout of dynamically-provisioned volumes.

### Ceph config injection

Mount pods need `ceph.conf` + the cephx keyring to reach RADOS. Create that Secret yourself (so the keyring never lands in values), then reference it from the backend's `configs` field as `"{<secretName>: <mountPath>}"`, e.g. `"{ceph-client-conf: /etc/ceph}"`. The node plugin mounts the named Secret at that path inside every mount pod for the StorageClass.

### Mount pod recovery (important for durability)

When a mount pod dies (eviction, node pressure, an accidental `kubectl delete`), the node plugin **recreates it automatically**. For the recovered mount to propagate back into a running application pod **without restarting the app**, two things must be in place:

1. The `jfs-fuse-fd` hostPath (`/var/run/juicefs-csi`) — the chart wires this into the node DaemonSet by default.
2. The **application** pod must set `mountPropagation: HostToContainer` (or `Bidirectional`) on its volume mount. Without it, the app keeps seeing `Transport endpoint is not connected` until it is restarted.

Recovery typically restores I/O within ~20–30 s; data is not lost. See DEPLOY.md for a kill-and-recover demonstration.

Additionally, set `node.mountPodNonPreempting=true` to give mount pods a non-preempting priority class so the scheduler will not evict them under resource pressure.

### High availability

`controller.replicas` defaults to 2 with `controller.leaderElection.enabled=true`; `controller.pdb.create=true` and `controller.podAntiAffinityPreset=soft` keep replicas spread and available during upgrades. The node plugin is a DaemonSet (one per schedulable node) tolerating all taints by default.

### Rolling vs immutable mount image tags

Mount pods honor `imagePullPolicy: IfNotPresent`. If `defaultMountImage.ce` uses a **mutable** tag (e.g. `:main`), a node that already cached that tag will **not** re-pull an updated image. Pin an **immutable** tag (a commit-sha or version tag) so mount pods always run the intended build and updates are picked up cleanly.

### Kubelet directory

Set `kubeletDir` to match your distribution (e.g. `/var/lib/k0s/kubelet` for k0s, `/var/snap/microk8s/common/var/lib/kubelet` for microk8s). The default is `/var/lib/kubelet`.

### Snapshots

`snapshot.enabled=true` adds the `csi-snapshotter` sidecar and RBAC. It requires the external snapshot CRDs and controller installed cluster-wide.

## Parameters

### Global parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `global.imageRegistry` | Global Docker image registry | `""` |
| `global.imagePullSecrets` | Global Docker registry secret names as an array | `[]` |
| `global.security.allowInsecureImages` | Allows skipping image verification | `false` |
| `global.compatibility.openshift.adaptSecurityContext` | Adapt securityContext for Openshift. Possible values: auto, force, disabled | `auto` |

### Common parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `nameOverride` | String to partially override common.names.fullname | `""` |
| `namespaceOverride` | String to fully override common.names.namespace | `""` |
| `fullnameOverride` | String to fully override common.names.fullname (keep it containing csi-controller/csi-node compatible names) | `""` |
| `commonLabels` | Labels to add to all deployed objects | `{}` |
| `commonAnnotations` | Annotations to add to all deployed objects | `{}` |
| `clusterDomain` | Default Kubernetes cluster domain | `cluster.local` |
| `extraDeploy` | Array of extra objects to deploy with the release | `[]` |
| `kubeVersion` | Force target Kubernetes version (using Helm capabilities if not set) | `""` |

### CSI driver parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `driverName` | Name of the CSIDriver object applications reference | `csi.juicefs.com` |
| `mountMode` | How the JuiceFS client runs: `mountpod` (default) or `process` | `mountpod` |
| `image.registry` | CSI plugin image registry | `docker.io` |
| `image.repository` | CSI plugin image repository | `juicedata/juicefs-csi-driver` |
| `image.tag` | CSI plugin image tag | `v0.32.0` |
| `image.digest` | CSI plugin image digest (overrides tag if set) | `""` |
| `image.pullPolicy` | CSI plugin image pull policy | `IfNotPresent` |
| `image.pullSecrets` | CSI plugin image pull secrets | `[]` |
| `defaultMountImage.ce` | Community Edition mount pod image — **set to your fork's ceph + TiKV build** | `""` |
| `defaultMountImage.ee` | Enterprise Edition mount pod image (leave empty for CE) | `""` |
| `sidecars.livenessProbeImage.*` | livenessprobe sidecar image | `registry.k8s.io/sig-storage/livenessprobe:v2.12.0` |
| `sidecars.nodeDriverRegistrarImage.*` | node-driver-registrar sidecar image | `registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.9.0` |
| `sidecars.csiProvisionerImage.*` | csi-provisioner sidecar image (used when `controller.provisioner=false`) | `registry.k8s.io/sig-storage/csi-provisioner:v3.6.3` |
| `sidecars.csiResizerImage.*` | csi-resizer sidecar image | `registry.k8s.io/sig-storage/csi-resizer:v1.9.0` |
| `kubeletDir` | kubelet root directory (adjust for k0s/microk8s/etc.) | `/var/lib/kubelet` |
| `jfsMountDir` | Host directory where JuiceFS mount points live | `/var/lib/juicefs/volume` |
| `jfsConfigDir` | Host directory for JuiceFS client config | `/var/lib/juicefs/config` |
| `hostAliases` | Pod host aliases for both controller and node | `[]` |

### CSIDriver object parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `csidriver.disableHooks` | Disable Helm hooks on the CSIDriver object (useful for ArgoCD/GitOps) | `false` |
| `csidriver.annotations` | Additional annotations for the CSIDriver object | `{}` |

### Global configuration (ConfigMap) parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `globalConfig.enabled` | Create the JuiceFS CSI driver global config ConfigMap | `true` |
| `globalConfig.manageByHelm` | Let Helm manage (update) the global config; if false, applied only on first install | `true` |
| `globalConfig.enableNodeSelector` | Schedule mount pods via nodeSelector rather than nodeName | `false` |
| `globalConfig.mountPodPatch` | Recursively-merged patches to the mount pod spec (per pvcSelector) | `[]` |

### Controller (provisioner) parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `controller.enabled` | Deploy the CSI controller | `true` |
| `controller.replicas` | Number of controller replicas (HA with leader election) | `2` |
| `controller.debug` | Enable verbose controller logging | `false` |
| `controller.provisioner` | Use the built-in provisioner (required for pathPattern); disables the external sidecar | `true` |
| `controller.provisionWorkerThreads` | Number of provisioner worker threads | `100` |
| `controller.cacheClientConf` | Cache client auth config in the user's secret (EE only) | `true` |
| `controller.leaderElection.enabled` | Enable controller leader election | `true` |
| `controller.leaderElection.leaderElectionNamespace` | Namespace for the leader election lease | `""` |
| `controller.leaderElection.leaseDuration` | Lease duration for leader election | `""` |
| `controller.metricsPort` | Controller metrics port | `9567` |
| `controller.terminationGracePeriodSeconds` | Grace period before the controller pod is killed | `30` |
| `controller.podLabels` | Extra labels for controller pods | `{}` |
| `controller.podAnnotations` | Annotations for controller pods | `{}` |
| `controller.podAntiAffinityPreset` | Pod anti-affinity preset to spread controller replicas (soft/hard) | `soft` |
| `controller.affinity` | Affinity for controller pods (overrides the preset) | `{}` |
| `controller.nodeSelector` | Node selector for controller pods | `{}` |
| `controller.tolerations` | Tolerations for controller pods | `[CriticalAddonsOnly]` |
| `controller.priorityClassName` | Controller pods priority class name | `system-cluster-critical` |
| `controller.resourcesPreset` | Controller resources preset (ignored if resources is set) | `medium` |
| `controller.resources` | Explicit controller resources (overrides preset) | `{}` |
| `controller.service.type` | Controller metrics service type | `ClusterIP` |
| `controller.service.port` | Controller metrics service port | `9909` |
| `controller.extraEnvVars` | Extra environment variables for the controller plugin container | `[]` |
| `controller.pdb.create` | Create a PodDisruptionBudget for the controller | `true` |
| `controller.pdb.minAvailable` | Minimum available controller pods | `""` |
| `controller.pdb.maxUnavailable` | Maximum unavailable controller pods (defaults to 1) | `""` |

### Node (DaemonSet) parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `node.enabled` | Deploy the CSI node DaemonSet | `true` |
| `node.debug` | Enable verbose node logging | `false` |
| `node.hostNetwork` | Run the node pods on the host network | `false` |
| `node.sidecarPrivileged` | Run node-driver-registrar and liveness-probe privileged (e.g. SELinux) | `false` |
| `node.mountPodNonPreempting` | Give mount pods a non-preempting priority class (recommended) | `false` |
| `node.ifPollingKubelet` | Poll the kubelet for mount pod state (sets HOST_IP/KUBELET_PORT) | `false` |
| `node.driverRegistrarLogLevel` | Log verbosity for node-driver-registrar (--v) | `5` |
| `node.updateStrategy.type` | Node DaemonSet update strategy type | `RollingUpdate` |
| `node.updateStrategy.rollingUpdate` | Node DaemonSet rolling update config | `{maxUnavailable: 1}` |
| `node.podLabels` | Extra labels for node pods | `{}` |
| `node.podAnnotations` | Annotations for node pods | `{}` |
| `node.nodeSelector` | Node selector for node pods | `{}` |
| `node.tolerations` | Tolerations for node pods (default tolerates all) | `[operator: Exists]` |
| `node.priorityClassName` | Node pods priority class name | `system-node-critical` |
| `node.resourcesPreset` | Node resources preset (ignored if resources is set) | `medium` |
| `node.resources` | Explicit node resources (overrides preset) | `{}` |
| `node.extraEnvVars` | Extra environment variables for the node plugin container | `[]` |

### RBAC parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `serviceAccount.controller.create` | Create the controller ServiceAccount | `true` |
| `serviceAccount.controller.name` | Name of the controller ServiceAccount | `""` |
| `serviceAccount.controller.annotations` | Annotations for the controller ServiceAccount | `{}` |
| `serviceAccount.node.create` | Create the node ServiceAccount | `true` |
| `serviceAccount.node.name` | Name of the node ServiceAccount | `""` |
| `serviceAccount.node.annotations` | Annotations for the node ServiceAccount | `{}` |
| `rbac.create` | Create the ClusterRoles/Bindings the driver needs | `true` |

### Snapshot parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `snapshot.enabled` | Enable volume snapshot support (adds csi-snapshotter sidecar + RBAC; requires snapshot CRDs) | `false` |

### StorageClass parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `storageClasses` | Array of StorageClasses to create, each with its JuiceFS backend secret | `[]` |

Per-entry `storageClasses[*]` keys: `name`, `enabled`, `reclaimPolicy` (default `Delete`), `allowVolumeExpansion` (default `true`), `volumeBindingMode` (default `Immediate`), `existingSecret`, `pathPattern`, `annotations`, `mountOptions`, `parameters`, and `backend.{name,metaurl,storage,bucket,accessKey,secretKey,token,envs,configs,trashDays,formatOptions}`.

## Troubleshooting

- **`juicefs-plugin` container exits 0 immediately (CrashLoopBackOff, `Completed`, no logs)** — the binary detects its mode by matching `POD_NAME` against `csi-controller`/`csi-node`. The chart's default names satisfy this; if you `fullnameOverride`, ensure the rendered pod names still contain those substrings.
- **Controller `os.Exit(1)`: "Can't get CSI pods or DaemonSet"** — the controller locates node pods by `app=juicefs-csi-node` and a DaemonSet-name fallback. The chart sets both the label and `JUICEFS_CSI_NODE_DS_NAME`; if you renamed the node ServiceAccount, refresh in-flight mount pods (see below).
- **Mount pod fails: `/bin/mount.juicefs: not found`** — the mount pod issues `mount -t juicefs`, which dispatches to `mount.juicefs` on PATH. The mount image must symlink `mount.juicefs` to the `juicefs` binary (present in official images and this fork's image).
- **App pod I/O errors `Transport endpoint is not connected` after a mount pod restart** — set `mountPropagation: HostToContainer` on the application's volume mount so the recovered mount propagates back in without an app restart.
- **Mount pod stuck `Failed`, recreation blocked by "serviceaccount … not found"** — mount pods created before a ServiceAccount rename reference the old SA. Refresh them by restarting their consumer app pods (fresh NodePublish creates a mount pod with the current SA).
- **Mount pod not re-pulling an updated `:main` image** — `IfNotPresent` reuses the cached image for a mutable tag. Pin an immutable (sha/version) tag.

## License

Apache-2.0.
