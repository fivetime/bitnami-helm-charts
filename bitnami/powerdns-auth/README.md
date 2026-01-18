# PowerDNS Authoritative Server

[PowerDNS Authoritative Server](https://www.powerdns.com/) 是一个高性能的权威 DNS 服务器，支持多种数据库后端，可配置为主服务器或从服务器。

## TL;DR

```bash
helm repo add powerdns https://charts.example.com/powerdns
helm install my-pdns-auth powerdns/powerdns-auth \
  --set database.postgresql.host=postgresql.default.svc.cluster.local \
  --set database.postgresql.password=your-password
```

## 简介

此 Chart 使用 [Helm](https://helm.sh) 包管理器在 [Kubernetes](https://kubernetes.io) 集群上部署 PowerDNS Authoritative Server。

## 先决条件

- Kubernetes 1.25+
- Helm 3.8.0+
- 外部 PostgreSQL 或 MySQL 数据库

## 安装 Chart

安装名为 `my-pdns-auth` 的 release：

```bash
helm install my-pdns-auth powerdns/powerdns-auth \
  --set database.postgresql.host=postgresql.default.svc.cluster.local \
  --set database.postgresql.password=your-password
```

该命令使用默认配置部署 PowerDNS Auth。[参数](#参数) 部分列出了安装期间可以配置的参数。

> **提示**: 使用 `helm list` 列出所有 release

## 卸载 Chart

卸载 `my-pdns-auth` release：

```bash
helm uninstall my-pdns-auth
```

该命令删除与 Chart 关联的所有 Kubernetes 组件并删除 release。

## 架构

### 推荐架构：对等多副本 + 共享数据库

```
                    ┌─────────────────┐
                    │  LoadBalancer   │
                    │    或 VIP       │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
        ┌──────────┐   ┌──────────┐   ┌──────────┐
        │ PowerDNS │   │ PowerDNS │   │ PowerDNS │
        │  Pod 1   │   │  Pod 2   │   │  Pod 3   │
        │ (读写)   │   │ (读写)   │   │ (读写)   │
        └────┬─────┘   └────┬─────┘   └────┬─────┘
             │              │              │
             └──────────────┼──────────────┘
                            │
                            ▼
                   ┌─────────────────┐
                   │   PostgreSQL    │
                   │   或 MySQL      │
                   │   (共享数据库)  │
                   └─────────────────┘
```

**特点**:
- 所有 Pod 对等，共享同一数据库
- Kubernetes Service 提供负载均衡
- 水平扩展只需增加 replicas
- 适用于纯 Kubernetes 环境

### 可选架构：Primary/Secondary 区域传输

```
     ┌──────────────────┐              ┌──────────────────┐
     │   Primary 集群   │              │  Secondary 集群  │
     │   (数据库 A)     │              │   (数据库 B)     │
     │                  │   NOTIFY     │                  │
     │  PowerDNS Auth   │─────────────►│  PowerDNS Auth   │
     │  primary=yes     │   AXFR/IXFR  │  secondary=yes   │
     └──────────────────┘              └──────────────────┘
```

**适用场景**:
- 跨数据中心部署
- 混合云环境
- 与外部 DNS 服务器同步

## 参数

### 全局参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `global.imageRegistry` | 全局 Docker 镜像仓库 | `""` |
| `global.imagePullSecrets` | 全局 Docker 仓库密钥 | `[]` |
| `global.defaultStorageClass` | 全局默认 StorageClass | `""` |
| `global.security.allowInsecureImages` | 允许跳过镜像验证 | `false` |
| `global.compatibility.openshift.adaptSecurityContext` | OpenShift 安全上下文适配 | `auto` |

### 通用参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `kubeVersion` | 覆盖 Kubernetes 版本 | `""` |
| `nameOverride` | 部分覆盖 fullname | `""` |
| `fullnameOverride` | 完全覆盖 fullname | `""` |
| `namespaceOverride` | 覆盖命名空间 | `""` |
| `commonLabels` | 添加到所有资源的标签 | `{}` |
| `commonAnnotations` | 添加到所有资源的注解 | `{}` |
| `clusterDomain` | Kubernetes 集群域名 | `cluster.local` |
| `extraDeploy` | 额外部署的资源数组 | `[]` |
| `diagnosticMode.enabled` | 启用诊断模式 | `false` |
| `diagnosticMode.command` | 诊断模式命令 | `["sleep"]` |
| `diagnosticMode.args` | 诊断模式参数 | `["infinity"]` |

### PowerDNS Auth 服务器参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `image.registry` | 镜像仓库 | `docker.io` |
| `image.repository` | 镜像名称 | `powerdns/pdns-auth-50` |
| `image.tag` | 镜像标签 | `5.0.2` |
| `image.digest` | 镜像摘要 (覆盖 tag) | `""` |
| `image.pullPolicy` | 镜像拉取策略 | `IfNotPresent` |
| `image.pullSecrets` | 镜像拉取密钥 | `[]` |
| `replicaCount` | 副本数量 | `2` |
| `livenessProbe.enabled` | 启用存活探针 | `true` |
| `livenessProbe.initialDelaySeconds` | 存活探针初始延迟 | `30` |
| `livenessProbe.periodSeconds` | 存活探针周期 | `20` |
| `livenessProbe.timeoutSeconds` | 存活探针超时 | `5` |
| `livenessProbe.failureThreshold` | 存活探针失败阈值 | `3` |
| `livenessProbe.successThreshold` | 存活探针成功阈值 | `1` |
| `readinessProbe.enabled` | 启用就绪探针 | `true` |
| `readinessProbe.initialDelaySeconds` | 就绪探针初始延迟 | `10` |
| `readinessProbe.periodSeconds` | 就绪探针周期 | `10` |
| `readinessProbe.timeoutSeconds` | 就绪探针超时 | `5` |
| `readinessProbe.failureThreshold` | 就绪探针失败阈值 | `3` |
| `readinessProbe.successThreshold` | 就绪探针成功阈值 | `1` |
| `startupProbe.enabled` | 启用启动探针 | `true` |
| `startupProbe.initialDelaySeconds` | 启动探针初始延迟 | `5` |
| `startupProbe.periodSeconds` | 启动探针周期 | `5` |
| `startupProbe.timeoutSeconds` | 启动探针超时 | `3` |
| `startupProbe.failureThreshold` | 启动探针失败阈值 | `30` |
| `startupProbe.successThreshold` | 启动探针成功阈值 | `1` |
| `customLivenessProbe` | 自定义存活探针 | `{}` |
| `customReadinessProbe` | 自定义就绪探针 | `{}` |
| `customStartupProbe` | 自定义启动探针 | `{}` |
| `resourcesPreset` | 资源预设 | `small` |
| `resources` | 资源限制 | `{}` |
| `podSecurityContext.enabled` | 启用 Pod 安全上下文 | `true` |
| `podSecurityContext.fsGroup` | Pod fsGroup | `953` |
| `podSecurityContext.fsGroupChangePolicy` | fsGroup 变更策略 | `Always` |
| `podSecurityContext.supplementalGroups` | 附加组 | `[]` |
| `podSecurityContext.sysctls` | sysctl 设置 | `[]` |
| `containerSecurityContext.enabled` | 启用容器安全上下文 | `true` |
| `containerSecurityContext.seLinuxOptions` | SELinux 选项 | `{}` |
| `containerSecurityContext.runAsUser` | 容器运行用户 | `953` |
| `containerSecurityContext.runAsGroup` | 容器运行组 | `953` |
| `containerSecurityContext.runAsNonRoot` | 非 root 运行 | `true` |
| `containerSecurityContext.privileged` | 特权模式 | `false` |
| `containerSecurityContext.readOnlyRootFilesystem` | 只读根文件系统 | `true` |
| `containerSecurityContext.allowPrivilegeEscalation` | 允许提权 | `false` |
| `containerSecurityContext.capabilities.drop` | 移除的能力 | `["ALL"]` |
| `containerSecurityContext.seccompProfile.type` | seccomp 类型 | `RuntimeDefault` |
| `automountServiceAccountToken` | 自动挂载 ServiceAccount Token | `false` |
| `hostNetwork` | 启用主机网络 | `false` |
| `hostIPC` | 启用主机 IPC | `false` |
| `dnsPolicy` | DNS 策略 | `""` |
| `dnsConfig` | DNS 配置 | `{}` |
| `command` | 覆盖默认命令 | `[]` |
| `args` | 覆盖默认参数 | `[]` |
| `hostAliases` | Pod host aliases | `[]` |
| `podLabels` | Pod 额外标签 | `{}` |
| `podAnnotations` | Pod 额外注解 | `{}` |
| `podAffinityPreset` | Pod 亲和性预设 | `""` |
| `podAntiAffinityPreset` | Pod 反亲和性预设 | `soft` |
| `nodeAffinityPreset.type` | 节点亲和性类型 | `""` |
| `nodeAffinityPreset.key` | 节点标签键 | `""` |
| `nodeAffinityPreset.values` | 节点标签值 | `[]` |
| `affinity` | 自定义亲和性 | `{}` |
| `nodeSelector` | 节点选择器 | `{}` |
| `tolerations` | 容忍度 | `[]` |
| `revisionHistoryLimit` | 保留的历史版本数 | `10` |
| `updateStrategy.type` | 更新策略类型 | `RollingUpdate` |
| `priorityClassName` | 优先级类名 | `""` |
| `topologySpreadConstraints` | 拓扑分布约束 | `[]` |
| `schedulerName` | 调度器名称 | `""` |
| `runtimeClassName` | Runtime class 名称 | `""` |
| `terminationGracePeriodSeconds` | 终止宽限期 | `30` |
| `lifecycleHooks` | 生命周期钩子 | `{}` |
| `extraEnvVars` | 额外环境变量 | `[]` |
| `extraEnvVarsCM` | 额外环境变量 ConfigMap | `""` |
| `extraEnvVarsSecret` | 额外环境变量 Secret | `""` |
| `extraVolumes` | 额外卷 | `[]` |
| `extraVolumeMounts` | 额外卷挂载 | `[]` |
| `sidecars` | Sidecar 容器 | `[]` |
| `initContainers` | Init 容器 | `[]` |

### PowerDNS 配置参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `config.localAddress` | 监听地址 | `0.0.0.0, ::` |
| `config.localPort` | 监听端口 | `53` |
| `config.loglevel` | 日志级别 (0-9) | `4` |
| `config.logDnsDetails` | 记录 DNS 详情 | `false` |
| `config.logDnsQueries` | 记录 DNS 查询 | `false` |
| `config.queryLogging` | 启用查询日志 | `false` |
| `config.disableAxfr` | 禁用 AXFR 传输 | `true` |
| `config.allowAxfrIps` | 允许 AXFR 的 IP | `127.0.0.0/8,::1` |
| `config.allowNotifyFrom` | 允许 NOTIFY 的 IP | `0.0.0.0/0,::/0` |
| `config.primary` | 作为主服务器运行 | `false` |
| `config.secondary` | 作为从服务器运行 | `false` |
| `config.alsoNotify` | 发送 NOTIFY 的 IP 列表 | `""` |
| `config.onlyNotify` | 仅通知这些 IP | `""` |
| `config.autosecondary` | 自动从 autoprimary 创建区域 | `false` |
| `config.allowUnsignedAutoprimary` | 允许无 TSIG 的 autoprimary | `false` |
| `config.allowUnsignedNotify` | 允许无 TSIG 的 NOTIFY | `false` |
| `config.receiverThreads` | 接收线程数 | `2` |
| `config.retrievalThreads` | 检索线程数 | `2` |
| `config.signingThreads` | 签名线程数 | `3` |
| `config.reuseport` | 启用 SO_REUSEPORT | `true` |
| `config.maxTcpConnectionDuration` | TCP 最大连接时长 | `0` |
| `config.maxTcpConnections` | TCP 最大连接数 | `20` |
| `config.tcpFastOpen` | TCP Fast Open 队列大小 | `64` |
| `config.defaultKskAlgorithm` | 默认 KSK 算法 | `ecdsa256` |
| `config.defaultKskSize` | 默认 KSK 大小 | `0` |
| `config.defaultZskAlgorithm` | 默认 ZSK 算法 | `""` |
| `config.defaultZskSize` | 默认 ZSK 大小 | `0` |
| `config.dnameProcessing` | 启用 DNAME 处理 | `false` |
| `config.expandAlias` | 启用 ALIAS 扩展 | `false` |
| `config.versionString` | 版本字符串 | `anonymous` |
| `config.securityPollSuffix` | 安全轮询后缀 | `""` |
| `config.cacheTtl` | 缓存 TTL (秒) | `20` |
| `config.negqueryCacheTtl` | 负查询缓存 TTL | `60` |
| `config.queryCacheEnabled` | 启用查询缓存 | `true` |
| `config.defaultSoaContent` | 默认 SOA 内容 | `""` |
| `config.defaultSoaMail` | 默认 SOA 邮箱 | `""` |
| `config.defaultSoaName` | 默认 SOA 名称 | `""` |
| `config.defaultTtl` | 默认 TTL | `3600` |
| `config.allowDnsupdateFrom` | 允许 DNS UPDATE 的 IP | `""` |
| `config.dnsupdateRequireTsig` | DNS UPDATE 需要 TSIG | `true` |
| `config.forwardDnsupdate` | 转发 DNS UPDATE | `false` |
| `config.enableLuaRecords` | 启用 LUA 记录 | `false` |
| `config.extra` | 额外配置键值对 | `{}` |

### 数据库配置参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `database.type` | 数据库类型 | `postgresql` |
| `database.connection.maxRetries` | 最大重试次数 | `15` |
| `database.connection.retryInterval` | 重试间隔 (秒) | `5` |
| `database.existingSecret.enabled` | 使用已有 Secret | `false` |
| `database.existingSecret.name` | Secret 名称 | `""` |
| `database.existingSecret.adminPasswordKey` | 管理员密码键 | `admin-password` |
| `database.existingSecret.userPasswordKey` | 用户密码键 | `user-password` |
| `database.postgresql.host` | PostgreSQL 主机 | `""` |
| `database.postgresql.port` | PostgreSQL 端口 | `5432` |
| `database.postgresql.database` | 数据库名 | `pdns` |
| `database.postgresql.username` | 用户名 | `pdns` |
| `database.postgresql.password` | 密码 | `pdns` |
| `database.postgresql.adminUsername` | 管理员用户名 | `postgres` |
| `database.postgresql.adminPassword` | 管理员密码 | `""` |
| `database.mysql.host` | MySQL 主机 | `""` |
| `database.mysql.port` | MySQL 端口 | `3306` |
| `database.mysql.database` | 数据库名 | `pdns` |
| `database.mysql.username` | 用户名 | `pdns` |
| `database.mysql.password` | 密码 | `pdns` |
| `database.mysql.timeout` | 连接超时 | `10` |
| `database.mysql.adminUsername` | 管理员用户名 | `root` |
| `database.mysql.adminPassword` | 管理员密码 | `""` |

### API / Webserver 配置参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `webserver.enabled` | 启用 Webserver/API | `true` |
| `webserver.address` | 监听地址 | `0.0.0.0` |
| `webserver.port` | 监听端口 | `8081` |
| `webserver.allowFrom` | 允许访问的 IP | `0.0.0.0/0,::/0` |
| `webserver.password` | Webserver 密码 | `""` |
| `webserver.apiKey` | API 密钥 | `""` |

### GeoIP 后端配置参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `geoip.enabled` | 启用 GeoIP 后端 | `false` |
| `geoip.databases` | GeoIP 数据库路径列表 | `[/usr/share/GeoIP/GeoLite2-City.mmdb, ...]` |
| `geoip.zonesFile` | GeoIP zones 文件路径 | `/etc/pdns/geo-zones.yaml` |
| `geoip.ednsSubnetProcessing` | 启用 EDNS 子网处理 | `true` |
| `geoip.dnssecKeydir` | DNSSEC 密钥目录 | `""` |
| `geoipZones.enabled` | 启用 GeoIP zones ConfigMap | `false` |
| `geoipZones.domains` | GeoIP 域配置列表 | `[]` |
| `geoipVolume.enabled` | 启用 GeoIP 卷 | `false` |
| `geoipVolume.type` | 卷类型 (pvc/configMap/hostPath) | `pvc` |
| `geoipVolume.pvc.claimName` | PVC 名称 | `geoip-data` |
| `geoipVolume.pvc.readOnly` | 只读挂载 | `true` |
| `geoipVolume.configMap.name` | ConfigMap 名称 | `geoip-data` |
| `geoipVolume.hostPath.path` | 主机路径 | `/var/lib/GeoIP` |

### TSIG 密钥配置参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `tsig.enabled` | 启用 TSIG 密钥配置 | `false` |
| `tsig.keys` | TSIG 密钥列表 | `[]` |
| `tsig.existingSecret.enabled` | 使用已有 Secret | `false` |
| `tsig.existingSecret.name` | Secret 名称 | `""` |

### 流量暴露参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `service.type` | Service 类型 | `ClusterIP` |
| `service.ports.dns` | DNS UDP 端口 | `53` |
| `service.ports.dnsTcp` | DNS TCP 端口 | `53` |
| `service.ports.api` | API 端口 | `8081` |
| `service.nodePorts.dns` | DNS UDP NodePort | `""` |
| `service.nodePorts.dnsTcp` | DNS TCP NodePort | `""` |
| `service.nodePorts.api` | API NodePort | `""` |
| `service.clusterIP` | Service ClusterIP | `""` |
| `service.loadBalancerIP` | LoadBalancer IP | `""` |
| `service.loadBalancerSourceRanges` | LoadBalancer 源范围 | `[]` |
| `service.externalTrafficPolicy` | 外部流量策略 | `Local` |
| `service.annotations` | Service 注解 | `{}` |
| `service.extraPorts` | 额外端口 | `[]` |
| `service.sessionAffinity` | 会话亲和性 | `None` |
| `service.sessionAffinityConfig` | 会话亲和性配置 | `{}` |
| `ingress.enabled` | 启用 Ingress | `false` |
| `ingress.pathType` | Ingress 路径类型 | `Prefix` |
| `ingress.hostname` | Ingress 主机名 | `pdns-api.local` |
| `ingress.ingressClassName` | Ingress 类名 | `""` |
| `ingress.path` | Ingress 路径 | `/api` |
| `ingress.annotations` | Ingress 注解 | `{}` |
| `ingress.tls` | 启用 TLS | `false` |
| `ingress.selfSigned` | 自签名证书 | `false` |
| `ingress.extraHosts` | 额外主机 | `[]` |
| `ingress.extraPaths` | 额外路径 | `[]` |
| `ingress.extraTls` | 额外 TLS 配置 | `[]` |
| `ingress.secrets` | TLS 证书 Secrets | `[]` |
| `ingress.extraRules` | 额外规则 | `[]` |

### 持久化参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `persistence.enabled` | 启用持久化 | `false` |
| `persistence.mountPath` | 挂载路径 | `/var/lib/powerdns` |
| `persistence.storageClass` | StorageClass | `""` |
| `persistence.annotations` | PVC 注解 | `{}` |
| `persistence.accessModes` | 访问模式 | `[ReadWriteOnce]` |
| `persistence.size` | 卷大小 | `1Gi` |
| `persistence.existingClaim` | 已有 PVC 名称 | `""` |
| `persistence.selector` | PV 选择器 | `{}` |

### 数据库初始化/同步 Job 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `dbInit.enabled` | 启用 db-init Job | `true` |
| `dbInit.mysql.image.registry` | MySQL 镜像仓库 | `docker.io` |
| `dbInit.mysql.image.repository` | MySQL 镜像名称 | `library/mysql` |
| `dbInit.mysql.image.tag` | MySQL 镜像标签 | `8.0` |
| `dbInit.postgresql.image.registry` | PostgreSQL 镜像仓库 | `docker.io` |
| `dbInit.postgresql.image.repository` | PostgreSQL 镜像名称 | `library/postgres` |
| `dbInit.postgresql.image.tag` | PostgreSQL 镜像标签 | `16-alpine` |
| `dbInit.resourcesPreset` | 资源预设 | `micro` |
| `dbInit.resources` | 资源限制 | `{}` |
| `dbSync.enabled` | 启用 db-sync Job | `true` |
| `dbSync.resourcesPreset` | 资源预设 | `micro` |
| `dbSync.resources` | 资源限制 | `{}` |

### RBAC 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `serviceAccount.create` | 创建 ServiceAccount | `true` |
| `serviceAccount.name` | ServiceAccount 名称 | `""` |
| `serviceAccount.annotations` | ServiceAccount 注解 | `{}` |
| `serviceAccount.automountServiceAccountToken` | 自动挂载 token | `false` |

### 网络策略参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `networkPolicy.enabled` | 启用 NetworkPolicy | `true` |
| `networkPolicy.allowExternal` | 允许外部连接 | `true` |
| `networkPolicy.allowExternalEgress` | 允许外部出口 | `true` |
| `networkPolicy.extraIngress` | 额外入口规则 | `[]` |
| `networkPolicy.extraEgress` | 额外出口规则 | `[]` |
| `networkPolicy.ingressNSMatchLabels` | 入口命名空间标签 | `{}` |
| `networkPolicy.ingressNSPodMatchLabels` | 入口 Pod 标签 | `{}` |

### Pod 中断预算参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `pdb.create` | 创建 PDB | `true` |
| `pdb.minAvailable` | 最小可用 Pod 数 | `1` |
| `pdb.maxUnavailable` | 最大不可用 Pod 数 | `""` |

### 自动伸缩参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `autoscaling.vpa.enabled` | 启用 VPA | `false` |
| `autoscaling.vpa.annotations` | VPA 注解 | `{}` |
| `autoscaling.vpa.controlledResources` | VPA 控制的资源 | `[]` |
| `autoscaling.vpa.maxAllowed` | VPA 最大资源 | `{}` |
| `autoscaling.vpa.minAllowed` | VPA 最小资源 | `{}` |
| `autoscaling.vpa.updatePolicy.updateMode` | VPA 更新模式 | `Auto` |
| `autoscaling.hpa.enabled` | 启用 HPA | `false` |
| `autoscaling.hpa.minReplicas` | 最小副本数 | `2` |
| `autoscaling.hpa.maxReplicas` | 最大副本数 | `5` |
| `autoscaling.hpa.targetCPU` | 目标 CPU 使用率 | `75` |
| `autoscaling.hpa.targetMemory` | 目标内存使用率 | `""` |

### 监控指标参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `metrics.enabled` | 启用指标端点 | `false` |
| `metrics.serviceMonitor.enabled` | 创建 ServiceMonitor | `false` |
| `metrics.serviceMonitor.namespace` | ServiceMonitor 命名空间 | `""` |
| `metrics.serviceMonitor.interval` | 采集间隔 | `30s` |
| `metrics.serviceMonitor.scrapeTimeout` | 采集超时 | `10s` |
| `metrics.serviceMonitor.relabelings` | relabel 配置 | `[]` |
| `metrics.serviceMonitor.metricRelabelings` | metric relabel 配置 | `[]` |
| `metrics.serviceMonitor.selector` | Prometheus 选择器 | `{}` |
| `metrics.serviceMonitor.labels` | 额外标签 | `{}` |
| `metrics.serviceMonitor.honorLabels` | 保留原始标签 | `false` |
| `metrics.serviceMonitor.jobLabel` | Job 标签 | `""` |

## 配置示例

### 基本部署 (PostgreSQL)

```yaml
database:
  type: postgresql
  postgresql:
    host: postgresql.database.svc.cluster.local
    port: 5432
    database: pdns
    username: pdns
    password: "your-secure-password"
    adminUsername: postgres
    adminPassword: "admin-password"

webserver:
  enabled: true
  apiKey: "your-api-key"
```

### 高可用部署

```yaml
replicaCount: 3

podAntiAffinityPreset: hard

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: powerdns-auth

pdb:
  create: true
  minAvailable: 2

autoscaling:
  hpa:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPU: 70
```

### Primary 配置 (区域传输)

```yaml
config:
  primary: true
  disableAxfr: false
  allowAxfrIps: "192.168.1.0/24,10.0.0.0/8"
  alsoNotify: "192.168.2.10:53,192.168.2.11:53"

tsig:
  enabled: true
  keys:
    - name: transfer-key
      algorithm: hmac-sha256
      secret: "your-base64-encoded-secret"
```

### Secondary 配置

```yaml
config:
  secondary: true
  autosecondary: true

tsig:
  enabled: true
  keys:
    - name: transfer-key
      algorithm: hmac-sha256
      secret: "your-base64-encoded-secret"
```

### GeoIP 配置

```yaml
geoip:
  enabled: true
  databases:
    - /usr/share/GeoIP/GeoLite2-City.mmdb
    - /usr/share/GeoIP/GeoLite2-Country.mmdb
  ednsSubnetProcessing: true

geoipVolume:
  enabled: true
  type: pvc
  pvc:
    claimName: geoip-data

geoipZones:
  enabled: true
  domains:
    - domain: geo.example.com
      ttl: 300
      records:
        geo.example.com:
          - soa: "ns1.example.com hostmaster.example.com 2024010101 7200 3600 1209600 3600"
          - ns: ns1.example.com
        us.cdn.example.com:
          - a: 192.0.2.1
        eu.cdn.example.com:
          - a: 198.51.100.1
      services:
        www.example.com: "%co.cdn.example.com"
```

### 使用外部 Secret

```yaml
database:
  type: postgresql
  existingSecret:
    enabled: true
    name: pdns-db-credentials
    adminPasswordKey: postgres-password
    userPasswordKey: pdns-password
  postgresql:
    host: postgresql.database.svc.cluster.local
    database: pdns
    username: pdns
```

### 启用监控

```yaml
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    labels:
      release: prometheus
    interval: 30s
```

## 故障排除

### 查看 Pod 日志

```bash
kubectl logs -l app.kubernetes.io/name=powerdns-auth -f
```

### 检查数据库连接

```bash
kubectl exec -it deploy/my-pdns-auth -- pdnsutil list-zone example.com
```

### 测试 DNS 查询

```bash
kubectl run -it --rm dns-test --image=busybox --restart=Never -- \
  nslookup example.com my-pdns-auth.default.svc.cluster.local
```

### 查看 API 状态

```bash
kubectl port-forward svc/my-pdns-auth 8081:8081
curl -H "X-API-Key: your-api-key" http://localhost:8081/api/v1/servers/localhost
```

## 升级

### 从 1.1.x 升级到 1.2.x

1.2.0 版本新增了以下功能：
- DNS UPDATE (RFC 2136) 支持
- HPA/VPA 自动伸缩
- TSIG 声明式配置
- 增强的安全上下文

升级命令：

```bash
helm upgrade my-pdns-auth powerdns/powerdns-auth -f values.yaml
```

## 许可证

Copyright &copy; 2024 Simon Li

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
