<!--- app-name: HashiCorp Vault -->

# HashiCorp Vault Helm Chart (Enhanced)

基于 Bitnami Vault Helm Chart 的增强版本，使用 `hashicorp/vault` 官方镜像，新增 S3 自动备份/恢复功能。

[HashiCorp Vault 官方文档](https://www.vaultproject.io/)

## 增强功能

相比原版 Bitnami Chart，本 Chart 新增以下功能：

- **S3 自动备份**：通过 CronJob 定时创建 Raft 快照并上传至 S3 兼容存储（AWS S3、Ceph RGW、MinIO 等）
- **自动恢复**：Pod 启动时检测空数据目录，自动从 S3 下载最新快照恢复
- **集群路径隔离**：多集群共用同一 S3 bucket 时，通过 `clusterName` 隔离备份路径
- **hashicorp/vault 镜像兼容**：正确处理 `docker-entrypoint.sh`，避免 seal 配置重复加载和端口冲突

## 架构说明

本 Chart 默认使用 `hashicorp/vault` 官方镜像而非 `bitnami/vault`。启动时通过 `/bin/sh -ec` 覆盖镜像的 entrypoint，直接执行 `vault server -config=...`，避免 `docker-entrypoint.sh` 自动扫描 `/vault/config` 目录导致的以下问题：

- **端口冲突**：entrypoint 内部启动一次 + args 再启动一次 → `address already in use`
- **Seal 重复加载**：同一 seal 配置被加载两次 → `more than one enabled seal found`

Seal 配置（GCP KMS、AWS KMS、Transit 等）不在 Chart 内抽象，直接写在 `server.config`（HCL）或 `existingConfigMap` 中，通过 `extraVolumes`/`extraVolumeMounts` 注入凭证文件。这种方式支持所有 seal 类型，无需修改 Chart。

## TL;DR

```console
helm install vault my-repo/vault -f values.yaml
```

## 前提条件

- Kubernetes 1.23+
- Helm 3.8.0+

## 快速开始

### 1. 基础部署（Raft HA + 外部 ConfigMap）

创建 Vault 配置：

```bash
cat << 'EOF' > config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-config
  namespace: kube-infra
data:
  config.hcl: |
    ui = true
    disable_mlock = true

    listener "tcp" {
      address         = "[::]:8200"
      cluster_address = "[::]:8201"
      tls_disable     = "true"
    }

    storage "raft" {
      path = "/vault/data"
      retry_join {
        leader_api_addr = "http://vault-server-0.vault-server-headless:8200"
      }
      retry_join {
        leader_api_addr = "http://vault-server-1.vault-server-headless:8200"
      }
      retry_join {
        leader_api_addr = "http://vault-server-2.vault-server-headless:8200"
      }
    }

    service_registration "kubernetes" {}
EOF
kubectl apply -f config.yaml
```

创建 values.yaml：

```yaml
server:
  enabled: true
  replicaCount: 3
  existingConfigMap: "vault-config"
  resourcesPreset: small
  persistence:
    enabled: true
    size: 20Gi
```

部署：

```bash
helm install vault my-repo/vault -n kube-infra -f values.yaml
```

初始化：

```bash
kubectl exec -n kube-infra vault-server-0 -- vault operator init -format=json > vault-init.json
```

### 2. Auto-Unseal 配置（以 GCP KMS 为例）

在 config.hcl 中加入 seal 配置：

```hcl
seal "gcpckms" {
  project     = "my-project"
  region      = "asia-northeast1"
  key_ring    = "vault-keyring"
  crypto_key  = "vault-auto-unseal"
  credentials = "/vault/gcp/key.json"
}
```

创建凭证 Secret 并通过 extraVolumes 注入：

```bash
kubectl -n kube-infra create secret generic gcp-kms-credentials \
  --from-file=key.json=./service-account-key.json
```

```yaml
# gcp-kms.yaml
server:
  extraVolumes:
    - name: gcp-credentials
      secret:
        secretName: gcp-kms-credentials
  extraVolumeMounts:
    - name: gcp-credentials
      mountPath: /vault/gcp
      readOnly: true
```

```bash
helm install vault my-repo/vault -n kube-infra \
  -f values.yaml \
  -f gcp-kms.yaml
```

使用 auto-unseal 时，初始化使用 recovery keys：

```bash
kubectl exec -n kube-infra vault-server-0 -- vault operator init \
  -recovery-shares=5 -recovery-threshold=3 -format=json > vault-init.json
```

> **注意**：务必妥善保管 `vault-init.json` 中的 recovery keys 和 root token。

### 3. S3 备份配置

创建 S3 凭证（以 Ceph RGW OBC 为例）：

```yaml
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: vault-backup
  namespace: kube-infra
spec:
  bucketName: vault-backup
  storageClassName: ceph-bucket-openstack
```

OBC 会自动生成同名的 Secret（含 `AWS_ACCESS_KEY_ID` 和 `AWS_SECRET_ACCESS_KEY`）。

创建备份 token：

```bash
ROOT_TOKEN=$(cat vault-init.json | jq -r '.root_token')
kubectl -n kube-infra create secret generic vault-backup-token \
  --from-literal=token="$ROOT_TOKEN"
```

在 values.yaml 中添加备份配置：

```yaml
backup:
  enabled: true
  clusterName: "my-cluster"
  schedule: "0 2 * * *"
  retentionDays: 7
  vaultTokenSecretName: "vault-backup-token"
  rclone:
    provider: "Ceph"
    bucket: "vault-backup"
    endpoint: "http://rook-ceph-rgw-openstack.rook-ceph.svc"
    forcePathStyle: true
    credentialsSecretName: "vault-backup"
```

手动触发备份测试：

```bash
kubectl create job --from=cronjob/vault-backup vault-backup-test -n kube-infra
kubectl logs -f job/vault-backup-test -n kube-infra --all-containers
```

### 4. 灾难恢复（从 S3 恢复）

删除现有数据后，通过 `--set` 临时启用恢复：

```bash
helm uninstall vault -n kube-infra
kubectl delete pvc -n kube-infra -l app.kubernetes.io/instance=vault

helm install vault my-repo/vault -n kube-infra \
  -f values.yaml \
  -f gcp-kms.yaml \
  --set restore.enabled=true --set restore.mode=auto
```

恢复流程：Pod 启动 → init container 检测空数据目录 → 从 S3 下载 `latest.snap` → 恢复 Raft 快照 → Vault 启动 → auto-unseal 自动解封。

> **提示**：恢复成功后，后续升级不带 `--set restore.*` 参数即可，避免重复恢复。

## 备份参数

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `backup.enabled` | 启用 S3 备份 | `false` |
| `backup.clusterName` | 集群标识，用于 S3 路径隔离 | `""` (使用 release name) |
| `backup.schedule` | CronJob 调度表达式 | `"0 2 * * *"` |
| `backup.retentionDays` | 备份保留天数 | `7` |
| `backup.vaultTokenSecretName` | 包含 Vault token 的 Secret 名称 | `""` |
| `backup.vaultTokenSecretKey` | Secret 中 token 的 key | `"token"` |
| `backup.rclone.image.repository` | Rclone 镜像 | `rclone/rclone` |
| `backup.rclone.image.tag` | Rclone 镜像 tag | `"latest"` |
| `backup.rclone.provider` | S3 provider: AWS, Ceph, Minio 等 | `"AWS"` |
| `backup.rclone.region` | S3 region | `"ap-northeast-1"` |
| `backup.rclone.bucket` | S3 bucket 名称 | `""` |
| `backup.rclone.path` | bucket 内路径前缀 | `"vault-snapshots"` |
| `backup.rclone.endpoint` | 自定义 S3 endpoint（MinIO/Ceph 用） | `""` |
| `backup.rclone.forcePathStyle` | 强制 path style（MinIO/Ceph 必须） | `false` |
| `backup.rclone.credentialsSecretName` | 包含 S3 凭证的 Secret 名称 | `""` |
| `backup.snapshot.useMemory` | 使用内存 tmpfs 存放临时快照 | `true` |
| `backup.snapshot.sizeLimit` | 快照最大尺寸 | `"2Gi"` |

## 恢复参数

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `restore.enabled` | 启用自动恢复 | `false` |
| `restore.mode` | 恢复模式 | `"auto"` |

恢复模式说明：

- `auto`：数据目录为空时自动恢复（推荐用于 DR）
- `never`：不自动恢复
- `force`：强制恢复，即使数据已存在（**危险！**）

## S3 路径结构

备份文件存储路径：`s3://<bucket>/<path>/<clusterName>/`

```
vault-backup/
└── vault-snapshots/
    └── my-cluster/
        ├── vault-20260204-020000.snap    # 带时间戳的快照
        ├── vault-20260205-020000.snap
        └── latest.snap                   # 最新快照（恢复用）
```

## 安全说明

- Raft 快照中的数据被 seal key 加密，没有对应的 KMS key 无法解密
- 备份 token 建议使用最小权限策略，生产环境避免使用 root token
- S3 凭证通过 Kubernetes Secret 管理，建议启用 RBAC 限制访问

## 配置与安装详情

### Prometheus 指标

设置 `server.metrics.enabled=true` 可启用 Vault 原生 Prometheus 端点。配合 `server.metrics.serviceMonitor.enabled=true` 可自动创建 ServiceMonitor 对象供 Prometheus Operator 抓取。

### Ingress

设置 `server.ingress.enabled=true` 启用 Ingress。通过 `server.ingress.hostname` 设置域名，`server.ingress.tls` 启用 TLS。

### 自定义配置

两种方式提供 Vault 配置：

1. **内联配置**：通过 `server.config` 直接在 values.yaml 中编写 HCL（支持模板变量）
2. **外部 ConfigMap**：通过 `server.existingConfigMap` 引用预创建的 ConfigMap（推荐，灵活性更高）

使用外部 ConfigMap 时，Chart 不会生成 configmap，你可以完全控制配置内容。

## Bitnami 原始参数

### Global parameters

| Name                                                  | Description                                                                                                                                                                                                                                                                                                                                                         | Value   |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `global.imageRegistry`                                | Global Docker image registry                                                                                                                                                                                                                                                                                                                                        | `""`    |
| `global.imagePullSecrets`                             | Global Docker registry secret names as an array                                                                                                                                                                                                                                                                                                                     | `[]`    |
| `global.defaultStorageClass`                          | Global default StorageClass for Persistent Volume(s)                                                                                                                                                                                                                                                                                                                | `""`    |
| `global.storageClass`                                 | DEPRECATED: use global.defaultStorageClass instead                                                                                                                                                                                                                                                                                                                  | `""`    |
| `global.security.allowInsecureImages`                 | Allows skipping image verification                                                                                                                                                                                                                                                                                                                                  | `false` |
| `global.compatibility.openshift.adaptSecurityContext` | Adapt the securityContext sections of the deployment to make them compatible with Openshift restricted-v2 SCC: remove runAsUser, runAsGroup and fsGroup and let the platform use their allowed default IDs. Possible values: auto (apply if the detected running cluster is Openshift), force (perform the adaptation always), disabled (do not perform adaptation) | `auto`  |

### Common parameters

| Name                     | Description                                                                             | Value           |
| ------------------------ | --------------------------------------------------------------------------------------- | --------------- |
| `kubeVersion`            | Override Kubernetes version                                                             | `""`            |
| `nameOverride`           | String to partially override common.names.name                                          | `""`            |
| `fullnameOverride`       | String to fully override common.names.fullname                                          | `""`            |
| `namespaceOverride`      | String to fully override common.names.namespace                                         | `""`            |
| `commonLabels`           | Labels to add to all deployed objects                                                   | `{}`            |
| `commonAnnotations`      | Annotations to add to all deployed objects                                              | `{}`            |
| `clusterDomain`          | Kubernetes cluster domain name                                                          | `cluster.local` |
| `extraDeploy`            | Array of extra objects to deploy with the release                                       | `[]`            |
| `diagnosticMode.enabled` | Enable diagnostic mode (all probes will be disabled and the command will be overridden) | `false`         |
| `diagnosticMode.command` | Command to override all containers in the deployment                                    | `["sleep"]`     |
| `diagnosticMode.args`    | Args to override all containers in the deployment                                       | `["infinity"]`  |

### Vault Server Parameters

| Name                                                       | Description                                                                                                                                                                                                                     | Value                   |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| `server.enabled`                                           | Enable Vault Server                                                                                                                                                                                                             | `true`                  |
| `server.image.registry`                                    | Vault Server image registry                                                                                                                                                                                                     | `REGISTRY_NAME`         |
| `server.image.repository`                                  | Vault Server image repository                                                                                                                                                                                                   | `REPOSITORY_NAME/vault` |
| `server.image.digest`                                      | Vault Server image digest in the way sha256:aa.... Please note this parameter, if set, will override the tag image tag (immutable tags are recommended)                                                                         | `""`                    |
| `server.image.pullPolicy`                                  | Vault Server image pull policy                                                                                                                                                                                                  | `IfNotPresent`          |
| `server.image.pullSecrets`                                 | Vault Server image pull secrets                                                                                                                                                                                                 | `[]`                    |
| `server.image.debug`                                       | Enable Vault Server image debug mode                                                                                                                                                                                            | `false`                 |
| `server.replicaCount`                                      | Number of Vault Server replicas to deploy                                                                                                                                                                                       | `1`                     |
| `server.podManagementPolicy`                               | Pod management policy                                                                                                                                                                                                           | `Parallel`              |
| `server.containerPorts.http`                               | Vault Server http container port                                                                                                                                                                                                | `8200`                  |
| `server.containerPorts.internal`                           | Vault Server internal (HTTPS) container port                                                                                                                                                                                    | `8201`                  |
| `server.livenessProbe.enabled`                             | Enable livenessProbe on Vault Server containers                                                                                                                                                                                 | `false`                 |
| `server.livenessProbe.initialDelaySeconds`                 | Initial delay seconds for livenessProbe                                                                                                                                                                                         | `5`                     |
| `server.livenessProbe.periodSeconds`                       | Period seconds for livenessProbe                                                                                                                                                                                                | `10`                    |
| `server.livenessProbe.timeoutSeconds`                      | Timeout seconds for livenessProbe                                                                                                                                                                                               | `5`                     |
| `server.livenessProbe.failureThreshold`                    | Failure threshold for livenessProbe                                                                                                                                                                                             | `5`                     |
| `server.livenessProbe.successThreshold`                    | Success threshold for livenessProbe                                                                                                                                                                                             | `1`                     |
| `server.readinessProbe.enabled`                            | Enable readinessProbe on Vault Server containers                                                                                                                                                                                | `true`                  |
| `server.readinessProbe.initialDelaySeconds`                | Initial delay seconds for readinessProbe                                                                                                                                                                                        | `5`                     |
| `server.readinessProbe.periodSeconds`                      | Period seconds for readinessProbe                                                                                                                                                                                               | `10`                    |
| `server.readinessProbe.timeoutSeconds`                     | Timeout seconds for readinessProbe                                                                                                                                                                                              | `5`                     |
| `server.readinessProbe.failureThreshold`                   | Failure threshold for readinessProbe                                                                                                                                                                                            | `5`                     |
| `server.readinessProbe.successThreshold`                   | Success threshold for readinessProbe                                                                                                                                                                                            | `1`                     |
| `server.startupProbe.enabled`                              | Enable startupProbe on Vault Server containers                                                                                                                                                                                  | `false`                 |
| `server.startupProbe.initialDelaySeconds`                  | Initial delay seconds for startupProbe                                                                                                                                                                                          | `5`                     |
| `server.startupProbe.periodSeconds`                        | Period seconds for startupProbe                                                                                                                                                                                                 | `10`                    |
| `server.startupProbe.timeoutSeconds`                       | Timeout seconds for startupProbe                                                                                                                                                                                                | `5`                     |
| `server.startupProbe.failureThreshold`                     | Failure threshold for startupProbe                                                                                                                                                                                              | `5`                     |
| `server.startupProbe.successThreshold`                     | Success threshold for startupProbe                                                                                                                                                                                              | `1`                     |
| `server.customLivenessProbe`                               | Custom livenessProbe that overrides the default one                                                                                                                                                                             | `{}`                    |
| `server.customReadinessProbe`                              | Custom readinessProbe that overrides the default one                                                                                                                                                                            | `{}`                    |
| `server.customStartupProbe`                                | Custom startupProbe that overrides the default one                                                                                                                                                                              | `{}`                    |
| `server.resourcesPreset`                                   | Set container resources according to one common preset (allowed values: none, nano, micro, small, medium, large, xlarge, 2xlarge). This is ignored if server.resources is set (server.resources is recommended for production). | `micro`                 |
| `server.resources`                                         | Set container requests and limits for different resources like CPU or memory (essential for production workloads)                                                                                                               | `{}`                    |
| `server.podSecurityContext.enabled`                        | Enabled Vault Server pods' Security Context                                                                                                                                                                                     | `true`                  |
| `server.podSecurityContext.fsGroupChangePolicy`            | Set filesystem group change policy                                                                                                                                                                                              | `Always`                |
| `server.podSecurityContext.sysctls`                        | Set kernel settings using the sysctl interface                                                                                                                                                                                  | `[]`                    |
| `server.podSecurityContext.supplementalGroups`             | Set filesystem extra groups                                                                                                                                                                                                     | `[]`                    |
| `server.podSecurityContext.fsGroup`                        | Set Vault Server pod's Security Context fsGroup                                                                                                                                                                                 | `1001`                  |
| `server.containerSecurityContext.enabled`                  | Enabled containers' Security Context                                                                                                                                                                                            | `true`                  |
| `server.containerSecurityContext.seLinuxOptions`           | Set SELinux options in container                                                                                                                                                                                                | `{}`                    |
| `server.containerSecurityContext.runAsUser`                | Set containers' Security Context runAsUser                                                                                                                                                                                      | `1001`                  |
| `server.containerSecurityContext.runAsGroup`               | Set containers' Security Context runAsGroup                                                                                                                                                                                     | `1001`                  |
| `server.containerSecurityContext.runAsNonRoot`             | Set container's Security Context runAsNonRoot                                                                                                                                                                                   | `true`                  |
| `server.containerSecurityContext.privileged`               | Set container's Security Context privileged                                                                                                                                                                                     | `false`                 |
| `server.containerSecurityContext.readOnlyRootFilesystem`   | Set container's Security Context readOnlyRootFilesystem                                                                                                                                                                         | `true`                  |
| `server.containerSecurityContext.allowPrivilegeEscalation` | Set container's Security Context allowPrivilegeEscalation                                                                                                                                                                       | `false`                 |
| `server.containerSecurityContext.capabilities.drop`        | List of capabilities to be dropped                                                                                                                                                                                              | `["ALL"]`               |
| `server.containerSecurityContext.seccompProfile.type`      | Set container's Security Context seccomp profile                                                                                                                                                                                | `RuntimeDefault`        |
| `server.command`                                           | Override default container command (useful when using custom images)                                                                                                                                                            | `[]`                    |
| `server.args`                                              | Override default container args (useful when using custom images)                                                                                                                                                               | `[]`                    |
| `server.automountServiceAccountToken`                      | Mount Service Account token in pod                                                                                                                                                                                              | `true`                  |
| `server.hostAliases`                                       | Vault Server pods host aliases                                                                                                                                                                                                  | `[]`                    |
| `server.config`                                            | Vault server configuration (evaluated as a template)                                                                                                                                                                            | `""`                    |
| `server.existingConfigMap`                                 | name of a ConfigMap with existing configuration for the server                                                                                                                                                                  | `""`                    |
| `server.podLabels`                                         | Extra labels for Vault Server pods                                                                                                                                                                                              | `{}`                    |
| `server.podAnnotations`                                    | Annotations for Vault Server pods                                                                                                                                                                                               | `{}`                    |
| `server.podAffinityPreset`                                 | Pod affinity preset. Ignored if `server.affinity` is set. Allowed values: `soft` or `hard`                                                                                                                                      | `""`                    |
| `server.podAntiAffinityPreset`                             | Pod anti-affinity preset. Ignored if `server.affinity` is set. Allowed values: `soft` or `hard`                                                                                                                                 | `soft`                  |
| `server.pdb.create`                                        | Enable/disable a Pod Disruption Budget creation                                                                                                                                                                                 | `true`                  |
| `server.pdb.minAvailable`                                  | Minimum number/percentage of pods that should remain scheduled                                                                                                                                                                  | `""`                    |
| `server.pdb.maxUnavailable`                                | Maximum number/percentage of pods that may be made unavailable. Defaults to `1` if both `server.pdb.minAvailable` and `server.pdb.maxUnavailable` are empty.                                                                    | `""`                    |
| `server.nodeAffinityPreset.type`                           | Node affinity preset type. Ignored if `server.affinity` is set. Allowed values: `soft` or `hard`                                                                                                                                | `""`                    |
| `server.nodeAffinityPreset.key`                            | Node label key to match. Ignored if `server.affinity` is set                                                                                                                                                                    | `""`                    |
| `server.nodeAffinityPreset.values`                         | Node label values to match. Ignored if `server.affinity` is set                                                                                                                                                                 | `[]`                    |
| `server.affinity`                                          | Affinity for Vault Server pods assignment                                                                                                                                                                                       | `{}`                    |
| `server.nodeSelector`                                      | Node labels for Vault Server pods assignment                                                                                                                                                                                    | `{}`                    |
| `server.tolerations`                                       | Tolerations for Vault Server pods assignment                                                                                                                                                                                    | `[]`                    |
| `server.updateStrategy.type`                               | Vault Server statefulset strategy type                                                                                                                                                                                          | `RollingUpdate`         |
| `server.priorityClassName`                                 | Vault Server pods' priorityClassName                                                                                                                                                                                            | `""`                    |
| `server.topologySpreadConstraints`                         | Topology Spread Constraints for pod assignment spread across your cluster among failure-domains. Evaluated as a template                                                                                                        | `[]`                    |
| `server.schedulerName`                                     | Name of the k8s scheduler (other than default) for Vault Server pods                                                                                                                                                            | `""`                    |
| `server.terminationGracePeriodSeconds`                     | Seconds Redmine pod needs to terminate gracefully                                                                                                                                                                               | `""`                    |
| `server.lifecycleHooks`                                    | for the Vault Server container(s) to automate configuration before or after startup                                                                                                                                             | `{}`                    |
| `server.extraEnvVars`                                      | Array with extra environment variables to add to Vault Server nodes                                                                                                                                                             | `[]`                    |
| `server.extraEnvVarsCM`                                    | Name of existing ConfigMap containing extra env vars for Vault Server nodes                                                                                                                                                     | `""`                    |
| `server.extraEnvVarsSecret`                                | Name of existing Secret containing extra env vars for Vault Server nodes                                                                                                                                                        | `""`                    |
| `server.extraVolumes`                                      | Optionally specify extra list of additional volumes for the Vault Server pod(s)                                                                                                                                                 | `[]`                    |
| `server.extraVolumeMounts`                                 | Optionally specify extra list of additional volumeMounts for the Vault Server container(s)                                                                                                                                      | `[]`                    |
| `server.sidecars`                                          | Add additional sidecar containers to the Vault Server pod(s)                                                                                                                                                                    | `[]`                    |
| `server.initContainers`                                    | Add additional init containers to the Vault Server pod(s)                                                                                                                                                                       | `[]`                    |

### Vault Server Traffic Exposure Parameters

| Name                                              | Description                                                                                                                      | Value                    |
| ------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------ |
| `server.service.general.type`                     | Vault Server service type                                                                                                        | `ClusterIP`              |
| `server.service.general.ports.http`               | Vault Server service HTTP port                                                                                                   | `8200`                   |
| `server.service.general.ports.internal`           | Vault Server internal port                                                                                                       | `8201`                   |
| `server.service.general.nodePorts.http`           | Node port for HTTP                                                                                                               | `""`                     |
| `server.service.general.nodePorts.internal`       | Node port for HTTP                                                                                                               | `""`                     |
| `server.service.general.clusterIP`                | Vault Server service Cluster IP                                                                                                  | `""`                     |
| `server.service.general.loadBalancerIP`           | Vault Server service Load Balancer IP                                                                                            | `""`                     |
| `server.service.general.loadBalancerSourceRanges` | Vault Server service Load Balancer sources                                                                                       | `[]`                     |
| `server.service.general.externalTrafficPolicy`    | Vault Server service external traffic policy                                                                                     | `Cluster`                |
| `server.service.general.annotations`              | Additional custom annotations for Vault Server service                                                                           | `{}`                     |
| `server.service.general.extraPorts`               | Extra ports to expose in Vault Server service (normally used with the `sidecars` value)                                          | `[]`                     |
| `server.service.general.sessionAffinity`          | Control where web requests go, to the same pod or round-robin                                                                    | `None`                   |
| `server.service.general.sessionAffinityConfig`    | Additional settings for the sessionAffinity                                                                                      | `{}`                     |
| `server.service.active.type`                      | Vault Server service type                                                                                                        | `ClusterIP`              |
| `server.service.active.ports.http`                | Vault Server service HTTP port                                                                                                   | `8200`                   |
| `server.service.active.ports.internal`            | Vault Server internal port                                                                                                       | `8201`                   |
| `server.service.active.nodePorts.http`            | Node port for HTTP                                                                                                               | `""`                     |
| `server.service.active.nodePorts.internal`        | Node port for HTTP                                                                                                               | `""`                     |
| `server.service.active.clusterIP`                 | Vault Server service Cluster IP                                                                                                  | `""`                     |
| `server.service.active.loadBalancerIP`            | Vault Server service Load Balancer IP                                                                                            | `""`                     |
| `server.service.active.loadBalancerSourceRanges`  | Vault Server service Load Balancer sources                                                                                       | `[]`                     |
| `server.service.active.externalTrafficPolicy`     | Vault Server service external traffic policy                                                                                     | `Cluster`                |
| `server.service.active.annotations`               | Additional custom annotations for Vault Server service                                                                           | `{}`                     |
| `server.service.active.extraPorts`                | Extra ports to expose in Vault Server service (normally used with the `sidecars` value)                                          | `[]`                     |
| `server.service.active.sessionAffinity`           | Control where web requests go, to the same pod or round-robin                                                                    | `None`                   |
| `server.service.active.sessionAffinityConfig`     | Additional settings for the sessionAffinity                                                                                      | `{}`                     |
| `server.networkPolicy.enabled`                    | Specifies whether a NetworkPolicy should be created                                                                              | `true`                   |
| `server.networkPolicy.kubeAPIServerPorts`         | List of possible endpoints to kube-apiserver (limit to your cluster settings to increase security)                               | `[]`                     |
| `server.networkPolicy.allowExternal`              | Don't require server label for connections                                                                                       | `true`                   |
| `server.networkPolicy.allowExternalEgress`        | Allow the pod to access any range of port and all destinations.                                                                  | `true`                   |
| `server.networkPolicy.extraIngress`               | Add extra ingress rules to the NetworkPolicy                                                                                     | `[]`                     |
| `server.networkPolicy.extraEgress`                | Add extra ingress rules to the NetworkPolicy                                                                                     | `[]`                     |
| `server.networkPolicy.ingressNSMatchLabels`       | Labels to match to allow traffic from other namespaces                                                                           | `{}`                     |
| `server.networkPolicy.ingressNSPodMatchLabels`    | Pod labels to match to allow traffic from other namespaces                                                                       | `{}`                     |
| `server.ingress.enabled`                          | Enable ingress record generation for Vault                                                                                       | `false`                  |
| `server.ingress.pathType`                         | Ingress path type                                                                                                                | `ImplementationSpecific` |
| `server.ingress.apiVersion`                       | Force Ingress API version (automatically detected if not set)                                                                    | `""`                     |
| `server.ingress.hostname`                         | Default host for the ingress record                                                                                              | `vault.local`            |
| `server.ingress.ingressClassName`                 | IngressClass that will be be used to implement the Ingress (Kubernetes 1.18+)                                                    | `""`                     |
| `server.ingress.path`                             | Default path for the ingress record                                                                                              | `/`                      |
| `server.ingress.annotations`                      | Additional annotations for the Ingress resource. To enable certificate autogeneration, place here your cert-manager annotations. | `{}`                     |
| `server.ingress.tls`                              | Enable TLS configuration for the host defined at `server.ingress.hostname` parameter                                             | `false`                  |
| `server.ingress.selfSigned`                       | Create a TLS secret for this ingress record using self-signed certificates generated by Helm                                     | `false`                  |
| `server.ingress.extraHosts`                       | An array with additional hostname(s) to be covered with the ingress record                                                       | `[]`                     |
| `server.ingress.extraPaths`                       | An array with additional arbitrary paths that may need to be added to the ingress under the main host                            | `[]`                     |
| `server.ingress.extraTls`                         | TLS configuration for additional hostname(s) to be covered with this ingress record                                              | `[]`                     |
| `server.ingress.secrets`                          | Custom TLS certificates as secrets                                                                                               | `[]`                     |
| `server.ingress.extraRules`                       | Additional rules to be covered with this ingress record                                                                          | `[]`                     |

### Vault Server RBAC Parameters

| Name                                                 | Description                                                      | Value   |
| ---------------------------------------------------- | ---------------------------------------------------------------- | ------- |
| `server.rbac.create`                                 | Specifies whether RBAC resources should be created               | `true`  |
| `server.rbac.createClusterRoleBinding`               | Specifies whether a ClusterRoleBinding should be created         | `true`  |
| `server.rbac.leaderElection.rules`                   | Specifies the leader election role rules                         | `[]`    |
| `server.rbac.discovery.rules`                        | Specifies the discovery role rules                               | `[]`    |
| `server.serviceAccount.create`                       | Specifies whether a ServiceAccount should be created             | `true`  |
| `server.serviceAccount.name`                         | The name of the ServiceAccount to use.                           | `""`    |
| `server.serviceAccount.annotations`                  | Additional Service Account annotations (evaluated as a template) | `{}`    |
| `server.serviceAccount.automountServiceAccountToken` | Automount service account token for the server service account   | `false` |

### Source Controller Persistence Parameters

| Name                                           | Description                                                                                                  | Value                 |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------ | --------------------- |
| `server.persistence.enabled`                   | Enable persistence using Persistent Volume Claims                                                            | `true`                |
| `server.persistence.mountPath`                 | Persistent Volume mount root path                                                                            | `/bitnami/vault/data` |
| `server.persistence.storageClass`              | Persistent Volume storage class                                                                              | `""`                  |
| `server.persistence.accessModes`               | Persistent Volume access modes                                                                               | `[]`                  |
| `server.persistence.size`                      | Persistent Volume size                                                                                       | `10Gi`                |
| `server.persistence.dataSource`                | Custom PVC data source                                                                                       | `{}`                  |
| `server.persistence.annotations`               | Annotations for the PVC                                                                                      | `{}`                  |
| `server.persistence.selector`                  | Selector to match an existing Persistent Volume (this value is evaluated as a template)                      | `{}`                  |
| `server.persistence.existingClaim`             | The name of an existing PVC to use for persistence                                                           | `""`                  |
| `server.persistence.extraVolumeClaimTemplates` | Add additional VolumeClaimTemplates for enabling any plugins or any other purpose to the Vault Server pod(s) | `[]`                  |

### Vault Server Metrics Parameters

| Name                                              | Description                                                                                            | Value   |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | ------- |
| `server.metrics.enabled`                          | Enable the export of Prometheus metrics                                                                | `false` |
| `server.metrics.annotations`                      | Annotations for the server service in order to scrape metrics                                          | `{}`    |
| `server.metrics.serviceMonitor.enabled`           | if `true`, creates a Prometheus Operator ServiceMonitor (also requires `metrics.enabled` to be `true`) | `false` |
| `server.metrics.serviceMonitor.namespace`         | Namespace in which Prometheus is running                                                               | `""`    |
| `server.metrics.serviceMonitor.annotations`       | Additional custom annotations for the ServiceMonitor                                                   | `{}`    |
| `server.metrics.serviceMonitor.labels`            | Extra labels for the ServiceMonitor                                                                    | `{}`    |
| `server.metrics.serviceMonitor.jobLabel`          | The name of the label on the target service to use as the job name in Prometheus                       | `""`    |
| `server.metrics.serviceMonitor.honorLabels`       | honorLabels chooses the metric's labels on collisions with target labels                               | `false` |
| `server.metrics.serviceMonitor.interval`          | Interval at which metrics should be scraped.                                                           | `""`    |
| `server.metrics.serviceMonitor.scrapeTimeout`     | Timeout after which the scrape is ended                                                                | `""`    |
| `server.metrics.serviceMonitor.metricRelabelings` | Specify additional relabeling of metrics                                                               | `[]`    |
| `server.metrics.serviceMonitor.relabelings`       | Specify general relabeling                                                                             | `[]`    |
| `server.metrics.serviceMonitor.selector`          | Prometheus instance selector labels                                                                    | `{}`    |

### Vault CSI Provider Parameters

| Name                                                                     | Description                                                                                                                                                                                                                                                 | Value                                         |
| ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| `csiProvider.enabled`                                                    | Enable Vault CSI Provider                                                                                                                                                                                                                                   | `false`                                       |
| `csiProvider.image.registry`                                             | Vault CSI Provider image registry                                                                                                                                                                                                                           | `REGISTRY_NAME`                               |
| `csiProvider.image.repository`                                           | Vault CSI Provider image repository                                                                                                                                                                                                                         | `REPOSITORY_NAME/vault-csi-provider`          |
| `csiProvider.image.digest`                                               | Vault CSI Provider image digest in the way sha256:aa.... Please note this parameter, if set, will override the tag image tag (immutable tags are recommended)                                                                                               | `""`                                          |
| `csiProvider.image.pullPolicy`                                           | Vault CSI Provider image pull policy                                                                                                                                                                                                                        | `IfNotPresent`                                |
| `csiProvider.image.pullSecrets`                                          | Vault CSI Provider image pull secrets                                                                                                                                                                                                                       | `[]`                                          |
| `csiProvider.image.debug`                                                | Enable Vault CSI Provider image debug mode                                                                                                                                                                                                                  | `false`                                       |
| `csiProvider.config`                                                     | Vault CSI Provider configuration (evaluated as a template)                                                                                                                                                                                                  | `""`                                          |
| `csiProvider.existingConfigMap`                                          | name of a ConfigMap with existing configuration for the CSI Provider                                                                                                                                                                                        | `""`                                          |
| `csiProvider.secretStoreHostPath`                                        | Path to the host CSI Provider folder                                                                                                                                                                                                                        | `/etc/kubernetes/secrets-store-csi-providers` |
| `csiProvider.automountServiceAccountToken`                               | Mount Service Account token in pod                                                                                                                                                                                                                          | `true`                                        |
| `csiProvider.hostAliases`                                                | Vault CSI Provider pods host aliases                                                                                                                                                                                                                        | `[]`                                          |
| `csiProvider.podLabels`                                                  | Extra labels for Vault CSI Provider pods                                                                                                                                                                                                                    | `{}`                                          |
| `csiProvider.podAnnotations`                                             | Annotations for Vault CSI Provider pods                                                                                                                                                                                                                     | `{}`                                          |
| `csiProvider.podAffinityPreset`                                          | Pod affinity preset. Ignored if `csiProvider.affinity` is set. Allowed values: `soft` or `hard`                                                                                                                                                             | `""`                                          |
| `csiProvider.podAntiAffinityPreset`                                      | Pod anti-affinity preset. Ignored if `csiProvider.affinity` is set. Allowed values: `soft` or `hard`                                                                                                                                                        | `soft`                                        |
| `csiProvider.nodeAffinityPreset.type`                                    | Node affinity preset type. Ignored if `csiProvider.affinity` is set. Allowed values: `soft` or `hard`                                                                                                                                                       | `""`                                          |
| `csiProvider.nodeAffinityPreset.key`                                     | Node label key to match. Ignored if `csiProvider.affinity` is set                                                                                                                                                                                           | `""`                                          |
| `csiProvider.nodeAffinityPreset.values`                                  | Node label values to match. Ignored if `csiProvider.affinity` is set                                                                                                                                                                                        | `[]`                                          |
| `csiProvider.affinity`                                                   | Affinity for Vault CSI Provider pods assignment                                                                                                                                                                                                             | `{}`                                          |
| `csiProvider.nodeSelector`                                               | Node labels for Vault CSI Provider pods assignment                                                                                                                                                                                                          | `{}`                                          |
| `csiProvider.tolerations`                                                | Tolerations for Vault CSI Provider pods assignment                                                                                                                                                                                                          | `[]`                                          |
| `csiProvider.updateStrategy.type`                                        | Vault CSI Provider statefulset strategy type                                                                                                                                                                                                                | `RollingUpdate`                               |
| `csiProvider.priorityClassName`                                          | Vault CSI Provider pods' priorityClassName                                                                                                                                                                                                                  | `""`                                          |
| `csiProvider.topologySpreadConstraints`                                  | Topology Spread Constraints for pod assignment spread across your cluster among failure-domains. Evaluated as a template                                                                                                                                    | `[]`                                          |
| `csiProvider.schedulerName`                                              | Name of the k8s scheduler (other than default) for Vault CSI Provider pods                                                                                                                                                                                  | `""`                                          |
| `csiProvider.terminationGracePeriodSeconds`                              | Seconds Redmine pod needs to terminate gracefully                                                                                                                                                                                                           | `""`                                          |
| `csiProvider.extraVolumes`                                               | Optionally specify extra list of additional volumes for the Vault CSI Provider pod(s)                                                                                                                                                                       | `[]`                                          |
| `csiProvider.sidecars`                                                   | Add additional sidecar containers to the Vault CSI Provider pod(s)                                                                                                                                                                                          | `[]`                                          |
| `csiProvider.initContainers`                                             | Add additional init containers to the Vault CSI Provider pod(s)                                                                                                                                                                                             | `[]`                                          |
| `csiProvider.podSecurityContext.enabled`                                 | Enabled CSI Provider pods' Security Context                                                                                                                                                                                                                 | `true`                                        |
| `csiProvider.podSecurityContext.fsGroupChangePolicy`                     | Set filesystem group change policy                                                                                                                                                                                                                          | `Always`                                      |
| `csiProvider.podSecurityContext.sysctls`                                 | Set kernel settings using the sysctl interface                                                                                                                                                                                                              | `[]`                                          |
| `csiProvider.podSecurityContext.supplementalGroups`                      | Set filesystem extra groups                                                                                                                                                                                                                                 | `[]`                                          |
| `csiProvider.podSecurityContext.fsGroup`                                 | Set CSI Provider pod's Security Context fsGroup                                                                                                                                                                                                             | `1001`                                        |
| `csiProvider.networkPolicy.enabled`                                      | Specifies whether a NetworkPolicy should be created                                                                                                                                                                                                         | `true`                                        |
| `csiProvider.networkPolicy.kubeAPIServerPorts`                           | List of possible endpoints to kube-apiserver (limit to your cluster settings to increase security)                                                                                                                                                          | `[]`                                          |
| `csiProvider.networkPolicy.allowExternalEgress`                          | Allow the pod to access any range of port and all destinations.                                                                                                                                                                                             | `true`                                        |
| `csiProvider.networkPolicy.extraIngress`                                 | Add extra ingress rules to the NetworkPolicy                                                                                                                                                                                                                | `[]`                                          |
| `csiProvider.networkPolicy.extraEgress`                                  | Add extra ingress rules to the NetworkPolicy                                                                                                                                                                                                                | `[]`                                          |
| `csiProvider.provider.containerPorts.health`                             | CSI Provider health container port                                                                                                                                                                                                                          | `8080`                                        |
| `csiProvider.provider.livenessProbe.enabled`                             | Enable livenessProbe on CSI Provider container                                                                                                                                                                                                              | `true`                                        |
| `csiProvider.provider.livenessProbe.initialDelaySeconds`                 | Initial delay seconds for livenessProbe                                                                                                                                                                                                                     | `5`                                           |
| `csiProvider.provider.livenessProbe.periodSeconds`                       | Period seconds for livenessProbe                                                                                                                                                                                                                            | `10`                                          |
| `csiProvider.provider.livenessProbe.timeoutSeconds`                      | Timeout seconds for livenessProbe                                                                                                                                                                                                                           | `5`                                           |
| `csiProvider.provider.livenessProbe.failureThreshold`                    | Failure threshold for livenessProbe                                                                                                                                                                                                                         | `5`                                           |
| `csiProvider.provider.livenessProbe.successThreshold`                    | Success threshold for livenessProbe                                                                                                                                                                                                                         | `1`                                           |
| `csiProvider.provider.readinessProbe.enabled`                            | Enable readinessProbe on CSI Provider container                                                                                                                                                                                                             | `true`                                        |
| `csiProvider.provider.readinessProbe.initialDelaySeconds`                | Initial delay seconds for readinessProbe                                                                                                                                                                                                                    | `5`                                           |
| `csiProvider.provider.readinessProbe.periodSeconds`                      | Period seconds for readinessProbe                                                                                                                                                                                                                           | `10`                                          |
| `csiProvider.provider.readinessProbe.timeoutSeconds`                     | Timeout seconds for readinessProbe                                                                                                                                                                                                                          | `5`                                           |
| `csiProvider.provider.readinessProbe.failureThreshold`                   | Failure threshold for readinessProbe                                                                                                                                                                                                                        | `5`                                           |
| `csiProvider.provider.readinessProbe.successThreshold`                   | Success threshold for readinessProbe                                                                                                                                                                                                                        | `1`                                           |
| `csiProvider.provider.startupProbe.enabled`                              | Enable startupProbe on CSI Provider container                                                                                                                                                                                                               | `false`                                       |
| `csiProvider.provider.startupProbe.initialDelaySeconds`                  | Initial delay seconds for startupProbe                                                                                                                                                                                                                      | `5`                                           |
| `csiProvider.provider.startupProbe.periodSeconds`                        | Period seconds for startupProbe                                                                                                                                                                                                                             | `10`                                          |
| `csiProvider.provider.startupProbe.timeoutSeconds`                       | Timeout seconds for startupProbe                                                                                                                                                                                                                            | `5`                                           |
| `csiProvider.provider.startupProbe.failureThreshold`                     | Failure threshold for startupProbe                                                                                                                                                                                                                          | `5`                                           |
| `csiProvider.provider.startupProbe.successThreshold`                     | Success threshold for startupProbe                                                                                                                                                                                                                          | `1`                                           |
| `csiProvider.provider.customLivenessProbe`                               | Custom livenessProbe that overrides the default one                                                                                                                                                                                                         | `{}`                                          |
| `csiProvider.provider.customReadinessProbe`                              | Custom readinessProbe that overrides the default one                                                                                                                                                                                                        | `{}`                                          |
| `csiProvider.provider.customStartupProbe`                                | Custom startupProbe that overrides the default one                                                                                                                                                                                                          | `{}`                                          |
| `csiProvider.provider.resourcesPreset`                                   | Set container resources according to one common preset (allowed values: none, nano, micro, small, medium, large, xlarge, 2xlarge). This is ignored if csiProvider.provider.resources is set (csiProvider.provider.resources is recommended for production). | `nano`                                        |
| `csiProvider.provider.resources`                                         | Set container requests and limits for different resources like CPU or memory (essential for production workloads)                                                                                                                                           | `{}`                                          |
| `csiProvider.provider.containerSecurityContext.enabled`                  | Enabled containers' Security Context                                                                                                                                                                                                                        | `true`                                        |
| `csiProvider.provider.containerSecurityContext.seLinuxOptions`           | Set SELinux options in container                                                                                                                                                                                                                            | `{}`                                          |
| `csiProvider.provider.containerSecurityContext.runAsUser`                | Set containers' Security Context runAsUser                                                                                                                                                                                                                  | `1001`                                        |
| `csiProvider.provider.containerSecurityContext.runAsGroup`               | Set containers' Security Context runAsGroup                                                                                                                                                                                                                 | `1001`                                        |
| `csiProvider.provider.containerSecurityContext.runAsNonRoot`             | Set container's Security Context runAsNonRoot                                                                                                                                                                                                               | `true`                                        |
| `csiProvider.provider.containerSecurityContext.privileged`               | Set container's Security Context privileged                                                                                                                                                                                                                 | `false`                                       |
| `csiProvider.provider.containerSecurityContext.readOnlyRootFilesystem`   | Set container's Security Context readOnlyRootFilesystem                                                                                                                                                                                                     | `true`                                        |
| `csiProvider.provider.containerSecurityContext.allowPrivilegeEscalation` | Set container's Security Context allowPrivilegeEscalation                                                                                                                                                                                                   | `false`                                       |
| `csiProvider.provider.containerSecurityContext.capabilities.drop`        | List of capabilities to be dropped                                                                                                                                                                                                                          | `["ALL"]`                                     |
| `csiProvider.provider.containerSecurityContext.seccompProfile.type`      | Set container's Security Context seccomp profile                                                                                                                                                                                                            | `RuntimeDefault`                              |
| `csiProvider.provider.command`                                           | Override default container command (useful when using custom images)                                                                                                                                                                                        | `[]`                                          |
| `csiProvider.provider.args`                                              | Override default container args (useful when using custom images)                                                                                                                                                                                           | `[]`                                          |
| `csiProvider.provider.lifecycleHooks`                                    | for the CSI Provider container(s) to automate configuration before or after startup                                                                                                                                                                         | `{}`                                          |
| `csiProvider.provider.extraEnvVars`                                      | Array with extra environment variables to add to CSI Provider nodes                                                                                                                                                                                         | `[]`                                          |
| `csiProvider.provider.extraEnvVarsCM`                                    | Name of existing ConfigMap containing extra env vars for CSI Provider nodes                                                                                                                                                                                 | `""`                                          |
| `csiProvider.provider.extraEnvVarsSecret`                                | Name of existing Secret containing extra env vars for CSI Provider nodes                                                                                                                                                                                    | `""`                                          |
| `csiProvider.provider.extraVolumeMounts`                                 | Optionally specify extra list of additional volumeMounts for the Vault CSI Provider container                                                                                                                                                               | `[]`                                          |
| `csiProvider.agent.containerPorts.tcp`                                   | CSI Provider Agent metrics container port                                                                                                                                                                                                                   | `8200`                                        |
| `csiProvider.agent.livenessProbe.enabled`                                | Enable livenessProbe on CSI Provider Agent container                                                                                                                                                                                                        | `true`                                        |
| `csiProvider.agent.livenessProbe.initialDelaySeconds`                    | Initial delay seconds for livenessProbe                                                                                                                                                                                                                     | `5`                                           |
| `csiProvider.agent.livenessProbe.periodSeconds`                          | Period seconds for livenessProbe                                                                                                                                                                                                                            | `10`                                          |
| `csiProvider.agent.livenessProbe.timeoutSeconds`                         | Timeout seconds for livenessProbe                                                                                                                                                                                                                           | `5`                                           |
| `csiProvider.agent.livenessProbe.failureThreshold`                       | Failure threshold for livenessProbe                                                                                                                                                                                                                         | `5`                                           |
| `csiProvider.agent.livenessProbe.successThreshold`                       | Success threshold for livenessProbe                                                                                                                                                                                                                         | `1`                                           |
| `csiProvider.agent.readinessProbe.enabled`                               | Enable readinessProbe on CSI Provider Agent container                                                                                                                                                                                                       | `true`                                        |
| `csiProvider.agent.readinessProbe.initialDelaySeconds`                   | Initial delay seconds for readinessProbe                                                                                                                                                                                                                    | `5`                                           |
| `csiProvider.agent.readinessProbe.periodSeconds`                         | Period seconds for readinessProbe                                                                                                                                                                                                                           | `10`                                          |
| `csiProvider.agent.readinessProbe.timeoutSeconds`                        | Timeout seconds for readinessProbe                                                                                                                                                                                                                          | `5`                                           |
| `csiProvider.agent.readinessProbe.failureThreshold`                      | Failure threshold for readinessProbe                                                                                                                                                                                                                        | `5`                                           |
| `csiProvider.agent.readinessProbe.successThreshold`                      | Success threshold for readinessProbe                                                                                                                                                                                                                        | `1`                                           |
| `csiProvider.agent.startupProbe.enabled`                                 | Enable startupProbe on CSI Provider Agent container                                                                                                                                                                                                         | `false`                                       |
| `csiProvider.agent.startupProbe.initialDelaySeconds`                     | Initial delay seconds for startupProbe                                                                                                                                                                                                                      | `5`                                           |
| `csiProvider.agent.startupProbe.periodSeconds`                           | Period seconds for startupProbe                                                                                                                                                                                                                             | `10`                                          |
| `csiProvider.agent.startupProbe.timeoutSeconds`                          | Timeout seconds for startupProbe                                                                                                                                                                                                                            | `5`                                           |
| `csiProvider.agent.startupProbe.failureThreshold`                        | Failure threshold for startupProbe                                                                                                                                                                                                                          | `5`                                           |
| `csiProvider.agent.startupProbe.successThreshold`                        | Success threshold for startupProbe                                                                                                                                                                                                                          | `1`                                           |
| `csiProvider.agent.customLivenessProbe`                                  | Custom livenessProbe that overrides the default one                                                                                                                                                                                                         | `{}`                                          |
| `csiProvider.agent.customReadinessProbe`                                 | Custom readinessProbe that overrides the default one                                                                                                                                                                                                        | `{}`                                          |
| `csiProvider.agent.customStartupProbe`                                   | Custom startupProbe that overrides the default one                                                                                                                                                                                                          | `{}`                                          |
| `csiProvider.agent.containerSecurityContext.enabled`                     | Enabled containers' Security Context                                                                                                                                                                                                                        | `true`                                        |
| `csiProvider.agent.containerSecurityContext.seLinuxOptions`              | Set SELinux options in container                                                                                                                                                                                                                            | `{}`                                          |
| `csiProvider.agent.containerSecurityContext.runAsUser`                   | Set containers' Security Context runAsUser                                                                                                                                                                                                                  | `1001`                                        |
| `csiProvider.agent.containerSecurityContext.runAsGroup`                  | Set containers' Security Context runAsGroup                                                                                                                                                                                                                 | `1001`                                        |
| `csiProvider.agent.containerSecurityContext.runAsNonRoot`                | Set container's Security Context runAsNonRoot                                                                                                                                                                                                               | `true`                                        |
| `csiProvider.agent.containerSecurityContext.privileged`                  | Set container's Security Context privileged                                                                                                                                                                                                                 | `false`                                       |
| `csiProvider.agent.containerSecurityContext.readOnlyRootFilesystem`      | Set container's Security Context readOnlyRootFilesystem                                                                                                                                                                                                     | `true`                                        |
| `csiProvider.agent.containerSecurityContext.allowPrivilegeEscalation`    | Set container's Security Context allowPrivilegeEscalation                                                                                                                                                                                                   | `false`                                       |
| `csiProvider.agent.containerSecurityContext.capabilities.drop`           | List of capabilities to be dropped                                                                                                                                                                                                                          | `["ALL"]`                                     |
| `csiProvider.agent.containerSecurityContext.seccompProfile.type`         | Set container's Security Context seccomp profile                                                                                                                                                                                                            | `RuntimeDefault`                              |
| `csiProvider.agent.resourcesPreset`                                      | Set container resources according to one common preset (allowed values: none, nano, micro, small, medium, large, xlarge, 2xlarge). This is ignored if csiProvider.agent.resources is set (csiProvider.agent.resources is recommended for production).       | `nano`                                        |
| `csiProvider.agent.resources`                                            | Set container requests and limits for different resources like CPU or memory (essential for production workloads)                                                                                                                                           | `{}`                                          |
| `csiProvider.agent.command`                                              | Override default container command (useful when using custom images)                                                                                                                                                                                        | `[]`                                          |
| `csiProvider.agent.args`                                                 | Override default container args (useful when using custom images)                                                                                                                                                                                           | `[]`                                          |
| `csiProvider.agent.lifecycleHooks`                                       | for the CSI Provider Agent container(s) to automate configuration before or after startup                                                                                                                                                                   | `{}`                                          |
| `csiProvider.agent.extraEnvVars`                                         | Array with extra environment variables to add to CSI Provider Agent nodes                                                                                                                                                                                   | `[]`                                          |
| `csiProvider.agent.extraEnvVarsCM`                                       | Name of existing ConfigMap containing extra env vars for CSI Provider Agent nodes                                                                                                                                                                           | `""`                                          |
| `csiProvider.agent.extraEnvVarsSecret`                                   | Name of existing Secret containing extra env vars for CSI Provider Agent nodes                                                                                                                                                                              | `""`                                          |
| `csiProvider.agent.extraVolumeMounts`                                    | Optionally specify extra list of additional volumeMounts for the CSI Provider container(s)                                                                                                                                                                  | `[]`                                          |

### Vault CSI Provider RBAC Parameters

| Name                                                      | Description                                                      | Value   |
| --------------------------------------------------------- | ---------------------------------------------------------------- | ------- |
| `csiProvider.rbac.create`                                 | Specifies whether RBAC resources should be created               | `true`  |
| `csiProvider.rbac.rules`                                  | Custom RBAC rules to set                                         | `[]`    |
| `csiProvider.serviceAccount.create`                       | Specifies whether a ServiceAccount should be created             | `true`  |
| `csiProvider.serviceAccount.name`                         | The name of the ServiceAccount to use.                           | `""`    |
| `csiProvider.serviceAccount.annotations`                  | Additional Service Account annotations (evaluated as a template) | `{}`    |
| `csiProvider.serviceAccount.automountServiceAccountToken` | Automount service account token for the server service account   | `false` |

### Vault Kubernetes Injector Parameters

| Name                                                         | Description                                                                                                                                                                                                                         | Value                       |
| ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| `injector.enabled`                                           | Enable Vault Kubernetes Injector                                                                                                                                                                                                    | `true`                      |
| `injector.image.registry`                                    | Vault Kubernetes Injector image registry                                                                                                                                                                                            | `REGISTRY_NAME`             |
| `injector.image.repository`                                  | Vault Kubernetes Injector image repository                                                                                                                                                                                          | `REPOSITORY_NAME/vault-k8s` |
| `injector.image.digest`                                      | Vault Kubernetes Injector image digest in the way sha256:aa.... Please note this parameter, if set, will override the tag image tag (immutable tags are recommended)                                                                | `""`                        |
| `injector.image.pullPolicy`                                  | Vault Kubernetes Injector image pull policy                                                                                                                                                                                         | `IfNotPresent`              |
| `injector.image.pullSecrets`                                 | Vault Kubernetes Injector image pull secrets                                                                                                                                                                                        | `[]`                        |
| `injector.image.debug`                                       | Enable Vault Kubernetes Injector image debug mode                                                                                                                                                                                   | `false`                     |
| `injector.replicaCount`                                      | Number of Vault Kubernetes Injector replicas to deploy                                                                                                                                                                              | `1`                         |
| `injector.containerPorts.https`                              | Vault Kubernetes Injector metrics container port                                                                                                                                                                                    | `8080`                      |
| `injector.livenessProbe.enabled`                             | Enable livenessProbe on Vault Kubernetes Injector containers                                                                                                                                                                        | `true`                      |
| `injector.livenessProbe.initialDelaySeconds`                 | Initial delay seconds for livenessProbe                                                                                                                                                                                             | `5`                         |
| `injector.livenessProbe.periodSeconds`                       | Period seconds for livenessProbe                                                                                                                                                                                                    | `10`                        |
| `injector.livenessProbe.timeoutSeconds`                      | Timeout seconds for livenessProbe                                                                                                                                                                                                   | `5`                         |
| `injector.livenessProbe.failureThreshold`                    | Failure threshold for livenessProbe                                                                                                                                                                                                 | `5`                         |
| `injector.livenessProbe.successThreshold`                    | Success threshold for livenessProbe                                                                                                                                                                                                 | `1`                         |
| `injector.readinessProbe.enabled`                            | Enable readinessProbe on Vault Kubernetes Injector containers                                                                                                                                                                       | `true`                      |
| `injector.readinessProbe.initialDelaySeconds`                | Initial delay seconds for readinessProbe                                                                                                                                                                                            | `5`                         |
| `injector.readinessProbe.periodSeconds`                      | Period seconds for readinessProbe                                                                                                                                                                                                   | `10`                        |
| `injector.readinessProbe.timeoutSeconds`                     | Timeout seconds for readinessProbe                                                                                                                                                                                                  | `5`                         |
| `injector.readinessProbe.failureThreshold`                   | Failure threshold for readinessProbe                                                                                                                                                                                                | `5`                         |
| `injector.readinessProbe.successThreshold`                   | Success threshold for readinessProbe                                                                                                                                                                                                | `1`                         |
| `injector.startupProbe.enabled`                              | Enable startupProbe on Vault Kubernetes Injector containers                                                                                                                                                                         | `false`                     |
| `injector.startupProbe.initialDelaySeconds`                  | Initial delay seconds for startupProbe                                                                                                                                                                                              | `5`                         |
| `injector.startupProbe.periodSeconds`                        | Period seconds for startupProbe                                                                                                                                                                                                     | `10`                        |
| `injector.startupProbe.timeoutSeconds`                       | Timeout seconds for startupProbe                                                                                                                                                                                                    | `5`                         |
| `injector.startupProbe.failureThreshold`                     | Failure threshold for startupProbe                                                                                                                                                                                                  | `5`                         |
| `injector.startupProbe.successThreshold`                     | Success threshold for startupProbe                                                                                                                                                                                                  | `1`                         |
| `injector.customLivenessProbe`                               | Custom livenessProbe that overrides the default one                                                                                                                                                                                 | `{}`                        |
| `injector.customReadinessProbe`                              | Custom readinessProbe that overrides the default one                                                                                                                                                                                | `{}`                        |
| `injector.customStartupProbe`                                | Custom startupProbe that overrides the default one                                                                                                                                                                                  | `{}`                        |
| `injector.resourcesPreset`                                   | Set container resources according to one common preset (allowed values: none, nano, micro, small, medium, large, xlarge, 2xlarge). This is ignored if injector.resources is set (injector.resources is recommended for production). | `nano`                      |
| `injector.resources`                                         | Set container requests and limits for different resources like CPU or memory (essential for production workloads)                                                                                                                   | `{}`                        |
| `injector.podSecurityContext.enabled`                        | Enabled Vault Kubernetes Injector pods' Security Context                                                                                                                                                                            | `true`                      |
| `injector.podSecurityContext.fsGroupChangePolicy`            | Set filesystem group change policy                                                                                                                                                                                                  | `Always`                    |
| `injector.podSecurityContext.sysctls`                        | Set kernel settings using the sysctl interface                                                                                                                                                                                      | `[]`                        |
| `injector.podSecurityContext.supplementalGroups`             | Set filesystem extra groups                                                                                                                                                                                                         | `[]`                        |
| `injector.podSecurityContext.fsGroup`                        | Set Vault Kubernetes Injector pod's Security Context fsGroup                                                                                                                                                                        | `1001`                      |
| `injector.containerSecurityContext.enabled`                  | Enabled containers' Security Context                                                                                                                                                                                                | `true`                      |
| `injector.containerSecurityContext.seLinuxOptions`           | Set SELinux options in container                                                                                                                                                                                                    | `{}`                        |
| `injector.containerSecurityContext.runAsUser`                | Set containers' Security Context runAsUser                                                                                                                                                                                          | `1001`                      |
| `injector.containerSecurityContext.runAsGroup`               | Set containers' Security Context runAsGroup                                                                                                                                                                                         | `1001`                      |
| `injector.containerSecurityContext.runAsNonRoot`             | Set container's Security Context runAsNonRoot                                                                                                                                                                                       | `true`                      |
| `injector.containerSecurityContext.privileged`               | Set container's Security Context privileged                                                                                                                                                                                         | `false`                     |
| `injector.containerSecurityContext.readOnlyRootFilesystem`   | Set container's Security Context readOnlyRootFilesystem                                                                                                                                                                             | `true`                      |
| `injector.containerSecurityContext.allowPrivilegeEscalation` | Set container's Security Context allowPrivilegeEscalation                                                                                                                                                                           | `false`                     |
| `injector.containerSecurityContext.capabilities.drop`        | List of capabilities to be dropped                                                                                                                                                                                                  | `["ALL"]`                   |
| `injector.containerSecurityContext.seccompProfile.type`      | Set container's Security Context seccomp profile                                                                                                                                                                                    | `RuntimeDefault`            |
| `injector.command`                                           | Override default container command (useful when using custom images)                                                                                                                                                                | `[]`                        |
| `injector.args`                                              | Override default container args (useful when using custom images)                                                                                                                                                                   | `[]`                        |
| `injector.automountServiceAccountToken`                      | Mount Service Account token in pod                                                                                                                                                                                                  | `true`                      |
| `injector.hostAliases`                                       | Vault Kubernetes Injector pods host aliases                                                                                                                                                                                         | `[]`                        |
| `injector.podLabels`                                         | Extra labels for Vault Kubernetes Injector pods                                                                                                                                                                                     | `{}`                        |
| `injector.podAnnotations`                                    | Annotations for Vault Kubernetes Injector pods                                                                                                                                                                                      | `{}`                        |
| `injector.podAffinityPreset`                                 | Pod affinity preset. Ignored if `injector.affinity` is set. Allowed values: `soft` or `hard`                                                                                                                                        | `""`                        |
| `injector.podAntiAffinityPreset`                             | Pod anti-affinity preset. Ignored if `injector.affinity` is set. Allowed values: `soft` or `hard`                                                                                                                                   | `soft`                      |
| `injector.pdb.create`                                        | Enable/disable a Pod Disruption Budget creation                                                                                                                                                                                     | `true`                      |
| `injector.pdb.minAvailable`                                  | Minimum number/percentage of pods that should remain scheduled                                                                                                                                                                      | `""`                        |
| `injector.pdb.maxUnavailable`                                | Maximum number/percentage of pods that may be made unavailable. Defaults to `1` if both `injector.pdb.minAvailable` and `injector.pdb.maxUnavailable` are empty.                                                                    | `""`                        |
| `injector.autoscaling.enabled`                               | Enable autoscaling for injector                                                                                                                                                                                                     | `false`                     |
| `injector.autoscaling.minReplicas`                           | Minimum number of injector replicas                                                                                                                                                                                                 | `""`                        |
| `injector.autoscaling.maxReplicas`                           | Maximum number of injector replicas                                                                                                                                                                                                 | `""`                        |
| `injector.autoscaling.targetCPU`                             | Target CPU utilization percentage                                                                                                                                                                                                   | `""`                        |
| `injector.autoscaling.targetMemory`                          | Target Memory utilization percentage                                                                                                                                                                                                | `""`                        |
| `injector.nodeAffinityPreset.type`                           | Node affinity preset type. Ignored if `injector.affinity` is set. Allowed values: `soft` or `hard`                                                                                                                                  | `""`                        |
| `injector.nodeAffinityPreset.key`                            | Node label key to match. Ignored if `injector.affinity` is set                                                                                                                                                                      | `""`                        |
| `injector.nodeAffinityPreset.values`                         | Node label values to match. Ignored if `injector.affinity` is set                                                                                                                                                                   | `[]`                        |
| `injector.affinity`                                          | Affinity for Vault Kubernetes Injector pods assignment                                                                                                                                                                              | `{}`                        |
| `injector.nodeSelector`                                      | Node labels for Vault Kubernetes Injector pods assignment                                                                                                                                                                           | `{}`                        |
| `injector.tolerations`                                       | Tolerations for Vault Kubernetes Injector pods assignment                                                                                                                                                                           | `[]`                        |
| `injector.updateStrategy.type`                               | Vault Kubernetes Injector statefulset strategy type                                                                                                                                                                                 | `RollingUpdate`             |
| `injector.priorityClassName`                                 | Vault Kubernetes Injector pods' priorityClassName                                                                                                                                                                                   | `""`                        |
| `injector.topologySpreadConstraints`                         | Topology Spread Constraints for pod assignment spread across your cluster among failure-domains. Evaluated as a template                                                                                                            | `[]`                        |
| `injector.schedulerName`                                     | Name of the k8s scheduler (other than default) for Vault Kubernetes Injector pods                                                                                                                                                   | `""`                        |
| `injector.terminationGracePeriodSeconds`                     | Seconds Redmine pod needs to terminate gracefully                                                                                                                                                                                   | `""`                        |
| `injector.lifecycleHooks`                                    | for the Vault Kubernetes Injector container(s) to automate configuration before or after startup                                                                                                                                    | `{}`                        |
| `injector.extraEnvVars`                                      | Array with extra environment variables to add to Vault Kubernetes Injector nodes                                                                                                                                                    | `[]`                        |
| `injector.extraEnvVarsCM`                                    | Name of existing ConfigMap containing extra env vars for Vault Kubernetes Injector nodes                                                                                                                                            | `""`                        |
| `injector.extraEnvVarsSecret`                                | Name of existing Secret containing extra env vars for Vault Kubernetes Injector nodes                                                                                                                                               | `""`                        |
| `injector.extraVolumes`                                      | Optionally specify extra list of additional volumes for the Vault Kubernetes Injector pod(s)                                                                                                                                        | `[]`                        |
| `injector.extraVolumeMounts`                                 | Optionally specify extra list of additional volumeMounts for the Vault Kubernetes Injector container(s)                                                                                                                             | `[]`                        |
| `injector.sidecars`                                          | Add additional sidecar containers to the Vault Kubernetes Injector pod(s)                                                                                                                                                           | `[]`                        |
| `injector.initContainers`                                    | Add additional init containers to the Vault Kubernetes Injector pod(s)                                                                                                                                                              | `[]`                        |

### Vault Kubernetes Injector Traffic Exposure Parameters

| Name                                             | Description                                                                                          | Value       |
| ------------------------------------------------ | ---------------------------------------------------------------------------------------------------- | ----------- |
| `injector.service.type`                          | Vault Kubernetes Injector service type                                                               | `ClusterIP` |
| `injector.service.ports.https`                   | Vault Kubernetes Injector service HTTPS port                                                         | `443`       |
| `injector.service.nodePorts.https`               | Node port for HTTPS                                                                                  | `""`        |
| `injector.service.clusterIP`                     | Vault Kubernetes Injector service Cluster IP                                                         | `""`        |
| `injector.service.loadBalancerIP`                | Vault Kubernetes Injector service Load Balancer IP                                                   | `""`        |
| `injector.service.loadBalancerSourceRanges`      | Vault Kubernetes Injector service Load Balancer sources                                              | `[]`        |
| `injector.service.externalTrafficPolicy`         | Vault Kubernetes Injector service external traffic policy                                            | `Cluster`   |
| `injector.service.annotations`                   | Additional custom annotations for Vault Kubernetes Injector service                                  | `{}`        |
| `injector.service.extraPorts`                    | Extra ports to expose in Vault Kubernetes Injector service (normally used with the `sidecars` value) | `[]`        |
| `injector.service.sessionAffinity`               | Control where web requests go, to the same pod or round-robin                                        | `None`      |
| `injector.service.sessionAffinityConfig`         | Additional settings for the sessionAffinity                                                          | `{}`        |
| `injector.networkPolicy.enabled`                 | Specifies whether a NetworkPolicy should be created                                                  | `true`      |
| `injector.networkPolicy.kubeAPIServerPorts`      | List of possible endpoints to kube-apiserver (limit to your cluster settings to increase security)   | `[]`        |
| `injector.networkPolicy.allowExternal`           | Don't require injector label for connections                                                         | `true`      |
| `injector.networkPolicy.allowExternalEgress`     | Allow the pod to access any range of port and all destinations.                                      | `true`      |
| `injector.networkPolicy.extraIngress`            | Add extra ingress rules to the NetworkPolicy                                                         | `[]`        |
| `injector.networkPolicy.extraEgress`             | Add extra ingress rules to the NetworkPolicy                                                         | `[]`        |
| `injector.networkPolicy.ingressNSMatchLabels`    | Labels to match to allow traffic from other namespaces                                               | `{}`        |
| `injector.networkPolicy.ingressNSPodMatchLabels` | Pod labels to match to allow traffic from other namespaces                                           | `{}`        |

### Vault Kubernetes Injector RBAC Parameters

| Name                                                        | Description                                                                                                                                                                                                                                           | Value                      |
| ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------- |
| `injector.rbac.create`                                      | Specifies whether RBAC resources should be created                                                                                                                                                                                                    | `true`                     |
| `injector.rbac.rules`                                       | Custom RBAC rules to set                                                                                                                                                                                                                              | `[]`                       |
| `injector.serviceAccount.create`                            | Specifies whether a ServiceAccount should be created                                                                                                                                                                                                  | `true`                     |
| `injector.serviceAccount.name`                              | The name of the ServiceAccount to use.                                                                                                                                                                                                                | `""`                       |
| `injector.serviceAccount.annotations`                       | Additional Service Account annotations (evaluated as a template)                                                                                                                                                                                      | `{}`                       |
| `injector.serviceAccount.automountServiceAccountToken`      | Automount service account token for the server service account                                                                                                                                                                                        | `false`                    |
| `injector.webhook.namespaceSelector`                        | Enabling specify which namespace you want to work with webhook                                                                                                                                                                                        | `{}`                       |
| `injector.webhook.clientConfig.caBundle`                    | is a PEM encoded CA bundle which will be used to validate the webhook's server certificate. If unspecified, system trust roots on theapiserver are used.                                                                                              | `""`                       |
| `volumePermissions.enabled`                                 | Enable init container that changes the owner/group of the PV mount point to `runAsUser:fsGroup`                                                                                                                                                       | `false`                    |
| `volumePermissions.image.registry`                          | OS Shell + Utility image registry                                                                                                                                                                                                                     | `REGISTRY_NAME`            |
| `volumePermissions.image.repository`                        | OS Shell + Utility image repository                                                                                                                                                                                                                   | `REPOSITORY_NAME/os-shell` |
| `volumePermissions.image.digest`                            | OS Shell + Utility image digest in the way sha256:aa.... Please note this parameter, if set, will override the tag                                                                                                                                    | `""`                       |
| `volumePermissions.image.pullPolicy`                        | OS Shell + Utility image pull policy                                                                                                                                                                                                                  | `IfNotPresent`             |
| `volumePermissions.image.pullSecrets`                       | OS Shell + Utility image pull secrets                                                                                                                                                                                                                 | `[]`                       |
| `volumePermissions.resourcesPreset`                         | Set container resources according to one common preset (allowed values: none, nano, micro, small, medium, large, xlarge, 2xlarge). This is ignored if volumePermissions.resources is set (volumePermissions.resources is recommended for production). | `nano`                     |
| `volumePermissions.resources`                               | Set container requests and limits for different resources like CPU or memory (essential for production workloads)                                                                                                                                     | `{}`                       |
| `volumePermissions.containerSecurityContext.enabled`        | Enable init container's Security Context                                                                                                                                                                                                              | `true`                     |
| `volumePermissions.containerSecurityContext.seLinuxOptions` | Set SELinux options in container                                                                                                                                                                                                                      | `{}`                       |
| `volumePermissions.containerSecurityContext.runAsUser`      | Set init container's Security Context runAsUser                                                                                                                                                                                                       | `0`                        |

The above parameters map to the env variables defined in [bitnami/vault](https://github.com/bitnami/containers/tree/main/bitnami/vault). For more information please refer to the [bitnami/vault](https://github.com/bitnami/containers/tree/main/bitnami/vault) image documentation.

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

```console
helm install my-release \
  --set csiProvider.enabled=true \
    my-repo/vault
```

The above command enables the Vault CSI Provider deployment.

> NOTE: Once this chart is deployed, it is not possible to change the application's access credentials, such as usernames or passwords, using Helm. To change these application credentials after deployment, delete any persistent volumes (PVs) used by the chart and re-deploy it, or use the application's built-in administrative tools if available.

Alternatively, a YAML file that specifies the values for the above parameters can be provided while installing the chart. For example,

```console
helm install my-release -f values.yaml my-repo/vault
```

> **Tip**: You can use the default [values.yaml](https://github.com/bitnami/charts/tree/main/bitnami/vault/values.yaml)


## License

Copyright &copy; 2025 Broadcom. The term "Broadcom" refers to Broadcom Inc. and/or its subsidiaries.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

<http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
