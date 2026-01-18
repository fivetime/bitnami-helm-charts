# Changelog

本文档记录 PowerDNS Recursor Helm Chart 的所有重要变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.4.0] - 2026-01-17

### 新增 - 高级功能完善

**Sortlist 响应排序**
- `config.recursor.sortlists`: 按客户端 IP 对 A/AAAA 记录进行排序
- 支持基于源网络的响应优先级配置

**DoT (DNS over TLS) 到上游**
- `config.outgoing.dotToAuthNames`: 对指定权威服务器强制使用 DoT
- `config.outgoing.dotToForwarders`: 对 853 端口的 forwarder 启用 DoT
- 提供到上游的加密查询支持

**Protobuf 日志导出**
- `config.logging.protobufServers`: Protobuf 日志服务器列表
- `config.logging.outgoingProtobufServers`: 出站查询 Protobuf 服务器
- `config.logging.protobufMaskV4/V6`: IP 掩码配置
- `config.logging.protobufLogQueries/Responses`: 查询/响应日志开关
- `config.logging.protobufAlwaysCache`: 总是缓存 Protobuf 响应
- `config.logging.protobufTaggedOnly`: 仅记录有标签的查询

**DNSTap 日志导出 (RFC 8618)**
- `config.logging.dnstapFramestreamServers`: DNSTap framestream 服务器列表
- `config.logging.dnstapLogQueries/Responses`: 查询/响应日志开关
- `config.logging.dnstapIdentity`: DNSTap 服务器标识

**UDR (Unique Domain Response) 跟踪**
- `config.nod.uniqueResponseTracking`: 启用 UDR 跟踪
- `config.nod.uniqueResponseLog`: 记录 UDR 到日志
- `config.nod.uniqueResponseDbSize`: UDR 数据库大小
- `config.nod.uniqueResponseHistoryDir`: UDR 历史目录
- `config.nod.uniqueResponsePbTag`: UDR Protobuf 标签

**Zone to Cache 预加载**
- `zoneToCache.enabled`: 启用 Zone to Cache
- `zoneToCache.zones`: 要缓存的区域列表
  - 支持 url, file, axfr 三种获取方式
  - 支持 refreshPeriod, retryOnError, maxReceivedBytes, timeout 配置
- 提高热点域名查询性能

### 功能覆盖率

本版本实现了 FEATURE_REVIEW.md 中列出的所有功能：
- ✅ DNS64 (v1.3.0)
- ✅ Proxy Protocol (v1.3.0)
- ✅ Allow Notify (v1.3.0)
- ✅ Extended DNS Errors (v1.3.0)
- ✅ Sortlist (v1.4.0)
- ✅ DoT to Upstream (v1.4.0)
- ✅ Protobuf Logging (v1.4.0)
- ✅ DNSTap (v1.4.0)
- ✅ UDR (v1.4.0)
- ✅ Zone to Cache (v1.4.0)

---

## [1.3.0] - 2026-01-17

### 新增 - 高级 DNS 功能

**DNS64 支持**
- `config.dns64.prefix`: DNS64 IPv6 前缀配置
- 支持纯 IPv6 客户端访问 IPv4 资源

**Proxy Protocol 支持**
- `config.incoming.proxyProtocolFrom`: 接受 Proxy Protocol v2 的来源
- `config.incoming.proxyProtocolExceptions`: Proxy Protocol 例外地址
- 在负载均衡器后保留真实客户端 IP

**Allow Notify 支持**
- `config.incoming.allowNotifyFrom`: 允许发送 NOTIFY 的来源
- `config.incoming.allowNotifyFor`: 允许接收 NOTIFY 的域名
- 支持区域更新通知和缓存清除

**Extended DNS Errors (RFC 8914)**
- `config.recursor.extendedResolutionErrors`: 启用扩展错误响应
- 默认启用，提供更详细的 DNS 错误信息

---

## [1.2.0] - 2026-01-17

### 新增 - Bitnami 命名风格完善

**新增标准参数**
- `automountServiceAccountToken`: 是否自动挂载 ServiceAccount Token
- `hostNetwork`: 是否启用主机网络
- `hostIPC`: 是否启用主机 IPC
- `dnsPolicy`: Pod 的 DNS 策略
- `dnsConfig`: Pod 的 DNS 配置
- `runtimeClassName`: Runtime class 名称
- `revisionHistoryLimit`: 保留的历史版本数量

**安全上下文增强**
- `podSecurityContext.supplementalGroups`: 附加组 ID 列表
- `podSecurityContext.sysctls`: Pod 的 sysctl 设置
- `containerSecurityContext.seLinuxOptions`: SELinux 选项
- `containerSecurityContext.privileged`: 是否启用特权模式

---

## [1.1.0] - 2026-01-17

### 新增

**出站查询配置 (outgoing)**
- `dontQuery`: 不查询的 IP/CIDR 列表，防止查询内部网络
- `sourceAddress`: 出站查询源地址
- `networkTimeout`: 出站查询超时（毫秒）
- `tcpFastOpenConnect`: 出站启用 TCP Fast Open
- `ednsSubnetAllowList`: 允许 ECS 的域名列表
- `ednsSubnetHarden`: 严格 ECS 处理
- `dontThrottleNames/Netmasks`: 不限速的域名和 IP
- `maxQperq`: 每个查询最大子查询数
- `maxNsAddressQperq`: 每个查询最大 NS 地址查询数
- `maxNsPerResolve`: 每次解析最大 NS 数
- `serverDownMaxFails/ThrottleTime`: 服务器 down 检测配置
- `udpSourcePortMin/Max/Avoid`: UDP 源端口配置

**包缓存配置 (packetcache)**
- `disable`: 禁用包缓存
- `maxEntries`: 包缓存最大条目数
- `ttl/negativeTtl/servfailTtl`: TTL 配置
- `shards`: 包缓存分片数

**DNSSEC 扩展配置**
- `aggressiveCacheMinNsec3HitRatio`: NSEC3 记录最小命中率阈值
- `nsec3MaxIterations`: NSEC3 最大迭代次数
- `signatureInceptionSkew`: 签名时间偏移允许
- `disabledAlgorithms`: 禁用的 DNSSEC 算法列表
- `maxDnskeys/maxDsPerZone`: 每区域最大 DNSKEY/DS 数量
- `maxRrsigsPerRecord/maxNsec3sPerRecord`: 每记录最大签名数
- `maxSignatureValidationsPerQuery`: 每查询最大签名验证次数
- `maxNsec3HashComputationsPerQuery`: 每查询最大 NSEC3 哈希计算次数

**NOD (Newly Observed Domain) 跟踪**
- `enabled/tracking`: 启用新观察域跟踪
- `log`: 记录新观察到的域
- `lookup`: 新域名查询后缀
- `dbSize/historyDir`: 数据库配置
- `ignoreList`: 忽略的域名列表
- `pbTag`: Protobuf 标签

**Carbon 监控**
- `enabled`: 启用 Carbon 指标导出
- `server`: Carbon 服务器地址列表
- `interval`: 指标发送间隔
- `ourname/namespace/instance`: 命名配置

**Negative Trust Anchors**
- `trustAnchors.negative`: 负信任锚点列表，用于禁用特定域的 DNSSEC 验证

---

## [1.0.0] - 2026-01-17

### 新增

**架构重构**
- 从 OpenStack-Helm 风格完全重构为 Bitnami 风格
- 使用 bitnami/common chart 替代 helm-toolkit
- 参数命名从 snake_case 改为 camelCase

**核心功能**
- PowerDNS Recursor 5.3.4 支持
- DNSSEC 验证（默认启用）
- Forward Zones 配置（支持递归和非递归模式）
- Trust Anchors 支持私有区域 DNSSEC
- Lua 脚本支持（config.lua 和 dns.lua）
- RPZ (Response Policy Zones) 支持
- ECS (EDNS Client Subnet) 支持
- 缓存配置（条目数、TTL 等）

**高可用性**
- 多副本部署支持
- Pod 反亲和性预设
- 拓扑分布约束
- HPA 自动伸缩
- VPA 垂直伸缩
- PodDisruptionBudget

**安全性**
- 完整的安全上下文配置
- NetworkPolicy 支持
- 非 root 用户运行
- 只读根文件系统
- seccomp profile 支持

**监控**
- Prometheus 指标导出
- ServiceMonitor 支持
- Webserver/API 支持

**网络**
- Service 类型配置（ClusterIP, LoadBalancer, NodePort）
- Ingress 支持 API 访问
- 外部流量策略配置

**运维**
- 诊断模式
- 资源预设
- 额外卷挂载支持
- Sidecar 容器支持
- Init 容器支持

### 从 0.2.x 迁移

旧版本使用 helm-toolkit，新版本使用 bitnami/common。主要配置变更：

| 旧参数 (0.2.x) | 新参数 (1.0.0) |
|---------------|---------------|
| `images.tags.recursor` | `image.tag` |
| `pod.replicas.recursor` | `replicaCount` |
| `pod.security_context` | `podSecurityContext` / `containerSecurityContext` |
| `pod.resources.recursor` | `resources` |
| `conf.incoming.listen` | `config.incoming.listen` |
| `conf.incoming.allow_from` | `config.incoming.allowFrom` |
| `conf.recursor.threads` | `config.recursor.threads` |
| `conf.dnssec.validation` | `config.dnssec.validation` |
| `conf.webservice.webserver` | `webserver.enabled` |
| `network.recursor.service_type` | `service.type` |
| `autoscaling.enabled` | `autoscaling.hpa.enabled` |
| `monitoring.prometheus.enabled` | `metrics.enabled` |

---

## [0.2.0] - 2026-01-16 (旧版本)

### 新增
- YAML 格式配置文件支持
- RPZ 基础支持
- Trust Anchors 配置
- Lua 脚本配置

### 变更
- 更新到 PowerDNS Recursor 5.3.4

## [0.1.0] - 2026-01-15 (旧版本)

### 新增
- 初始版本
- 基于 helm-toolkit
- 基本 DNS 解析功能
- DNSSEC 验证
- Forward Zones

---

## 版本兼容性

| Chart 版本 | PowerDNS 版本 | Kubernetes 版本 | Helm 版本 |
|-----------|--------------|----------------|-----------|
| 1.0.x | 5.3.x | 1.25+ | 3.8+ |
| 0.2.x | 5.3.x | 1.25+ | 3.8+ |
| 0.1.x | 5.0.x | 1.23+ | 3.8+ |
