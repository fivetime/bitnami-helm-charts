<!--- app-name: JuiceFS Operator -->

# JuiceFS Operator (Bitnami-style Helm Chart)

The JuiceFS Operator manages JuiceFS **cache groups**, **warmups**, and **sync jobs** through Kubernetes custom resources (`CacheGroup`, `WarmUp`, `Sync`, `CronSync` under `juicefs.io/v1`). It runs a highly available controller-manager (leader-elected) that reconciles those CRs into worker pods and jobs.

It is packaged following the [Bitnami common library](https://github.com/bitnami/charts/tree/main/bitnami/common) conventions (`common.*` helpers, `@section`/`@param` values, per-resource toggles, HA via PDB/anti-affinity/leader election).

## TL;DR

```console
# common is declared as a dependency; fetch it first
helm dependency build

helm install my-release . --namespace juicefs --create-namespace
```

Then create a `Sync`/`CronSync` (Community Edition) or `CacheGroup`/`WarmUp` (Enterprise Edition) custom resource.

> The `common` chart is a declared dependency, **not vendored**. Run `helm dependency build` (or `helm dependency update`) before `helm install`/`helm template`, otherwise rendering fails with missing `common.*` templates.

## Introduction

The operator itself only talks to the Kubernetes API server — it never touches your metadata engine or object storage. It reconciles CRs into **worker pods/jobs** that run the JuiceFS client image you specify per-CR (`spec.image` on `Sync`, `spec.worker.template.image` on `CacheGroup`). Point those at a JuiceFS client image built with your backend support (e.g. this fork's ceph + TiKV build).

### Community Edition vs Enterprise Edition

This distinction matters for which CRs are usable:

| CR | Edition | What it does |
| -- | ------- | ------------ |
| `Sync` / `CronSync` | **CE and EE** | Run `juicefs sync` between two storages (one-off or on a cron schedule). |
| `CacheGroup` | **EE only** | Manage a distributed cache group (worker pods sharing cache via `juicefs mount --cache-group`). |
| `WarmUp` | **EE only** | Pre-populate a cache group's cache for given paths. |

Community Edition `juicefs mount` has **local cache** (`--cache-dir`/`--cache-size`) but **no `--cache-group`** — distributed cache groups are an Enterprise feature. A `CacheGroup`/`WarmUp` CR backed by a CE secret fails to reconcile with `token is missing` (the operator expects an EE token). On CE, use `Sync`/`CronSync`.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8+
- A JuiceFS **volume already formatted** (the operator does not format volumes)
- A JuiceFS client image with your backend support for worker pods (`spec.image` per CR)
- For Ceph-backed CE volumes: the `ceph.conf` + keyring available as a Secret, injected into worker pods via the CR (`extraVolumes`)
- For `CacheGroup`/`WarmUp`: a JuiceFS **Enterprise** token in the referenced secret

## Installing the Chart

```console
helm dependency build
helm install my-release . -n juicefs --create-namespace -f my-values.yaml
```

The four CRDs are installed from the chart's `crds/` directory on first install. Helm does **not** upgrade or delete CRDs automatically — manage CRD upgrades out-of-band.

## Uninstalling the Chart

```console
helm uninstall my-release -n juicefs
```

This removes the operator and its RBAC. It leaves the CRDs and any custom resources in place (delete those first if you want them gone). It does not touch JuiceFS volume data.

## Configuration and installation details

### Worker image (the backend touchpoint)

The operator (`image.*`) uses the upstream `juicedata/juicefs-operator` image and only reconciles CRs. The **actual data work** happens in worker pods, whose image is set **per custom resource** — `spec.image` on `Sync`, `spec.worker.template.image` on `CacheGroup`. Point those at your fork's ceph + TiKV client image.

### High availability

`replicaCount` defaults to 2 with `leaderElection.enabled=true`: one replica is active, the rest stand by for failover. `pdb.create=true` and `podAntiAffinityPreset=soft` keep replicas spread and the active controller available during disruptions.

### Reconcile concurrency and API load

`options.*` tune the controller's concurrency and API client rate limits (`maxSyncConcurrentReconciles`, `maxCgConcurrentReconciles`, `maxWarmupConcurrentReconciles`, `k8sClientQPS`, `k8sClientBurst`). `options.watchNamespaces` (image ≥ v0.7.0) restricts which namespaces the operator watches (empty = all).

### Resource naming

Set `fullnameOverride` to avoid the redundant `<release>-<chart>` prefix — e.g. `fullnameOverride: juicefs-operator` yields `juicefs-operator`, `juicefs-operator-manager`, etc.

### Metrics

`metrics.enabled=true` exposes the controller-manager metrics endpoint (`metrics.port`, default `8080`). `metrics.serviceMonitor.enabled=true` adds a Prometheus Operator ServiceMonitor.

### CSI dashboard (optional web UI)

`dashboard.enabled=true` deploys the JuiceFS CSI dashboard (`juicedata/csi-dashboard`) — a web UI over the CSI driver's mount pods and the operator's CRs. It is basic-auth protected (`dashboard.auth.*`; password auto-generated when empty). This is independent of the operator's core function.

### Security context

The operator runs as non-root (`runAsUser: 1001`) with a read-only root filesystem and all capabilities dropped. Worker pods launched from CRs have their own security context defined in the CR.

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
| `fullnameOverride` | String to fully override common.names.fullname | `""` |
| `commonLabels` | Labels to add to all deployed objects | `{}` |
| `commonAnnotations` | Annotations to add to all deployed objects | `{}` |
| `clusterDomain` | Default Kubernetes cluster domain | `cluster.local` |
| `extraDeploy` | Array of extra objects to deploy with the release | `[]` |
| `kubeVersion` | Force target Kubernetes version (using Helm capabilities if not set) | `""` |

### Operator image parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `image.registry` | Operator image registry | `docker.io` |
| `image.repository` | Operator image repository | `juicedata/juicefs-operator` |
| `image.tag` | Operator image tag | `v0.8.4` |
| `image.digest` | Operator image digest (overrides tag if set) | `""` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `image.pullSecrets` | Docker registry secret names as an array | `[]` |

### Operator deployment parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `replicaCount` | Number of operator replicas. With leaderElection, extras stand by for failover | `2` |
| `logLevel` | Log verbosity: debug, info, error, or a positive integer | `info` |
| `logEncoder` | Log encoding: json or console | `console` |
| `leaderElection.enabled` | Enable leader election so only one replica is active | `true` |
| `options.maxSyncConcurrentReconciles` | Max concurrent reconciles for the sync controller | `10` |
| `options.maxWarmupConcurrentReconciles` | Max concurrent reconciles for the warmup controller | `10` |
| `options.maxCgConcurrentReconciles` | Max concurrent reconciles for the cache group controller | `10` |
| `options.updateWarmupStatsInterval` | Interval to update warmup stats | `5s` |
| `options.k8sClientQPS` | Max QPS to the API server from this client | `30` |
| `options.k8sClientBurst` | Max burst for throttle | `20` |
| `options.watchNamespaces` | Comma-separated namespaces to watch (empty = all; image ≥ v0.7.0) | `""` |
| `extraArgs` | Additional raw arguments for the controller-manager | `[]` |
| `extraEnvVars` | Array of extra environment variables for the operator container | `[]` |
| `command` | Override the operator container command | `[]` |
| `automountServiceAccountToken` | Mount the ServiceAccount token in the operator pod (required) | `true` |
| `podLabels` | Extra labels for operator pods | `{}` |
| `podAnnotations` | Annotations for operator pods | `{}` |
| `podAffinityPreset` | Pod affinity preset. Allowed values: soft, hard | `""` |
| `podAntiAffinityPreset` | Pod anti-affinity preset to spread replicas. Allowed values: soft, hard | `soft` |
| `nodeAffinityPreset.type` | Node affinity preset type. Allowed values: soft, hard | `""` |
| `nodeAffinityPreset.key` | Node label key to match | `""` |
| `nodeAffinityPreset.values` | Node label values to match | `[]` |
| `affinity` | Affinity for pod assignment (overrides the presets) | `{}` |
| `nodeSelector` | Node labels for pod assignment | `{}` |
| `tolerations` | Tolerations for pod assignment | `[]` |
| `topologySpreadConstraints` | Topology spread constraints for pod assignment | `[]` |
| `priorityClassName` | Operator pods priority class name | `""` |
| `podSecurityContext.enabled` | Enable pod Security Context | `true` |
| `podSecurityContext.runAsNonRoot` | Force pods to run as non root | `true` |
| `podSecurityContext.fsGroup` | Group ID for the pod | `1001` |
| `containerSecurityContext.enabled` | Enable container Security Context | `true` |
| `containerSecurityContext.runAsUser` | User ID for the container | `1001` |
| `containerSecurityContext.runAsNonRoot` | Force the container to run as non root | `true` |
| `containerSecurityContext.readOnlyRootFilesystem` | Mount the container root filesystem as read only | `true` |
| `containerSecurityContext.allowPrivilegeEscalation` | Allow privilege escalation | `false` |
| `containerSecurityContext.capabilities.drop` | Linux capabilities to drop | `["ALL"]` |
| `resourcesPreset` | Container resources preset (ignored if resources is set) | `small` |
| `resources` | Explicit container requests and limits | `{}` |
| `livenessProbe` | Liveness probe configuration (health-probe on :8081) | `see values.yaml` |
| `readinessProbe` | Readiness probe configuration | `see values.yaml` |

### RBAC parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `serviceAccount.create` | Create a ServiceAccount for the operator | `true` |
| `serviceAccount.name` | Name of the ServiceAccount (generated when empty) | `""` |
| `serviceAccount.annotations` | Additional annotations for the ServiceAccount | `{}` |
| `serviceAccount.automountServiceAccountToken` | Auto-mount the ServiceAccount token | `true` |
| `rbac.create` | Create the Role/ClusterRole and bindings the operator needs | `true` |

### Metrics parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `metrics.enabled` | Expose the controller-manager metrics endpoint | `true` |
| `metrics.port` | Metrics port | `8080` |
| `metrics.secure` | Serve metrics over HTTPS | `false` |
| `metrics.service.type` | Metrics service type | `ClusterIP` |
| `metrics.serviceMonitor.enabled` | Create a Prometheus Operator ServiceMonitor | `false` |
| `metrics.serviceMonitor.namespace` | Namespace for the ServiceMonitor | `""` |
| `metrics.serviceMonitor.interval` | Scrape interval | `""` |
| `metrics.serviceMonitor.scrapeTimeout` | Scrape timeout | `""` |
| `metrics.serviceMonitor.labels` | Extra labels for the ServiceMonitor | `{}` |

### pprof parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `pprof.enabled` | Enable the pprof debug endpoint (image ≥ v0.8.0) | `false` |
| `pprof.port` | pprof port | `6060` |

### Other parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `pdb.create` | Enable a PodDisruptionBudget so the active controller survives disruptions | `true` |
| `pdb.minAvailable` | Minimum number/percentage of pods available | `""` |
| `pdb.maxUnavailable` | Maximum number/percentage of pods unavailable (defaults to 1) | `""` |
| `networkPolicy.enabled` | Enable NetworkPolicy | `true` |
| `networkPolicy.allowExternal` | When false, only pods with the correct client label can reach the metrics port | `true` |
| `networkPolicy.allowExternalEgress` | Allow unrestricted egress (needed to reach the API server and worker pods) | `true` |
| `networkPolicy.extraIngress` | Extra ingress rules | `[]` |
| `networkPolicy.extraEgress` | Extra egress rules | `[]` |

### CSI dashboard parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `dashboard.enabled` | Deploy the JuiceFS CSI dashboard web UI | `false` |
| `dashboard.image.registry` | Dashboard image registry | `docker.io` |
| `dashboard.image.repository` | Dashboard image repository | `juicedata/csi-dashboard` |
| `dashboard.image.tag` | Dashboard image tag | `v0.26.1` |
| `dashboard.image.pullPolicy` | Dashboard image pull policy | `IfNotPresent` |
| `dashboard.replicaCount` | Number of dashboard replicas | `1` |
| `dashboard.enableManager` | Enable the dashboard's manager features (image tag > 0.26.0) | `false` |
| `dashboard.leaderElection.enabled` | Enable leader election for the dashboard (needed when replicaCount > 1) | `false` |
| `dashboard.auth.enabled` | Require basic auth on the dashboard | `true` |
| `dashboard.auth.username` | Dashboard username | `admin` |
| `dashboard.auth.password` | Dashboard password (auto-generated when empty) | `""` |
| `dashboard.auth.existingSecret` | Existing secret with dashboard credentials | `""` |
| `dashboard.service.type` | Dashboard service type | `ClusterIP` |
| `dashboard.service.port` | Dashboard service port | `8088` |
| `dashboard.resourcesPreset` | Dashboard resources preset | `small` |
| `dashboard.resources` | Explicit dashboard resources (overrides preset) | `{}` |

## Troubleshooting

- **`CacheGroup`/`WarmUp` reconcile fails with `token is missing`** — those are Enterprise features. A Community Edition volume has no EE token and CE `juicefs mount` has no `--cache-group`. Use `Sync`/`CronSync` on CE.
- **Sync worker cannot reach a Ceph-backed CE volume** — inject `ceph.conf` + keyring into the worker via the endpoint's `extraVolumes` (`{secret: {name: <ceph-secret>, mountPath: /etc/ceph}}`).
- **Operator pod CrashLoop / no leader** — check the `lease` object in the release namespace and the operator logs; ensure `automountServiceAccountToken: true` and RBAC was created (`rbac.create: true`).

## License

Apache-2.0.
