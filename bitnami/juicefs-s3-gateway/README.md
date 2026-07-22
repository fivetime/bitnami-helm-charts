<!--- app-name: JuiceFS S3 Gateway -->

# JuiceFS S3 Gateway (Bitnami-style Helm Chart)

JuiceFS S3 Gateway exposes a JuiceFS volume through an S3-compatible API, as a stateless, horizontally scalable replacement for Ceph RGW. This chart deploys the gateway on top of a TiKV metadata engine and Ceph RADOS object storage, with **content deduplication**, **multi-pool cost tiers**, **access-driven tier aging**, and a **bucket-provisioning admin API** for multi-tenant setups.

It is packaged following the [Bitnami common library](https://github.com/bitnami/charts/tree/main/bitnami/common) conventions (common.* helpers, `@section`/`@param` values, per-resource toggles, HA via PDB/anti-affinity).

## TL;DR

```console
# common is declared as a dependency; fetch it first
helm dependency build

helm install my-release . \
  --namespace juicefs --create-namespace \
  --set image.repository=<your-registry>/juicefs \
  --set image.tag=main \
  --set auth.rootUser=admin \
  --set auth.rootPassword=<STRONG_PASSWORD> \
  --set auth.metaUrl="tikv://<pd-host>:2379/<volume>"
```

> The `common` chart is a declared dependency, **not vendored**. Run `helm dependency build` (or `helm dependency update`) before `helm install`/`helm template`, otherwise rendering fails with missing `common.*` templates.

## Introduction

Unlike Ceph RGW, this gateway is a **stateless** process: all consistency is provided by the shared metadata engine (TiKV) and object storage (Ceph RADOS). You can run any number of replicas behind a load balancer. It adds three capabilities on top of plain S3:

- **Deduplication** — chunk objects are content-addressed (SHA-256); identical content is stored once. The dedup index lives in TiKV (`--dedup-tikv`).
- **Cost tiers** — each storage tier maps to a distinct Ceph pool (e.g. nvme / ssd / hdd erasure-coded pools). Buckets are created against a tier.
- **Tier aging** — idle files are demoted to the cold tier on a periodic (changelog-driven) scan; a read promotes them back to their bucket's tier.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8+
- A reachable **TiKV/PD** cluster for metadata (`tikv://<pd>:2379/<volume>`)
- A **Ceph** cluster with pools for each tier and a cephx user; mount its `ceph.conf` + keyring via a Secret (`ceph.existingSecret`)
- The JuiceFS **volume must be formatted** before the gateway serves it — either enable `provisioning.enabled`, or format it out-of-band (see DEPLOY.md)
- A JuiceFS client image built with **ceph + TiKV** support (this fork's image)

## Installing the Chart

```console
helm dependency build
helm install my-release . -n juicefs --create-namespace -f my-values.yaml
```

## Uninstalling the Chart

```console
helm uninstall my-release -n juicefs
```

This removes the Kubernetes objects. It does **not** touch the JuiceFS volume data (metadata in TiKV, objects in Ceph) — that is external to the chart.

## Configuration and installation details

### Credentials

`auth.rootUser` / `auth.rootPassword` become the S3 root access/secret key (`MINIO_ROOT_USER`/`MINIO_ROOT_PASSWORD`). Provide them explicitly for production, or point `auth.existingSecret` at a pre-created Secret (keys `root-user`, `root-password`, `meta-url`). When `auth.rootPassword` is empty and no existing secret is set, a password is auto-generated and preserved across upgrades.

### Metadata engine (TiKV)

Set `auth.metaUrl` to `tikv://<pd-host>:2379/<volume>`. For multiple PD addresses use a values file, not `--set` (commas are list separators in `--set`).

### Ceph backend

Set `ceph.enabled=true` and `ceph.existingSecret` to a Secret containing `ceph.conf` (with `mon_host`) and the cephx keyring; it is mounted read-only at `ceph.mountPath` (default `/etc/ceph`). The chart does **not** create this Secret — create it yourself, so the keyring never lands in values.

### Deduplication and tiers

Deduplication is a property of the **formatted volume** (`--dedup-tikv`), read from the volume settings at startup — the gateway enables it automatically. Tier-to-pool mapping is likewise stored on the volume (`juicefs config --tier N --storage-class <pool>`). Use `provisioning` to do this from Helm, or configure it out-of-band.

### Tier aging

`tierAging.enabled=true` starts the demotion scan and read-triggered promotion. It requires `atimeMode` to be `relatime` (production) or `strictatime` — **not** the default `noatime` (a validation warning is emitted). `tierAging.coldTier` is the demotion target tier. Multiple replicas coordinate via cross-instance locks (work-stealing); global metadata load ≈ `tierAging.scanRate` × replicas.

### Bucket-provisioning admin API

`bucketAdmin.enabled=true` exposes an internal HTTP endpoint (separate ClusterIP service) to create buckets pre-assigned to a tier. It is bearer-token protected (`bucketAdmin.token`). **Never expose it to tenants or the public**, and keep `s3:CreateBucket`/`s3:DeleteBucket` out of tenant IAM policies.

### Volume provisioning (optional)

`provisioning.enabled=true` runs a post-install/upgrade Helm hook Job that formats the volume (if absent), applies tier mappings, and enables changelog — independently of the gateway Deployment lifecycle. Adding a tier later is a `helm upgrade` of this Job, never a restart of the gateways.

### Local cache

`cache.enabled=true` adds `--cache-dir`/`--cache-size` (and `--writeback` for the write-back cache — an ability RGW lacks). Point `cache.dir` at fast local storage (NVMe) provided via `extraVolumes`/`extraVolumeMounts`.

### Ingress

Set `ingress.enabled=true`, `ingress.ingressClassName`, and `ingress.hostname`. For per-object-key cache locality behind an NGINX ingress, set `nginx.ingress.kubernetes.io/upstream-hash-by: "$request_uri"` in `ingress.annotations`.

### High availability

`replicaCount` defaults to 3; `pdb.create=true` and soft pod anti-affinity keep replicas spread and available during rolling upgrades. `autoscaling.enabled` adds an HPA.

### Rolling vs immutable tags

The default `image.tag: main` is a rolling tag that changes as the fork's `main` branch rebuilds. For production, pin an immutable tag (a commit-sha or version tag) so pod restarts never pull an unexpected image.

## Parameters

### Global parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `global.imageRegistry` | Global Docker image registry | `""` |
| `global.imagePullSecrets` | Global Docker registry secret names as an array | `{}` |
| `global.defaultStorageClass` | Global default StorageClass for Persistent Volume(s) | `""` |
| `global.security.allowInsecureImages` | Allows skipping image verification | `False` |
| `global.compatibility.openshift.adaptSecurityContext` | Adapt the securityContext sections of the deployment to make them compatible with Openshift restricted-v2 SCC: remove runAsUser, runAsGroup and fsGroup and let the platform use their allowed default IDs. Possible values: auto (apply if the detected running cluster is Openshift), force (perform the adaptation always), disabled (do not perform adaptation) | `auto` |

### Common parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `nameOverride` | String to partially override common.names.fullname template (will maintain the release name) | `""` |
| `namespaceOverride` | String to fully override common.names.namespace | `""` |
| `fullnameOverride` | String to fully override common.names.fullname template | `""` |
| `commonLabels` | Labels to add to all deployed objects | `{}` |
| `commonAnnotations` | Annotations to add to all deployed objects | `{}` |
| `clusterDomain` | Default Kubernetes cluster domain | `cluster.local` |
| `extraDeploy` | Array of extra objects to deploy with the release | `{}` |
| `kubeVersion` | Force target Kubernetes version (using Helm capabilities if not set) | `""` |

### JuiceFS S3 Gateway image parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `image.registry` |  JuiceFS gateway image registry | `ghcr.io` |
| `image.repository` |  JuiceFS gateway image repository | `fivetime/juicefs` |
| `image.tag` | JuiceFS gateway image tag | `main` |
| `image.digest` | JuiceFS gateway image digest in the way sha256:aa.... Please note this parameter, if set, will override the tag | `""` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `image.pullSecrets` | Specify docker-registry secret names as an array | `{}` |

### Authentication and volume parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `auth.rootUser` | S3 root access key (MINIO_ROOT_USER). Auto-generated when empty and no existingSecret is set | `admin` |
| `auth.rootPassword` | S3 root secret key (MINIO_ROOT_PASSWORD), at least 8 characters. Auto-generated when empty | `""` |
| `auth.metaUrl` | Metadata engine URL, e.g. "tikv://pd-host:2379/myjfs". Required unless auth.existingSecret is set | `""` |
| `auth.existingSecret` | Existing secret holding credentials and meta URL (keys: root-user, root-password, meta-url; overridable below) | `""` |
| `auth.rootUserSecretKey` | Key in auth.existingSecret holding the S3 root access key | `""` |
| `auth.rootPasswordSecretKey` | Key in auth.existingSecret holding the S3 root secret key | `""` |
| `auth.metaUrlSecretKey` | Key in auth.existingSecret holding the metadata engine URL | `""` |

### Gateway deployment parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `replicaCount` | Number of gateway replicas. For production, run at least 3 behind a consistent-hash load balancer | `3` |
| `volumeName` | JuiceFS volume name to serve. Defaults to the volume's own name when empty | `""` |
| `multiBuckets` | Expose top-level directories as separate S3 buckets (multi-tenant layout) | `True` |
| `atimeMode` | When to update atime: noatime, relatime (recommended for tier aging), strictatime | `relatime` |
| `extraArgs` | Additional raw arguments appended to the `juicefs gateway` command | `{}` |
| `command` | Override the container command (advanced; bypasses the generated startup script) | `{}` |
| `containerPorts.api` | S3 API container port | `9000` |
| `containerPorts.metrics` | Prometheus metrics container port | `9567` |
| `containerPorts.admin` | Bucket-provisioning admin API container port | `9568` |
| `extraEnvVars` | Array of extra environment variables for the gateway container | `{}` |
| `extraEnvVarsCM` | Name of a ConfigMap with extra environment variables | `""` |
| `extraEnvVarsSecret` | Name of a Secret with extra environment variables | `""` |
| `command` | Custom command override | `{}` |
| `lifecycleHooks` | lifecycleHooks for the gateway container to automate configuration before or after startup | `{}` |
| `automountServiceAccountToken` | Mount Service Account token in pod | `False` |
| `hostAliases` | Deployment pod host aliases | `{}` |
| `podLabels` | Extra labels for gateway pods | `{}` |
| `podAnnotations` | Annotations for gateway pods | `{}` |
| `podAffinityPreset` | Pod affinity preset. Ignored if `affinity` is set. Allowed values: soft, hard | `""` |
| `podAntiAffinityPreset` | Pod anti-affinity preset. Spreads replicas across nodes for HA. Allowed values: soft, hard | `soft` |
| `nodeAffinityPreset.type` | Node affinity preset type. Ignored if `affinity` is set. Allowed values: soft, hard | `""` |
| `nodeAffinityPreset.key` | Node label key to match. Ignored if `affinity` is set | `""` |
| `nodeAffinityPreset.values` | Node label values to match. Ignored if `affinity` is set | `{}` |
| `affinity` | Affinity for pod assignment. Overrides podAffinityPreset/podAntiAffinityPreset/nodeAffinityPreset | `{}` |
| `nodeSelector` | Node labels for pod assignment (e.g. pin gateways to NVMe cache nodes) | `{}` |
| `tolerations` | Tolerations for pod assignment | `{}` |
| `topologySpreadConstraints` | Topology spread constraints for pod assignment | `{}` |
| `priorityClassName` | Gateway pods priority class name | `""` |
| `schedulerName` | Name of the k8s scheduler (other than default) | `""` |
| `terminationGracePeriodSeconds` | Seconds the pod needs to terminate gracefully | `""` |
| `updateStrategy.type` | Gateway deployment strategy type | `RollingUpdate` |
| `updateStrategy.rollingUpdate` | Gateway deployment rolling update configuration parameters | `{}` |
| `podSecurityContext.enabled` | Enable pod Security Context | `True` |
| `podSecurityContext.fsGroup` | Group ID for the pod | `1001` |
| `containerSecurityContext.enabled` | Enable container Security Context | `True` |
| `containerSecurityContext.runAsUser` | User ID for the container | `1001` |
| `containerSecurityContext.runAsNonRoot` | Force the container to run as a non root user | `True` |
| `containerSecurityContext.readOnlyRootFilesystem` | Mount the container root filesystem as read only | `False` |
| `containerSecurityContext.privileged` | Run the container as privileged | `False` |
| `containerSecurityContext.allowPrivilegeEscalation` | Allow privilege escalation | `False` |
| `containerSecurityContext.capabilities.add` | Linux capabilities to add (SYS_ADMIN required if FUSE mountpoint symlink following is used) | `{}` |
| `containerSecurityContext.capabilities.drop` | Linux capabilities to drop | `['ALL']` |
| `resourcesPreset` | Set container resources according to one common preset (allowed values: none, nano, micro, small, medium, large, xlarge, 2xlarge). Ignored if resources is set | `large` |
| `resources` | Set container requests and limits for different resources like CPU or memory (essential for production workloads) | `{}` |
| `livenessProbe.enabled` | Enable livenessProbe on the gateway container | `True` |
| `livenessProbe.initialDelaySeconds` | Initial delay seconds for livenessProbe | `30` |
| `livenessProbe.periodSeconds` | Period seconds for livenessProbe | `10` |
| `livenessProbe.timeoutSeconds` | Timeout seconds for livenessProbe | `5` |
| `livenessProbe.failureThreshold` | Failure threshold for livenessProbe | `6` |
| `livenessProbe.successThreshold` | Success threshold for livenessProbe | `1` |
| `readinessProbe.enabled` | Enable readinessProbe on the gateway container | `True` |
| `readinessProbe.initialDelaySeconds` | Initial delay seconds for readinessProbe | `5` |
| `readinessProbe.periodSeconds` | Period seconds for readinessProbe | `10` |
| `readinessProbe.timeoutSeconds` | Timeout seconds for readinessProbe | `5` |
| `readinessProbe.failureThreshold` | Failure threshold for readinessProbe | `6` |
| `readinessProbe.successThreshold` | Success threshold for readinessProbe | `1` |
| `startupProbe.enabled` | Enable startupProbe on the gateway container | `False` |
| `startupProbe.initialDelaySeconds` | Initial delay seconds for startupProbe | `10` |
| `startupProbe.periodSeconds` | Period seconds for startupProbe | `10` |
| `startupProbe.timeoutSeconds` | Timeout seconds for startupProbe | `5` |
| `startupProbe.failureThreshold` | Failure threshold for startupProbe | `30` |
| `startupProbe.successThreshold` | Success threshold for startupProbe | `1` |
| `customLivenessProbe` | Custom livenessProbe that overrides the default one | `{}` |
| `customReadinessProbe` | Custom readinessProbe that overrides the default one | `{}` |
| `customStartupProbe` | Custom startupProbe that overrides the default one | `{}` |
| `extraVolumes` | Optionally specify extra list of additional volumes for the gateway pod (e.g. NVMe hostPath cache, ceph config) | `{}` |
| `extraVolumeMounts` | Optionally specify extra list of additional volumeMounts for the gateway container | `{}` |
| `initContainers` | Add additional init containers to the gateway pod | `{}` |
| `sidecars` | Add additional sidecar containers to the gateway pod | `{}` |

### Local cache parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `cache.enabled` | Enable local cache flags (--cache-dir/--cache-size). Provide the actual storage via extraVolumes/extraVolumeMounts | `False` |
| `cache.dir` | Local cache directory (colon-separated for multiple paths). Should map to an NVMe-backed volume mount | `/var/jfsCache` |
| `cache.size` | Read cache size limit in MiB | `102400` |
| `cache.writeback` | Enable write-back cache (stage writes locally, upload asynchronously). No RGW equivalent | `False` |
| `cache.extraArgs` | Extra cache-related raw arguments (e.g. --upload-delay, --free-space-ratio) | `{}` |

### Ceph RADOS parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `ceph.enabled` | Mount a Ceph client config secret at /etc/ceph | `False` |
| `ceph.existingSecret` | Name of an existing secret containing ceph.conf and the cephx keyring | `""` |
| `ceph.mountPath` | Path where the ceph config secret is mounted | `/etc/ceph` |

### Tier aging parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `tierAging.enabled` | Enable tier aging (demotion scan + read-triggered promotion) | `False` |
| `tierAging.demoteAfter` | Demote files not accessed for this duration (e.g. 720h). 0 disables demotion | `720h` |
| `tierAging.scanInterval` | How often the incremental demotion scan runs | `1h` |
| `tierAging.coldTier` | Tier id files are demoted to (must be configured with a storage class) | `3` |
| `tierAging.promote` | Promote a demoted file back to its bucket tier on S3 read access | `True` |
| `tierAging.scanRate` | Per-instance ceiling on scan metadata lookups per second (global load = this x scanning replicas) | `3000` |
| `tierAging.fullScanInterval` | Interval of the full tree-walk audit behind the incremental mode. 0 disables it | `168h` |

### Bucket-provisioning admin API parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `bucketAdmin.enabled` | Expose the bucket-provisioning admin API on containerPorts.admin | `False` |
| `bucketAdmin.token` | Bearer token required to call the admin API. Auto-nothing: required when enabled | `""` |
| `bucketAdmin.existingSecret` | Existing secret holding the admin token (key: admin-token, overridable) | `""` |
| `bucketAdmin.tokenSecretKey` | Key in bucketAdmin.existingSecret holding the token | `admin-token` |
| `bucketAdmin.service.type` | Kubernetes service type for the admin API (keep ClusterIP; do not expose externally) | `ClusterIP` |
| `bucketAdmin.service.port` | Admin API service port | `9568` |

### Volume provisioning parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `provisioning.enabled` | Run the provisioning Job on install/upgrade | `False` |
| `provisioning.format.enabled` | Run `juicefs format` (skipped automatically if the volume already exists) | `True` |
| `provisioning.format.enabled` | Attempt to format the volume when it does not exist yet | `True` |
| `provisioning.format.storage` | Object storage backend (e.g. ceph) | `ceph` |
| `provisioning.format.bucket` | Default tier (tier 0) bucket/pool, e.g. ceph://juicefs-nvme | `""` |
| `provisioning.format.accessKey` | Object storage access key (for ceph: the cephx user name, e.g. ceph) | `""` |
| `provisioning.format.secretKey` | Object storage secret key (for ceph: the cephx client id, e.g. client.juicefs) | `""` |
| `provisioning.format.dedupTiKV` | PD addresses for the deduplication index (immutable once set). Empty disables dedup | `""` |
| `provisioning.format.extraArgs` | Extra raw arguments for `juicefs format` | `{}` |
| `provisioning.tiers` | Tier-to-storage-class mappings applied via `juicefs config --tier`. Safe to re-run and to change over time | `{}` |
| `provisioning.changelog.enabled` | Enable the metadata changelog (required for incremental tier aging) | `False` |
| `provisioning.changelog.maxAge` | Changelog retention window | `2h` |
| `provisioning.extraCommands` | Extra `juicefs` commands (one per array item) run after format/config | `{}` |
| `provisioning.resourcesPreset` | Provisioning job resources preset | `small` |
| `provisioning.resources` | Explicit provisioning job resources (overrides preset) | `{}` |
| `provisioning.podSecurityContext.enabled` | Enable provisioning pod Security Context | `True` |
| `provisioning.podSecurityContext.fsGroup` | Provisioning pod fsGroup | `1001` |
| `provisioning.containerSecurityContext.enabled` | Enable provisioning container Security Context | `True` |
| `provisioning.containerSecurityContext.runAsUser` | Provisioning container user ID | `1001` |
| `provisioning.containerSecurityContext.runAsNonRoot` | Provisioning container run as non root | `True` |
| `provisioning.nodeSelector` | Node selector for the provisioning job | `{}` |
| `provisioning.tolerations` | Tolerations for the provisioning job | `{}` |
| `provisioning.cleanupAfterFinished.enabled` | Clean up the provisioning Job after it finishes | `False` |
| `provisioning.cleanupAfterFinished.seconds` | TTL seconds after the Job finishes | `600` |

### Traffic exposure parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `service.type` | S3 API Kubernetes service type | `ClusterIP` |
| `service.ports.api` | S3 API service port | `9000` |
| `service.ports.metrics` | Metrics service port | `9567` |
| `service.nodePorts.api` | Node port for the S3 API (when type is NodePort/LoadBalancer) | `""` |
| `service.clusterIP` | S3 API service cluster IP | `""` |
| `service.loadBalancerIP` | S3 API service Load Balancer IP | `""` |
| `service.loadBalancerSourceRanges` | S3 API service Load Balancer sources | `{}` |
| `service.externalTrafficPolicy` | S3 API service external traffic policy | `Cluster` |
| `service.annotations` | Additional custom annotations for the S3 API service | `{}` |
| `service.extraPorts` | Extra ports to expose in the S3 API service | `{}` |
| `service.sessionAffinity` | Session Affinity for Kubernetes service, can be "None" or "ClientIP" | `None` |
| `headless.annotations` | Annotations for the headless service | `{}` |
| `ingress.enabled` | Enable ingress record generation for the S3 API | `False` |
| `ingress.pathType` | Ingress path type | `ImplementationSpecific` |
| `ingress.hostname` | Default host for the ingress record | `s3.local` |
| `ingress.ingressClassName` | IngressClass that will be used to implement the Ingress | `""` |
| `ingress.path` | Default path for the ingress record | `/` |
| `ingress.annotations` | Additional annotations for the Ingress resource. For per-object-key consistent-hash routing with the NGINX Ingress Controller, set nginx.ingress.kubernetes.io/upstream-hash-by: "$request_uri" | `{}` |
| `ingress.tls` | Enable TLS configuration for the host defined at ingress.hostname | `False` |
| `ingress.selfSigned` | Create a TLS secret for this ingress record using self-signed certificates generated by Helm | `False` |
| `ingress.extraHosts` | An array with additional hostname(s) to be covered with the ingress record | `{}` |
| `ingress.extraTls` | The tls configuration for additional hostnames to be covered with this ingress record | `{}` |
| `ingress.secrets` | Custom TLS certificates as secrets | `{}` |
| `ingress.extraRules` | Additional rules to be covered with this ingress record | `{}` |

### Other parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `pdb.create` | Enable a Pod Disruption Budget so rolling upgrades keep the gateway available | `True` |
| `pdb.minAvailable` | Minimum number/percentage of pods that must be available | `""` |
| `pdb.maxUnavailable` | Maximum number/percentage of pods that may be unavailable (defaults to 1 when minAvailable is unset) | `""` |
| `autoscaling.enabled` | Enable Horizontal POD autoscaling for the gateway | `False` |
| `autoscaling.minReplicas` | Minimum number of gateway replicas | `3` |
| `autoscaling.maxReplicas` | Maximum number of gateway replicas | `10` |
| `autoscaling.targetCPU` | Target CPU utilization percentage | `70` |
| `autoscaling.targetMemory` | Target Memory utilization percentage | `""` |
| `serviceAccount.create` | Enable creation of a ServiceAccount for the gateway pods | `True` |
| `serviceAccount.name` | Name of the created ServiceAccount. Generated when empty and create is true | `""` |
| `serviceAccount.annotations` | Additional custom annotations for the ServiceAccount | `{}` |
| `serviceAccount.automountServiceAccountToken` | Auto-mount the ServiceAccount token | `False` |
| `networkPolicy.enabled` | Enable creation of NetworkPolicy resources | `True` |
| `networkPolicy.allowExternal` | The Policy model to apply. When false, only pods with the correct client label can reach the S3 port | `True` |
| `networkPolicy.allowExternalEgress` | Allow the pods to access any range of ports and hosts for egress | `True` |
| `networkPolicy.extraIngress` | Add extra ingress rules to the NetworkPolicy | `{}` |
| `networkPolicy.extraEgress` | Add extra egress rules to the NetworkPolicy | `{}` |

### Metrics parameters

| Name | Description | Value |
| ---- | ----------- | ----- |
| `metrics.serviceMonitor.enabled` | Create a Prometheus Operator ServiceMonitor for the gateway metrics endpoint | `False` |
| `metrics.serviceMonitor.namespace` | Namespace for the ServiceMonitor (defaults to the release namespace) | `""` |
| `metrics.serviceMonitor.interval` | Scrape interval | `""` |
| `metrics.serviceMonitor.scrapeTimeout` | Scrape timeout | `""` |
| `metrics.serviceMonitor.labels` | Extra labels for the ServiceMonitor | `{}` |
| `metrics.serviceMonitor.relabelings` | RelabelConfigs to apply to samples before scraping | `{}` |
| `metrics.serviceMonitor.metricRelabelings` | MetricRelabelConfigs to apply to samples before ingestion | `{}` |

## Troubleshooting

- **Pods CrashLoop with `InvalidAccessKeyId` on every S3 request** — fixed in this chart; ensure you are on a build after the secret double-encoding fix (root credentials must not be double base64-encoded).
- **`database is not formatted`** — the volume was never formatted. Enable `provisioning.enabled`, or run `juicefs format ... --dedup-tikv ...` out-of-band before serving.
- **Gateway cannot reach Ceph** — verify the `ceph.existingSecret` contains a valid `ceph.conf` (`mon_host`) and keyring, and that the cephx user has caps on every tier pool.
- **Tier aging never demotes** — check `atimeMode` is not `noatime`, and that the cold tier is configured with a storage class.
- **Hadoop SDK (HDFS) fails to load native lib on Alpine** — the JuiceFS Hadoop SDK's `libjfs` is glibc-based; run it on a glibc image (Debian/Ubuntu) with `librados2`, not Alpine/musl.

## License

Apache-2.0.
