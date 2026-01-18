# Citus Helm Chart

Citus 是基于 PostgreSQL 的分布式关系型数据库管理系统（RDBMS），能够对 PostgreSQL 进行水平扩展，以处理更大的数据量和更高的并发负载。

## 概述

本 Helm Chart 用于在 Kubernetes 集群上部署 Citus 分布式数据库集群，包含以下组件：

- **Coordinator 节点**：负责协调查询，管理元数据和分片位置
- **Worker 节点**：存储和处理数据分片
- **Worker 注册作业**：自动将 Worker 节点注册到 Coordinator

## 前提条件

- Kubernetes 1.23+
- Helm 3.8.0+
- PV provisioner 支持（如果启用持久化存储）

## 安装

### 快速安装

```bash
helm install my-citus ./citus \
  --namespace citus \
  --create-namespace \
  --set auth.postgresPassword=mypassword
```

### 使用自定义配置安装

```bash
helm install my-citus ./citus \
  --namespace citus \
  --create-namespace \
  -f values.yaml
```

## 卸载

```bash
helm uninstall my-citus -n citus
kubectl delete pvc -l app.kubernetes.io/instance=my-citus -n citus
```

## 架构

```
                     ┌─────────────────┐
                     │   Application   │
                     └────────┬────────┘
                              │
                              ▼
                     ┌─────────────────┐
                     │   Coordinator   │
                     │   (PostgreSQL   │
                     │   + Citus)      │
                     └────────┬────────┘
                              │
           ┌──────────────────┼──────────────────┐
           │                  │                  │
           ▼                  ▼                  ▼
    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
    │   Worker 0  │    │   Worker 1  │    │   Worker N  │
    │  (Shards)   │    │  (Shards)   │    │  (Shards)   │
    └─────────────┘    └─────────────┘    └─────────────┘
```

## 配置参数

### 全局参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `global.imageRegistry` | 全局 Docker 镜像仓库 | `""` |
| `global.imagePullSecrets` | 全局 Docker 镜像拉取密钥 | `[]` |
| `global.storageClass` | 全局 StorageClass | `""` |

### 通用参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `kubeVersion` | 覆盖 Kubernetes 版本 | `""` |
| `nameOverride` | 部分覆盖 Chart 名称 | `""` |
| `fullnameOverride` | 完全覆盖 Chart 名称 | `""` |
| `commonLabels` | 添加到所有资源的标签 | `{}` |
| `commonAnnotations` | 添加到所有资源的注解 | `{}` |
| `clusterDomain` | Kubernetes 集群域名 | `cluster.local` |
| `extraDeploy` | 额外部署的资源列表 | `[]` |

### Citus 镜像参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `image.registry` | Citus 镜像仓库 | `docker.io` |
| `image.repository` | Citus 镜像名称 | `citusdata/citus` |
| `image.tag` | Citus 镜像标签 | `13.0.3` |
| `image.digest` | Citus 镜像摘要（覆盖 tag） | `""` |
| `image.pullPolicy` | 镜像拉取策略 | `IfNotPresent` |
| `image.pullSecrets` | 镜像拉取密钥 | `[]` |

### 认证参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `auth.enablePostgresUser` | 启用 postgres 管理员用户 | `true` |
| `auth.postgresPassword` | postgres 管理员密码 | `""` |
| `auth.username` | 自定义用户名 | `citus` |
| `auth.password` | 自定义用户密码 | `""` |
| `auth.database` | 数据库名称 | `citus` |
| `auth.existingSecret` | 使用现有 Secret 名称 | `""` |
| `auth.secretKeys.adminPasswordKey` | Secret 中管理员密码的键名 | `postgres-password` |
| `auth.secretKeys.userPasswordKey` | Secret 中用户密码的键名 | `password` |
| `auth.usePasswordFiles` | 以文件形式挂载密码 | `false` |

### PostgreSQL 通用配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `postgresql.sharedPreloadLibraries` | 预加载共享库 | `citus` |
| `postgresql.maxConnections` | 最大连接数 | `200` |
| `postgresql.walLevel` | WAL 级别（logical 用于重平衡） | `logical` |
| `postgresql.maxWalSenders` | 最大 WAL 发送进程数 | `10` |
| `postgresql.maxReplicationSlots` | 最大复制槽数量 | `10` |
| `postgresql.maxWorkerProcesses` | 最大工作进程数 | `64` |
| `postgresql.citusShardCount` | 默认分片数量 | `32` |
| `postgresql.citusShardReplicationFactor` | 分片复制因子 | `1` |
| `postgresql.extraConfiguration` | 额外 PostgreSQL 配置 | `""` |

### Coordinator 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `coordinator.replicaCount` | Coordinator 副本数（推荐 1） | `1` |
| `coordinator.podManagementPolicy` | StatefulSet Pod 管理策略 | `OrderedReady` |
| `coordinator.updateStrategy.type` | 更新策略类型 | `RollingUpdate` |
| `coordinator.hostAliases` | Pod 主机别名 | `[]` |
| `coordinator.podLabels` | 额外 Pod 标签 | `{}` |
| `coordinator.podAnnotations` | Pod 注解 | `{}` |
| `coordinator.podAffinityPreset` | Pod 亲和性预设 | `""` |
| `coordinator.podAntiAffinityPreset` | Pod 反亲和性预设 | `soft` |
| `coordinator.nodeAffinityPreset.type` | 节点亲和性预设类型 | `""` |
| `coordinator.nodeAffinityPreset.key` | 节点亲和性标签键 | `""` |
| `coordinator.nodeAffinityPreset.values` | 节点亲和性标签值 | `[]` |
| `coordinator.affinity` | 亲和性配置 | `{}` |
| `coordinator.nodeSelector` | 节点选择器 | `{}` |
| `coordinator.tolerations` | 容忍度 | `[]` |
| `coordinator.topologySpreadConstraints` | 拓扑分布约束 | `[]` |
| `coordinator.priorityClassName` | 优先级类名 | `""` |
| `coordinator.schedulerName` | 调度器名称 | `""` |
| `coordinator.terminationGracePeriodSeconds` | 终止宽限期 | `30` |
| `coordinator.containerPorts.postgresql` | PostgreSQL 容器端口 | `5432` |
| `coordinator.command` | 覆盖容器命令 | `[]` |
| `coordinator.args` | 覆盖容器参数 | `[]` |
| `coordinator.extraEnvVars` | 额外环境变量 | `[]` |
| `coordinator.extraEnvVarsCM` | 额外环境变量 ConfigMap | `""` |
| `coordinator.extraEnvVarsSecret` | 额外环境变量 Secret | `""` |
| `coordinator.extraVolumes` | 额外卷 | `[]` |
| `coordinator.extraVolumeMounts` | 额外卷挂载 | `[]` |
| `coordinator.sidecars` | 边车容器 | `[]` |
| `coordinator.initContainers` | 初始化容器 | `[]` |
| `coordinator.lifecycleHooks` | 生命周期钩子 | `{}` |

#### Coordinator 安全上下文

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `coordinator.containerSecurityContext.enabled` | 启用容器安全上下文 | `true` |
| `coordinator.containerSecurityContext.runAsUser` | 运行用户 ID | `1001` |
| `coordinator.containerSecurityContext.runAsGroup` | 运行组 ID | `1001` |
| `coordinator.containerSecurityContext.runAsNonRoot` | 以非 root 运行 | `true` |
| `coordinator.containerSecurityContext.allowPrivilegeEscalation` | 允许权限提升 | `false` |
| `coordinator.containerSecurityContext.readOnlyRootFilesystem` | 只读根文件系统 | `false` |
| `coordinator.containerSecurityContext.seccompProfile.type` | Seccomp 配置类型 | `RuntimeDefault` |
| `coordinator.containerSecurityContext.capabilities.drop` | 删除的能力 | `["ALL"]` |
| `coordinator.podSecurityContext.enabled` | 启用 Pod 安全上下文 | `true` |
| `coordinator.podSecurityContext.fsGroup` | 文件系统组 | `1001` |
| `coordinator.podSecurityContext.fsGroupChangePolicy` | fsGroup 变更策略 | `Always` |

#### Coordinator 资源配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `coordinator.resources.limits` | 资源限制 | `{cpu: 2, memory: 4Gi}` |
| `coordinator.resources.requests.cpu` | CPU 请求 | `500m` |
| `coordinator.resources.requests.memory` | 内存请求 | `1Gi` |
| `coordinator.resourcesPreset` | 资源预设 (none/nano/micro/small/medium/large/xlarge/2xlarge) | `none` |

#### Coordinator 探针配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `coordinator.livenessProbe.enabled` | 启用存活探针 | `true` |
| `coordinator.livenessProbe.initialDelaySeconds` | 初始延迟 | `30` |
| `coordinator.livenessProbe.periodSeconds` | 检查周期 | `10` |
| `coordinator.livenessProbe.timeoutSeconds` | 超时时间 | `5` |
| `coordinator.livenessProbe.failureThreshold` | 失败阈值 | `6` |
| `coordinator.livenessProbe.successThreshold` | 成功阈值 | `1` |
| `coordinator.readinessProbe.enabled` | 启用就绪探针 | `true` |
| `coordinator.readinessProbe.initialDelaySeconds` | 初始延迟 | `10` |
| `coordinator.readinessProbe.periodSeconds` | 检查周期 | `5` |
| `coordinator.readinessProbe.timeoutSeconds` | 超时时间 | `5` |
| `coordinator.readinessProbe.failureThreshold` | 失败阈值 | `6` |
| `coordinator.readinessProbe.successThreshold` | 成功阈值 | `1` |
| `coordinator.startupProbe.enabled` | 启用启动探针 | `false` |
| `coordinator.startupProbe.initialDelaySeconds` | 初始延迟 | `30` |
| `coordinator.startupProbe.periodSeconds` | 检查周期 | `10` |
| `coordinator.startupProbe.timeoutSeconds` | 超时时间 | `5` |
| `coordinator.startupProbe.failureThreshold` | 失败阈值 | `10` |
| `coordinator.startupProbe.successThreshold` | 成功阈值 | `1` |
| `coordinator.customLivenessProbe` | 自定义存活探针 | `{}` |
| `coordinator.customReadinessProbe` | 自定义就绪探针 | `{}` |
| `coordinator.customStartupProbe` | 自定义启动探针 | `{}` |

#### Coordinator 持久化存储

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `coordinator.persistence.enabled` | 启用持久化存储 | `true` |
| `coordinator.persistence.existingClaim` | 使用现有 PVC | `""` |
| `coordinator.persistence.storageClass` | 存储类 | `""` |
| `coordinator.persistence.accessModes` | 访问模式 | `["ReadWriteOnce"]` |
| `coordinator.persistence.size` | 存储大小 | `10Gi` |
| `coordinator.persistence.annotations` | PVC 注解 | `{}` |
| `coordinator.persistence.labels` | PVC 标签 | `{}` |
| `coordinator.persistence.selector` | PVC 选择器 | `{}` |

#### Coordinator 服务配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `coordinator.service.type` | 服务类型 | `ClusterIP` |
| `coordinator.service.ports.postgresql` | PostgreSQL 端口 | `5432` |
| `coordinator.service.nodePorts.postgresql` | NodePort 端口 | `""` |
| `coordinator.service.clusterIP` | 集群 IP | `""` |
| `coordinator.service.loadBalancerIP` | 负载均衡 IP | `""` |
| `coordinator.service.loadBalancerSourceRanges` | 负载均衡源范围 | `[]` |
| `coordinator.service.externalTrafficPolicy` | 外部流量策略 | `Cluster` |
| `coordinator.service.annotations` | 服务注解 | `{}` |
| `coordinator.service.extraPorts` | 额外端口 | `[]` |
| `coordinator.service.sessionAffinity` | 会话亲和性 | `None` |
| `coordinator.service.sessionAffinityConfig` | 会话亲和性配置 | `{}` |

#### Coordinator ServiceAccount

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `coordinator.serviceAccount.create` | 创建 ServiceAccount | `true` |
| `coordinator.serviceAccount.name` | ServiceAccount 名称 | `""` |
| `coordinator.serviceAccount.annotations` | ServiceAccount 注解 | `{}` |
| `coordinator.serviceAccount.automountServiceAccountToken` | 自动挂载 Token | `false` |

#### Coordinator PDB

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `coordinator.pdb.create` | 创建 PodDisruptionBudget | `true` |
| `coordinator.pdb.minAvailable` | 最小可用数 | `1` |
| `coordinator.pdb.maxUnavailable` | 最大不可用数 | `""` |

#### Coordinator VPA (Vertical Pod Autoscaler)

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `coordinator.vpa.enabled` | 启用 VPA | `false` |
| `coordinator.vpa.annotations` | VPA 注解 | `{}` |
| `coordinator.vpa.updateMode` | 更新模式 (Auto/Recreate/Initial/Off) | `Auto` |
| `coordinator.vpa.controlledResources` | 受控资源类型 | `[]` |
| `coordinator.vpa.maxAllowed` | 最大资源限制 | `{}` |
| `coordinator.vpa.minAllowed` | 最小资源限制 | `{}` |
| `coordinator.vpa.containerPolicies.main` | 主容器策略 | `{}` |

### Worker 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `worker.replicaCount` | Worker 副本数 | `3` |
| `worker.podManagementPolicy` | StatefulSet Pod 管理策略 | `Parallel` |
| `worker.updateStrategy.type` | 更新策略类型 | `RollingUpdate` |
| `worker.hostAliases` | Pod 主机别名 | `[]` |
| `worker.podLabels` | 额外 Pod 标签 | `{}` |
| `worker.podAnnotations` | Pod 注解 | `{}` |
| `worker.podAffinityPreset` | Pod 亲和性预设 | `""` |
| `worker.podAntiAffinityPreset` | Pod 反亲和性预设 | `soft` |
| `worker.nodeAffinityPreset.type` | 节点亲和性预设类型 | `""` |
| `worker.nodeAffinityPreset.key` | 节点亲和性标签键 | `""` |
| `worker.nodeAffinityPreset.values` | 节点亲和性标签值 | `[]` |
| `worker.affinity` | 亲和性配置 | `{}` |
| `worker.nodeSelector` | 节点选择器 | `{}` |
| `worker.tolerations` | 容忍度 | `[]` |
| `worker.topologySpreadConstraints` | 拓扑分布约束 | `[]` |
| `worker.priorityClassName` | 优先级类名 | `""` |
| `worker.schedulerName` | 调度器名称 | `""` |
| `worker.terminationGracePeriodSeconds` | 终止宽限期 | `30` |
| `worker.containerPorts.postgresql` | PostgreSQL 容器端口 | `5432` |
| `worker.command` | 覆盖容器命令 | `[]` |
| `worker.args` | 覆盖容器参数 | `[]` |
| `worker.extraEnvVars` | 额外环境变量 | `[]` |
| `worker.extraEnvVarsCM` | 额外环境变量 ConfigMap | `""` |
| `worker.extraEnvVarsSecret` | 额外环境变量 Secret | `""` |
| `worker.extraVolumes` | 额外卷 | `[]` |
| `worker.extraVolumeMounts` | 额外卷挂载 | `[]` |
| `worker.sidecars` | 边车容器 | `[]` |
| `worker.initContainers` | 初始化容器 | `[]` |
| `worker.lifecycleHooks` | 生命周期钩子 | `{}` |

#### Worker 安全上下文

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `worker.containerSecurityContext.enabled` | 启用容器安全上下文 | `true` |
| `worker.containerSecurityContext.runAsUser` | 运行用户 ID | `1001` |
| `worker.containerSecurityContext.runAsGroup` | 运行组 ID | `1001` |
| `worker.containerSecurityContext.runAsNonRoot` | 以非 root 运行 | `true` |
| `worker.containerSecurityContext.allowPrivilegeEscalation` | 允许权限提升 | `false` |
| `worker.containerSecurityContext.readOnlyRootFilesystem` | 只读根文件系统 | `false` |
| `worker.containerSecurityContext.seccompProfile.type` | Seccomp 配置类型 | `RuntimeDefault` |
| `worker.containerSecurityContext.capabilities.drop` | 删除的能力 | `["ALL"]` |
| `worker.podSecurityContext.enabled` | 启用 Pod 安全上下文 | `true` |
| `worker.podSecurityContext.fsGroup` | 文件系统组 | `1001` |
| `worker.podSecurityContext.fsGroupChangePolicy` | fsGroup 变更策略 | `Always` |

#### Worker 资源配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `worker.resources.limits` | 资源限制 | `{cpu: 2, memory: 4Gi}` |
| `worker.resources.requests.cpu` | CPU 请求 | `500m` |
| `worker.resources.requests.memory` | 内存请求 | `1Gi` |
| `worker.resourcesPreset` | 资源预设 (none/nano/micro/small/medium/large/xlarge/2xlarge) | `none` |

#### Worker 探针配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `worker.livenessProbe.enabled` | 启用存活探针 | `true` |
| `worker.livenessProbe.initialDelaySeconds` | 初始延迟 | `30` |
| `worker.livenessProbe.periodSeconds` | 检查周期 | `10` |
| `worker.livenessProbe.timeoutSeconds` | 超时时间 | `5` |
| `worker.livenessProbe.failureThreshold` | 失败阈值 | `6` |
| `worker.livenessProbe.successThreshold` | 成功阈值 | `1` |
| `worker.readinessProbe.enabled` | 启用就绪探针 | `true` |
| `worker.readinessProbe.initialDelaySeconds` | 初始延迟 | `10` |
| `worker.readinessProbe.periodSeconds` | 检查周期 | `5` |
| `worker.readinessProbe.timeoutSeconds` | 超时时间 | `5` |
| `worker.readinessProbe.failureThreshold` | 失败阈值 | `6` |
| `worker.readinessProbe.successThreshold` | 成功阈值 | `1` |
| `worker.startupProbe.enabled` | 启用启动探针 | `false` |
| `worker.customLivenessProbe` | 自定义存活探针 | `{}` |
| `worker.customReadinessProbe` | 自定义就绪探针 | `{}` |
| `worker.customStartupProbe` | 自定义启动探针 | `{}` |

#### Worker 持久化存储

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `worker.persistence.enabled` | 启用持久化存储 | `true` |
| `worker.persistence.storageClass` | 存储类 | `""` |
| `worker.persistence.accessModes` | 访问模式 | `["ReadWriteOnce"]` |
| `worker.persistence.size` | 存储大小 | `10Gi` |
| `worker.persistence.annotations` | PVC 注解 | `{}` |
| `worker.persistence.labels` | PVC 标签 | `{}` |
| `worker.persistence.selector` | PVC 选择器 | `{}` |

#### Worker 服务配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `worker.service.type` | 服务类型 | `ClusterIP` |
| `worker.service.ports.postgresql` | PostgreSQL 端口 | `5432` |
| `worker.service.clusterIP` | 集群 IP（Headless 为 None） | `None` |
| `worker.service.annotations` | 服务注解 | `{}` |
| `worker.service.extraPorts` | 额外端口 | `[]` |

#### Worker ServiceAccount

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `worker.serviceAccount.create` | 创建 ServiceAccount | `true` |
| `worker.serviceAccount.name` | ServiceAccount 名称 | `""` |
| `worker.serviceAccount.annotations` | ServiceAccount 注解 | `{}` |
| `worker.serviceAccount.automountServiceAccountToken` | 自动挂载 Token | `false` |

#### Worker PDB

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `worker.pdb.create` | 创建 PodDisruptionBudget | `true` |
| `worker.pdb.minAvailable` | 最小可用数 | `""` |
| `worker.pdb.maxUnavailable` | 最大不可用数 | `1` |

#### Worker 自动扩缩 (HPA)

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `worker.autoscaling.enabled` | 启用 HPA | `false` |
| `worker.autoscaling.minReplicas` | 最小副本数 | `3` |
| `worker.autoscaling.maxReplicas` | 最大副本数 | `10` |
| `worker.autoscaling.targetCPU` | 目标 CPU 使用率 | `70` |
| `worker.autoscaling.targetMemory` | 目标内存使用率 | `""` |

#### Worker VPA (Vertical Pod Autoscaler)

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `worker.vpa.enabled` | 启用 VPA | `false` |
| `worker.vpa.annotations` | VPA 注解 | `{}` |
| `worker.vpa.updateMode` | 更新模式 (Auto/Recreate/Initial/Off) | `Auto` |
| `worker.vpa.controlledResources` | 受控资源类型 | `[]` |
| `worker.vpa.maxAllowed` | 最大资源限制 | `{}` |
| `worker.vpa.minAllowed` | 最小资源限制 | `{}` |
| `worker.vpa.containerPolicies.main` | 主容器策略 | `{}` |

### Worker 注册作业配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `workerRegistration.enabled` | 启用自动 Worker 注册 | `true` |
| `workerRegistration.ttlSecondsAfterFinished` | 完成后清理 TTL | `600` |
| `workerRegistration.backoffLimit` | 重试次数 | `5` |
| `workerRegistration.activeDeadlineSeconds` | 最大执行时间 | `300` |
| `workerRegistration.podAnnotations` | Pod 注解 | `{}` |
| `workerRegistration.resources.requests.cpu` | CPU 请求 | `100m` |
| `workerRegistration.resources.requests.memory` | 内存请求 | `128Mi` |

### 网络策略配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `networkPolicy.enabled` | 启用 NetworkPolicy | `false` |
| `networkPolicy.allowExternal` | 允许外部连接 | `true` |
| `networkPolicy.allowExternalEgress` | 允许外部出口 | `true` |
| `networkPolicy.extraIngress` | 额外入口规则 | `[]` |
| `networkPolicy.extraEgress` | 额外出口规则 | `[]` |
| `networkPolicy.ingressNSMatchLabels` | 入口命名空间标签匹配 | `{}` |
| `networkPolicy.ingressNSPodMatchLabels` | 入口 Pod 标签匹配 | `{}` |

### 监控配置（Prometheus）

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `metrics.enabled` | 启用 Prometheus 指标导出器 | `false` |
| `metrics.image.registry` | 导出器镜像仓库 | `docker.io` |
| `metrics.image.repository` | 导出器镜像名称 | `prometheuscommunity/postgres-exporter` |
| `metrics.image.tag` | 导出器镜像标签 | `v0.15.0` |
| `metrics.containerPorts.metrics` | 指标端口 | `9187` |
| `metrics.resources.requests.cpu` | CPU 请求 | `100m` |
| `metrics.resources.requests.memory` | 内存请求 | `128Mi` |
| `metrics.serviceMonitor.enabled` | 启用 ServiceMonitor | `false` |
| `metrics.serviceMonitor.namespace` | ServiceMonitor 命名空间 | `""` |
| `metrics.serviceMonitor.interval` | 抓取间隔 | `30s` |
| `metrics.serviceMonitor.scrapeTimeout` | 抓取超时 | `10s` |
| `metrics.serviceMonitor.labels` | 标签 | `{}` |
| `metrics.prometheusRule.enabled` | 启用 PrometheusRule | `false` |
| `metrics.prometheusRule.rules` | 告警规则 | `[]` |

### 备份配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `backup.enabled` | 启用定时备份 | `false` |
| `backup.schedule` | Cron 调度表达式 | `0 2 * * *` |
| `backup.image.registry` | 备份镜像仓库 | `docker.io` |
| `backup.image.repository` | 备份镜像名称 | `postgres` |
| `backup.image.tag` | 备份镜像标签 | `17` |
| `backup.persistence.enabled` | 启用备份持久化 | `true` |
| `backup.persistence.storageClass` | 存储类 | `""` |
| `backup.persistence.size` | 存储大小 | `20Gi` |
| `backup.retentionDays` | 备份保留天数 | `7` |

### Ingress 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `ingress.enabled` | 启用 Ingress | `false` |
| `ingress.ingressClassName` | Ingress 类名 | `""` |
| `ingress.hostname` | 主机名 | `citus.local` |
| `ingress.path` | 路径 | `/` |
| `ingress.pathType` | 路径类型 | `ImplementationSpecific` |
| `ingress.annotations` | 注解 | `{}` |
| `ingress.tls` | 启用 TLS | `false` |
| `ingress.extraHosts` | 额外主机 | `[]` |
| `ingress.extraTls` | 额外 TLS 配置 | `[]` |

### Volume Permissions 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `volumePermissions.enabled` | 启用卷权限初始化容器 | `false` |
| `volumePermissions.image.registry` | 镜像仓库 | `docker.io` |
| `volumePermissions.image.repository` | 镜像名称 | `bitnami/os-shell` |
| `volumePermissions.image.tag` | 镜像标签 | `12-debian-12-r40` |
| `volumePermissions.containerSecurityContext.runAsUser` | 运行用户 | `0` |

### 诊断模式

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `diagnosticMode.enabled` | 启用诊断模式 | `false` |
| `diagnosticMode.command` | 覆盖容器命令 | `["sleep"]` |
| `diagnosticMode.args` | 覆盖容器参数 | `["infinity"]` |

## 配置示例

### 高可用部署

```yaml
auth:
  postgresPassword: "mysecretpassword"

coordinator:
  podAntiAffinityPreset: hard
  resources:
    requests:
      cpu: 1
      memory: 2Gi
    limits:
      cpu: 4
      memory: 8Gi
  persistence:
    size: 50Gi
  pdb:
    create: true
  # VPA 配置 (与 HPA 互斥，选择其一)
  vpa:
    enabled: false  # 如需启用改为 true
    updateMode: Auto
    minAllowed:
      cpu: 500m
      memory: 1Gi
    maxAllowed:
      cpu: 4
      memory: 8Gi

worker:
  replicaCount: 5
  podAntiAffinityPreset: hard
  resources:
    requests:
      cpu: 2
      memory: 4Gi
    limits:
      cpu: 8
      memory: 16Gi
  persistence:
    size: 100Gi
  pdb:
    create: true
  # HPA 配置 (水平扩展)
  autoscaling:
    enabled: true
    minReplicas: 5
    maxReplicas: 20
    targetCPU: 70
  # VPA 配置 (垂直扩展，与 HPA 可同时使用但需谨慎)
  vpa:
    enabled: false  # 如需启用改为 true
    updateMode: Initial  # 推荐与 HPA 同时使用时设为 Initial
    minAllowed:
      cpu: 1
      memory: 2Gi
    maxAllowed:
      cpu: 8
      memory: 16Gi

networkPolicy:
  enabled: true

metrics:
  enabled: true
  serviceMonitor:
    enabled: true

backup:
  enabled: true
  retentionDays: 14
```

## 常用操作

### 连接集群

```bash
export POSTGRES_PASSWORD=$(kubectl get secret -n citus my-citus-secret -o jsonpath="{.data.postgres-password}" | base64 -d)
kubectl port-forward svc/my-citus-coordinator 5432:5432 -n citus
PGPASSWORD=$POSTGRES_PASSWORD psql -h 127.0.0.1 -U postgres -d citus
```

### 查看集群状态

```bash
kubectl exec -it my-citus-coordinator-0 -n citus -- psql -U postgres -d citus -c "SELECT * FROM citus_get_active_worker_nodes();"
```

### 创建分布式表

```sql
CREATE TABLE events (id bigserial PRIMARY KEY, device_id bigint, data jsonb);
SELECT create_distributed_table('events', 'device_id');
```

### 重新平衡分片

```bash
kubectl exec -it my-citus-coordinator-0 -n citus -- psql -U postgres -d citus -c "SELECT rebalance_table_shards();"
```

## 许可证

本 Chart 采用 Apache 2.0 许可证。Citus 采用 AGPL-3.0 许可证。
