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

## 高性能 GeoDNS 配置

支持百万级域名的动态 GeoDNS 场景，使用 LUA Records + 数据库后端实现。

### 架构说明

```
                         ┌──────────────────────────────────────┐
                         │            Kubernetes Cluster        │
                         │                                      │
    DNS Query            │   ┌──────────┐    ┌──────────┐       │
    (with ECS)           │   │ PowerDNS │    │ PowerDNS │       │
         │               │   │  Pod 1   │    │  Pod 2   │  ...  │
         ▼               │   │          │    │          │       │
    ┌─────────┐          │   │ ┌──────┐ │    │ ┌──────┐ │       │
    │ Service │──────────┼───┼►│ LUA  │ │    │ │ LUA  │ │       │
    │  (UDP)  │          │   │ │Record│ │    │ │Record│ │       │
    └─────────┘          │   │ └──┬───┘ │    │ └──┬───┘ │       │
                         │   │    │     │    │    │     │       │
                         │   │ ┌──▼───┐ │    │ ┌──▼───┐ │       │
                         │   │ │GeoIP │ │    │ │GeoIP │ │       │
                         │   │ │ mmdb │ │    │ │ mmdb │ │       │
                         │   │ └──────┘ │    │ └──────┘ │       │
                         │   └────┬─────┘    └────┬─────┘       │
                         │        │               │             │
                         │        └───────┬───────┘             │
                         │                │                     │
                         │                ▼                     │
                         │   ┌────────────────────────┐         │
                         │   │    PostgreSQL / MySQL   │         │
                         │   │  (LUA Records 存储)    │         │
                         │   │  millions of records   │         │
                         │   └────────────────────────┘         │
                         └──────────────────────────────────────┘
```

### 工作流程

1. **DNS 查询到达** - 客户端通过递归解析器查询，带有 EDNS Client Subnet
2. **LUA Record 执行** - PowerDNS 从数据库读取 LUA 记录并执行
3. **GeoIP 查询** - LUA 脚本调用 `country()`, `continent()` 等函数查询 GeoIP 数据库
4. **返回结果** - 根据客户端地理位置返回对应的 IP 地址

### 示例配置

```yaml
# values-geodns.yaml - 高性能 GeoDNS 配置
replicaCount: 3

config:
  # 性能调优
  performance:
    receiverThreads: 8        # 建议 = CPU 核心数
    distributorThreads: 2
    signingThreads: 4
    reuseport: true           # 必须启用
    udpTruncationThreshold: 1232
  
  # 缓存配置
  cache:
    ttl: 30                   # 响应缓存 30 秒
    negTtl: 60
    queryEnabled: true
    queryTtl: 20
  
  # LUA Records 配置
  luaRecords:
    enabled: true
    geoipDatabaseFiles:
      - /usr/share/GeoIP/GeoLite2-City.mmdb
      - /usr/share/GeoIP/GeoLite2-Country.mmdb
      - /usr/share/GeoIP/GeoLite2-ASN.mmdb
    ednsSubnetProcessing: true   # 必须启用
    execLimit: 5000
    healthChecks:
      enabled: true
      interval: 5
      expireDelay: 3600

# 挂载 GeoIP 数据库
geoipVolume:
  enabled: true
  type: pvc
  pvc:
    claimName: geoip-data
    readOnly: true

# 数据库配置
database:
  type: postgresql
  postgresql:
    host: postgresql.database.svc.cluster.local
    port: 5432
    database: pdns
    username: pdns
    password: "your-password"

# 资源配置
resources:
  requests:
    cpu: "2"
    memory: "2Gi"
  limits:
    cpu: "4"
    memory: "4Gi"

# 启用 HPA
autoscaling:
  hpa:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPU: 70

# Service 配置 (Cilium BGP LoadBalancer 示例)
service:
  type: LoadBalancer
  labels:
    io.cilium/bgp: "private"           # Cilium BGP 选择器
  annotations:
    lbipam.cilium.io/ips: "10.224.18.17"  # 指定 LoadBalancer IP
  externalTrafficPolicy: Local
```

### LUA Record 示例

通过 PowerDNS API 或 PowerDNS-Admin 创建 LUA 记录：

```bash
# 按国家返回不同 IP
curl -X POST http://pdns-api:8081/api/v1/servers/localhost/zones/example.com./records \
  -H "X-API-Key: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "rrsets": [{
      "name": "www.example.com.",
      "type": "LUA",
      "ttl": 300,
      "records": [{
        "content": "A \"country({JP='\''103.1.1.1'\'', CN='\''116.2.2.2'\'', US='\''198.3.3.3'\'', default='\''103.1.1.1'\''})\"",
        "disabled": false
      }]
    }]
  }'
```

### 常用 LUA 函数

| 函数 | 用途 | 示例 |
|------|------|------|
| `country({...})` | 按国家代码返回 | `country({JP='1.1.1.1', default='2.2.2.2'})` |
| `continent({...})` | 按大洲返回 | `continent({AS='1.1.1.1', EU='2.2.2.2'})` |
| `region({...})` | 按地区/省份返回 | `region({13='1.1.1.1'})` (东京=13) |
| `pickclosest({...})` | 返回地理最近节点 | `pickclosest({'1.1.1.1','2.2.2.2'})` |
| `pickwhashed(...)` | 加权哈希选择 | `pickwhashed(0.7,'1.1.1.1',0.3,'2.2.2.2')` |
| `ifportup(port,{...})` | 端口健康检查 | `ifportup(443,{'1.1.1.1','2.2.2.2'})` |
| `ifurlup(url,{...})` | URL 健康检查 | `ifurlup('https://health.check',{'1.1.1.1'})` |

### 性能优化建议

1. **启用 EDNS Client Subnet** - 必须开启，否则无法获取真实客户端 IP
2. **配置健康检查缓存** - 避免每次查询都触发后端检查
3. **合理设置缓存 TTL** - 在响应速度和数据新鲜度之间平衡
4. **使用 reuseport** - 多副本场景下的关键配置
5. **预热 GeoIP 数据库** - 首次查询会加载 mmdb 文件到内存

### GeoIP 数据库配置

GeoIP 数据库由独立的 `geoip-database` Chart 管理，PowerDNS Auth 只作为消费端挂载 PVC。

**配置方式**:

```yaml
# 1. 先部署 geoip-database chart
helm install geoip-database fivetime/geoip-database -n kube-infra

# 2. 在 powerdns-auth values.yaml 中挂载 PVC
geoipVolume:
  enabled: true
  existingClaim: geoip-database-data  # geoip-database chart 创建的 PVC
```

**滚动更新**: 如需在数据库更新后自动重启 Pod，请监听 `geoip-database-hash` ConfigMap 的变化。

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
| `config.defaultSoaContent` | 默认 SOA 内容 | `""` |
| `config.defaultSoaMail` | 默认 SOA 邮箱 | `""` |
| `config.defaultSoaName` | 默认 SOA 名称 | `""` |
| `config.defaultTtl` | 默认 TTL | `3600` |
| `config.allowDnsupdateFrom` | 允许 DNS UPDATE 的 IP | `""` |
| `config.dnsupdateRequireTsig` | DNS UPDATE 需要 TSIG | `true` |
| `config.forwardDnsupdate` | 转发 DNS UPDATE | `false` |
| `config.extra` | 额外配置键值对 | `{}` |

#### 性能配置参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `config.performance.receiverThreads` | 接收线程数（建议等于 CPU 核心数） | `4` |
| `config.performance.distributorThreads` | 分发线程数 | `1` |
| `config.performance.signingThreads` | DNSSEC 签名线程数 | `3` |
| `config.performance.reuseport` | 启用 SO_REUSEPORT（多副本必须启用） | `true` |
| `config.performance.udpTruncationThreshold` | UDP 截断阈值 | `1232` |

#### 缓存配置参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `config.cache.ttl` | 包缓存 TTL（秒） | `20` |
| `config.cache.negTtl` | 负查询缓存 TTL（秒） | `60` |
| `config.cache.queryEnabled` | 启用查询缓存 | `true` |
| `config.cache.queryTtl` | 查询缓存 TTL（秒） | `20` |

#### LUA Records 配置参数（动态 GeoDNS）

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `config.luaRecords.enabled` | 启用 LUA 记录 | `false` |
| `config.luaRecords.geoipDatabaseFiles` | GeoIP 数据库路径列表 | `[GeoLite2-City.mmdb, GeoLite2-Country.mmdb, GeoLite2-ASN.mmdb]` |
| `config.luaRecords.ednsSubnetProcessing` | 启用 EDNS 子网处理（获取真实客户端 IP） | `true` |
| `config.luaRecords.execLimit` | Lua 脚本执行指令限制 | `5000` |
| `config.luaRecords.healthChecks.enabled` | 启用健康检查功能 | `true` |
| `config.luaRecords.healthChecks.interval` | 健康检查间隔（秒） | `5` |
| `config.luaRecords.healthChecks.expireDelay` | 健康检查结果缓存时间（秒） | `3600` |
| `config.luaRecords.luaAxfrScript` | AXFR 预处理 Lua 脚本路径 | `""` |

### 数据库配置参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `database.type` | 数据库类型 | `postgresql` |
| `database.connection.maxRetries` | 最大重试次数 | `15` |
| `database.connection.retryInterval` | 重试间隔 (秒) | `5` |
| `database.existingSecret.enabled` | 使用已有 Secret (仅管理员凭据) | `false` |
| `database.existingSecret.name` | Secret 名称 | `""` |
| `database.existingSecret.adminUserKey` | 管理员用户名键 | `user` |
| `database.existingSecret.adminPasswordKey` | 管理员密码键 | `password` |
| `database.postgresql.host` | PostgreSQL 主机 | `""` |
| `database.postgresql.port` | PostgreSQL 端口 | `5432` |
| `database.postgresql.database` | 数据库名 | `pdns` |
| `database.postgresql.username` | 应用用户名 | `pdns` |
| `database.postgresql.password` | 应用用户密码 | `pdns` |
| `database.postgresql.adminUsername` | 管理员用户名 (existingSecret 禁用时) | `postgres` |
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
| `geoip.enabled` | 启用 GeoIP 后端（静态配置模式） | `false` |
| `geoip.databases` | GeoIP 数据库路径列表 | `[/usr/share/GeoIP/GeoLite2-City.mmdb, ...]` |
| `geoip.zonesFile` | GeoIP zones 文件路径 | `/etc/pdns/geo-zones.yaml` |
| `geoip.ednsSubnetProcessing` | 启用 EDNS 子网处理 | `true` |
| `geoip.dnssecKeydir` | DNSSEC 密钥目录 | `""` |
| `geoipZones.enabled` | 启用 GeoIP zones ConfigMap | `false` |
| `geoipZones.domains` | GeoIP 域配置列表 | `[]` |
| `geoipVolume.enabled` | 启用 GeoIP 卷挂载 | `false` |
| `geoipVolume.existingClaim` | 已有 PVC 名称（如 geoip-database-data） | `""` |
| `geoipVolume.mountPath` | 挂载路径 | `/usr/share/GeoIP` |

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
| `service.labels` | Service 自定义标签 (如 Cilium BGP) | `{}` |
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

### LUA Records GeoDNS 配置（推荐用于大规模动态 GeoDNS）

LUA Records 模式将 GeoDNS 记录存储在数据库中，支持通过 API/PowerDNS-Admin 动态管理，适合百万级域名场景。

```yaml
# 启用 LUA Records GeoDNS
config:
  # 性能配置
  performance:
    receiverThreads: 8          # 建议等于 CPU 核心数
    distributorThreads: 2
    signingThreads: 4
    reuseport: true             # 多副本必须启用
  
  # 缓存配置
  cache:
    ttl: 30
    negTtl: 60
    queryEnabled: true
    queryTtl: 20
  
  # LUA Records 配置
  luaRecords:
    enabled: true
    geoipDatabaseFiles:
      - /usr/share/GeoIP/GeoLite2-City.mmdb
      - /usr/share/GeoIP/GeoLite2-Country.mmdb
      - /usr/share/GeoIP/GeoLite2-ASN.mmdb
    ednsSubnetProcessing: true  # 获取递归解析器后的真实客户端 IP
    execLimit: 5000             # Lua 指令限制，复杂脚本可增加到 10000
    healthChecks:
      enabled: true
      interval: 5               # 健康检查间隔，影响故障切换速度
      expireDelay: 3600         # 检查结果缓存，防止高 QPS 时打爆后端
    # NOTE: timeout/maxConcurrent 是 LUA 函数参数，不是全局配置
    # 示例: ifportup(443, {'192.0.2.1'}, {timeout=2000})

# 必须挂载 GeoIP 数据库（使用 geoip-database chart）
geoipVolume:
  enabled: true
  existingClaim: geoip-database-data  # 来自 geoip-database chart

# 不需要启用 GeoIP Backend（两者独立）
geoip:
  enabled: false
```

配置完成后，通过 API 或 PowerDNS-Admin 创建 LUA 类型记录：

```sql
-- 按大洲返回不同 IP
INSERT INTO records (domain_id, name, type, content, ttl)
VALUES (1, 'www.example.com', 'LUA', 
        'A "continent({AS=''103.1.1.1'', EU=''185.2.2.2'', NA=''198.3.3.3'', default=''103.1.1.1''})"', 
        300);

-- 按国家返回
INSERT INTO records (domain_id, name, type, content, ttl)
VALUES (1, 'cdn.example.com', 'LUA', 
        'A "country({JP=''103.1.1.1'', CN=''116.2.2.2'', US=''198.3.3.3'', default=''103.1.1.1''})"', 
        300);

-- 选择最近节点
INSERT INTO records (domain_id, name, type, content, ttl)
VALUES (1, 'edge.example.com', 'LUA', 
        'A "pickclosest({''103.1.1.1'', ''185.2.2.2'', ''198.3.3.3''})"', 
        300);

-- 带健康检查的 GeoDNS
INSERT INTO records (domain_id, name, type, content, ttl)
VALUES (1, 'ha.example.com', 'LUA', 
        'A "ifportup(443, {continent({AS=''103.1.1.1'', EU=''185.2.2.2'', default=''103.1.1.1''})})"', 
        300);
```

### 使用外部 Secret

```yaml
database:
  type: postgresql
  existingSecret:
    enabled: true
    name: my-postgres-admin-secret
    adminUserKey: username
    adminPasswordKey: password
  postgresql:
    host: postgresql.database.svc.cluster.local
    database: pdns
    username: pdns
    password: my-pdns-password  # 应用用户密码
```

### 使用 Percona PostgreSQL Operator (直连 Primary，推荐)

```yaml
database:
  type: postgresql
  existingSecret:
    enabled: true
    name: percona-postgresql-pg-pguser-postgres
    adminUserKey: user
    adminPasswordKey: password
  postgresql:
    host: percona-postgresql-pg-primary.kube-infra.svc.cluster.local  # 直连 Primary
    port: 5432
    database: pdns
    username: pdns
    password: my-pdns-password
```

### 使用 Percona PostgreSQL Operator (通过 PgBouncer 连接池)

> **注意**: PowerDNS 5.0+ 默认启用预编译语句且不可配置。如需使用 PgBouncer，请将其配置为 `session` 模式以支持预编译语句。

```yaml
database:
  type: postgresql
  existingSecret:
    enabled: true
    name: percona-postgresql-pg-pguser-postgres
    adminUserKey: user
    adminPasswordKey: password
  postgresql:
    host: percona-postgresql-pg-pgbouncer.kube-infra.svc.cluster.local  # 通过 PgBouncer (需 session 模式)
    port: 5432
    database: pdns
    username: pdns
    password: my-pdns-password
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
