# PowerDNS Recursor

[PowerDNS Recursor](https://doc.powerdns.com/recursor/) 是一个高性能递归 DNS 解析器，支持 DNSSEC 验证、RPZ（Response Policy Zones）、Lua 脚本、ECS（EDNS Client Subnet）和信任锚点管理。

## TL;DR

```bash
helm install pdns-recursor ./powerdns-recursor -n dns --create-namespace
```

## 简介

本 Chart 使用 [Helm](https://helm.sh) 包管理器在 [Kubernetes](https://kubernetes.io) 集群上引导 PowerDNS Recursor 部署。

本 Chart 采用 Bitnami 风格设计，依赖 bitnami/common chart 提供通用模板函数。

## 先决条件

- Kubernetes 1.25+
- Helm 3.8.0+

## 架构

### 高可用递归解析器

```
                    ┌─────────────────────────────────────┐
                    │         Kubernetes Cluster          │
                    │                                     │
   DNS Query        │    ┌──────────────────────────┐    │
   ──────────────────────►│       LoadBalancer       │    │
                    │    │      (Service)           │    │
                    │    └───────────┬──────────────┘    │
                    │                │                   │
                    │    ┌───────────▼──────────────┐    │
                    │    │     Pod Anti-Affinity    │    │
                    │    └───────────┬──────────────┘    │
                    │                │                   │
                    │    ┌───────────┼───────────┐       │
                    │    │           │           │       │
                    │    ▼           ▼           ▼       │
                    │ ┌─────┐   ┌─────┐   ┌─────┐       │
                    │ │ Pod │   │ Pod │   │ Pod │       │
                    │ │  1  │   │  2  │   │  3  │       │
                    │ └──┬──┘   └──┬──┘   └──┬──┘       │
                    │    │         │         │          │
                    │    └─────────┼─────────┘          │
                    │              │                    │
                    │              ▼                    │
                    │    ┌──────────────────┐           │
                    │    │  Root Servers /  │           │
                    │    │  Upstream DNS    │           │
                    │    └──────────────────┘           │
                    └─────────────────────────────────────┘
```

### 与 PowerDNS Auth 集成

```
                              ┌─────────────────┐
                              │   External      │
                              │   Clients       │
                              └────────┬────────┘
                                       │
                    ┌──────────────────▼──────────────────┐
                    │           Kubernetes                │
                    │                                     │
                    │  ┌─────────────────────────────┐    │
                    │  │     PowerDNS Recursor       │    │
                    │  │  (Recursive DNS Resolver)   │    │
                    │  └─────────────┬───────────────┘    │
                    │                │                    │
                    │    ┌───────────┴───────────┐        │
                    │    │                       │        │
                    │    ▼                       ▼        │
                    │ ┌─────────────┐    ┌────────────┐   │
                    │ │  Internal   │    │  External  │   │
                    │ │  Zones      │    │  DNS       │   │
                    │ │             │    │            │   │
                    │ │ PowerDNS    │    │ Root       │   │
                    │ │ Auth Server │    │ Servers    │   │
                    │ └─────────────┘    └────────────┘   │
                    │                                     │
                    └─────────────────────────────────────┘
```

## 安装 Chart

```bash
helm install pdns-recursor ./powerdns-recursor \
  --namespace dns \
  --create-namespace
```

这将使用默认配置部署 PowerDNS Recursor。

> **提示**: 使用 `helm list` 列出所有发布版本

## 卸载 Chart

```bash
helm uninstall pdns-recursor -n dns
```

## 参数

### 全局参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `global.imageRegistry` | 全局 Docker 镜像仓库 | `""` |
| `global.imagePullSecrets` | 全局镜像拉取 Secrets | `[]` |
| `global.storageClass` | 全局存储类 | `""` |

### 通用参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `kubeVersion` | 覆盖 Kubernetes 版本 | `""` |
| `nameOverride` | 部分覆盖名称 | `""` |
| `fullnameOverride` | 完全覆盖名称 | `""` |
| `namespaceOverride` | 覆盖命名空间 | `""` |
| `commonLabels` | 所有资源的标签 | `{}` |
| `commonAnnotations` | 所有资源的注解 | `{}` |
| `clusterDomain` | 集群域名 | `cluster.local` |
| `extraDeploy` | 额外部署对象 | `[]` |

### 镜像参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `image.registry` | 镜像仓库 | `docker.io` |
| `image.repository` | 镜像名称 | `powerdns/pdns-recursor-53` |
| `image.tag` | 镜像标签 | `5.3.4` |
| `image.digest` | 镜像摘要 | `""` |
| `image.pullPolicy` | 拉取策略 | `IfNotPresent` |
| `image.pullSecrets` | 拉取 Secrets | `[]` |

### 部署参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `replicaCount` | 副本数量 | `2` |
| `updateStrategy.type` | 更新策略 | `RollingUpdate` |
| `podAffinityPreset` | Pod 亲和性预设 | `""` |
| `podAntiAffinityPreset` | Pod 反亲和性预设 | `soft` |
| `nodeSelector` | 节点选择器 | `{}` |
| `tolerations` | 容忍设置 | `[]` |
| `topologySpreadConstraints` | 拓扑分布约束 | `[]` |
| `priorityClassName` | 优先级类名 | `""` |
| `terminationGracePeriodSeconds` | 终止宽限期 | `30` |

### 安全上下文参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `podSecurityContext.enabled` | 启用 Pod 安全上下文 | `true` |
| `podSecurityContext.fsGroup` | Pod fsGroup | `953` |
| `containerSecurityContext.enabled` | 启用容器安全上下文 | `true` |
| `containerSecurityContext.runAsUser` | 运行用户 ID | `953` |
| `containerSecurityContext.runAsGroup` | 运行组 ID | `953` |
| `containerSecurityContext.runAsNonRoot` | 非 root 运行 | `true` |
| `containerSecurityContext.readOnlyRootFilesystem` | 只读根文件系统 | `true` |
| `containerSecurityContext.allowPrivilegeEscalation` | 允许特权升级 | `false` |

### Recursor 配置参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `config.incoming.listen` | 监听地址 | `["0.0.0.0"]` |
| `config.incoming.port` | DNS 端口 | `53` |
| `config.incoming.allowFrom` | 允许的客户端 | `[RFC1918...]` |
| `config.incoming.allowNoRd` | 允许无递归查询 | `false` |
| `config.incoming.tcpFastOpen` | TCP Fast Open | `64` |
| `config.incoming.reuseport` | SO_REUSEPORT | `true` |
| `config.incoming.proxyProtocolFrom` | 接受 Proxy Protocol 的来源 | `[]` |
| `config.incoming.proxyProtocolExceptions` | Proxy Protocol 例外 | `[]` |
| `config.incoming.allowNotifyFrom` | 允许 NOTIFY 的来源 | `[]` |
| `config.incoming.allowNotifyFor` | 允许 NOTIFY 的域名 | `[]` |
| `config.recursor.threads` | 线程数 | `4` |
| `config.recursor.pdnsDistributesQueries` | 查询分发 | `true` |
| `config.recursor.socketDir` | Socket 目录 | `/var/run` |
| `config.recursor.versionString` | 版本字符串 | `anonymous` |
| `config.recursor.extendedResolutionErrors` | 扩展 DNS 错误 (RFC 8914) | `true` |
| `config.recursor.sortlists` | 响应排序列表 | `[]` |
| `config.dns64.prefix` | DNS64 前缀 | `""` |
| `config.dnssec.validation` | DNSSEC 验证模式 | `validate` |
| `config.dnssec.logBogus` | 记录 BOGUS | `true` |
| `config.dnssec.aggressiveNsecCacheSize` | NSEC 缓存大小 | `100000` |
| `config.dnssec.nsec3MaxIterations` | NSEC3 最大迭代次数 | `50` |
| `config.dnssec.maxDnskeys` | 每区域最大 DNSKEY 数 | `2` |
| `config.logging.loglevel` | 日志级别 | `4` |
| `config.logging.structuredLogging` | 结构化日志 | `true` |
| `config.ecs.addFor` | ECS 目标 | `["0.0.0.0/0"...]` |
| `config.ecs.ipv4Bits` | IPv4 ECS 位数 | `24` |
| `config.ecs.ipv6Bits` | IPv6 ECS 位数 | `56` |
| `config.cache.maxCacheEntries` | 最大缓存条目 | `1000000` |
| `config.cache.maxNegativeTtl` | 最大负缓存 TTL | `3600` |
| `config.cache.maxCacheTtl` | 最大缓存 TTL | `86400` |

### 出站查询参数 (Outgoing)

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `config.outgoing.dontQuery` | 不查询的 IP/CIDR | `[RFC1918...]` |
| `config.outgoing.sourceAddress` | 出站源地址 | `["0.0.0.0", "::"]` |
| `config.outgoing.networkTimeout` | 查询超时（毫秒） | `1500` |
| `config.outgoing.tcpFastOpenConnect` | 出站 TCP Fast Open | `true` |
| `config.outgoing.ednsSubnetAllowList` | ECS 允许域名列表 | `[]` |
| `config.outgoing.maxQperq` | 每查询最大子查询数 | `60` |
| `config.outgoing.serverDownMaxFails` | 服务器 down 阈值 | `64` |
| `config.outgoing.dotToAuthNames` | 使用 DoT 的权威服务器 | `[]` |
| `config.outgoing.dotToForwarders` | 对 853 端口 forwarder 启用 DoT | `false` |

### 包缓存参数 (Packetcache)

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `config.packetcache.disable` | 禁用包缓存 | `false` |
| `config.packetcache.maxEntries` | 最大条目数 | `500000` |
| `config.packetcache.ttl` | TTL（秒） | `86400` |
| `config.packetcache.shards` | 分片数 | `1024` |

### NOD 参数 (Newly Observed Domain)

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `config.nod.enabled` | 启用 NOD 跟踪 | `false` |
| `config.nod.tracking` | 启用跟踪 | `false` |
| `config.nod.log` | 记录新域名 | `true` |
| `config.nod.lookup` | 查询后缀 | `""` |
| `config.nod.uniqueResponseTracking` | 启用 UDR 跟踪 | `false` |
| `config.nod.uniqueResponseLog` | 记录 UDR | `true` |
| `config.nod.uniqueResponseDbSize` | UDR 数据库大小 | `67108864` |
| `config.nod.uniqueResponsePbTag` | UDR Protobuf 标签 | `pdns-udr` |

### 日志导出参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `config.logging.protobufServers` | Protobuf 服务器列表 | `[]` |
| `config.logging.outgoingProtobufServers` | 出站 Protobuf 服务器 | `[]` |
| `config.logging.protobufMaskV4` | Protobuf IPv4 掩码 | `32` |
| `config.logging.protobufMaskV6` | Protobuf IPv6 掩码 | `128` |
| `config.logging.protobufLogQueries` | 记录查询 | `true` |
| `config.logging.protobufLogResponses` | 记录响应 | `true` |
| `config.logging.dnstapFramestreamServers` | DNSTap 服务器列表 | `[]` |
| `config.logging.dnstapLogQueries` | DNSTap 记录查询 | `true` |
| `config.logging.dnstapLogResponses` | DNSTap 记录响应 | `true` |
| `config.logging.dnstapIdentity` | DNSTap 标识 | `""` |

### Carbon 监控参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `config.carbon.enabled` | 启用 Carbon | `false` |
| `config.carbon.server` | 服务器列表 | `[]` |
| `config.carbon.interval` | 发送间隔（秒） | `30` |
| `config.carbon.namespace` | 命名空间 | `pdns` |

### Webserver/API 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `webserver.enabled` | 启用 Web 服务器 | `true` |
| `webserver.address` | 监听地址 | `0.0.0.0` |
| `webserver.port` | 端口 | `8082` |
| `webserver.allowFrom` | 允许访问的 IP | `["0.0.0.0/0"...]` |
| `webserver.password` | 密码 | `""` |
| `webserver.apiKey` | API 密钥 | `""` |
| `webserver.existingSecret` | 现有 Secret | `""` |

### Forward Zones 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `forwardZones.zones` | 转发区域列表 | `[]` |
| `forwardZones.recursiveZones` | 递归转发区域列表 | `[]` |

### Trust Anchors 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `trustAnchors.enabled` | 启用信任锚点 | `false` |
| `trustAnchors.anchors` | 锚点列表 | `[]` |
| `trustAnchors.negative` | 负信任锚点列表 | `[]` |

### Lua 脚本参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `lua.configEnabled` | 启用配置脚本 | `false` |
| `lua.configScript` | 配置脚本内容 | `""` |
| `lua.dnsEnabled` | 启用 DNS 脚本 | `false` |
| `lua.dnsScript` | DNS 脚本内容 | `""` |

### RPZ 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `rpz.enabled` | 启用 RPZ | `false` |
| `rpz.zones` | RPZ 区域列表 | `[]` |

### Zone to Cache 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `zoneToCache.enabled` | 启用 Zone to Cache | `false` |
| `zoneToCache.zones` | 要缓存的区域列表 | `[]` |
| `zoneToCache.zones[].zone` | 区域名称 | - |
| `zoneToCache.zones[].method` | 获取方式 (url/file/axfr) | - |
| `zoneToCache.zones[].source` | 源 URL/文件/服务器 | - |
| `zoneToCache.zones[].refreshPeriod` | 刷新周期（秒） | - |

### Service 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `service.type` | Service 类型 | `ClusterIP` |
| `service.ports.dns` | DNS UDP 端口 | `53` |
| `service.ports.dnsTcp` | DNS TCP 端口 | `53` |
| `service.ports.webserver` | Web 服务器端口 | `8082` |
| `service.externalTrafficPolicy` | 外部流量策略 | `Local` |
| `service.loadBalancerIP` | LoadBalancer IP | `""` |

### NetworkPolicy 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `networkPolicy.enabled` | 启用 NetworkPolicy | `true` |
| `networkPolicy.allowExternal` | 允许外部入站 | `true` |
| `networkPolicy.allowExternalEgress` | 允许外部出站 | `true` |

### PDB 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `pdb.create` | 创建 PDB | `true` |
| `pdb.minAvailable` | 最小可用 | `""` |
| `pdb.maxUnavailable` | 最大不可用 | `1` |

### 自动伸缩参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `autoscaling.hpa.enabled` | 启用 HPA | `false` |
| `autoscaling.hpa.minReplicas` | 最小副本数 | `2` |
| `autoscaling.hpa.maxReplicas` | 最大副本数 | `10` |
| `autoscaling.hpa.targetCPU` | CPU 目标 | `70` |
| `autoscaling.hpa.targetMemory` | 内存目标 | `80` |
| `autoscaling.vpa.enabled` | 启用 VPA | `false` |

### 监控参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `metrics.enabled` | 启用指标 | `false` |
| `metrics.serviceMonitor.enabled` | 创建 ServiceMonitor | `false` |
| `metrics.serviceMonitor.namespace` | 命名空间 | `""` |
| `metrics.serviceMonitor.interval` | 抓取间隔 | `30s` |

## 配置示例

### 基础部署

```yaml
replicaCount: 2

service:
  type: ClusterIP
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
        app.kubernetes.io/name: powerdns-recursor

resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 1Gi

autoscaling:
  hpa:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPU: 70

pdb:
  create: true
  minAvailable: 2
```

### 转发内部域名到 PowerDNS Auth

```yaml
forwardZones:
  zones:
    - zone: internal.example.com
      forwarders:
        - 10.0.0.10  # PowerDNS Auth Server
      recurse: false
    - zone: corp.example.com
      forwarders:
        - 10.0.0.10
      recurse: false
```

### 使用上游 DNS 服务器

```yaml
forwardZones:
  recursiveZones:
    - zone: "."
      forwarders:
        - 8.8.8.8
        - 8.8.4.4
```

### 配置 DNSSEC 信任锚点

```yaml
trustAnchors:
  enabled: true
  anchors:
    - zone: internal.example.com
      dsRecord: "54970 13 1 27efe1c1a790c3cbb43b947d6d6dfac62507097e"
```

### 启用 RPZ 阻止恶意域名

```yaml
rpz:
  enabled: true
  zones:
    - name: malware-block
      url: "https://example.com/rpz.zone"
      refresh: 3600
      policy: NXDOMAIN
```

### Zone to Cache 预加载

```yaml
zoneToCache:
  enabled: true
  zones:
    - zone: "."
      method: url
      source: "https://www.internic.net/domain/root.zone"
      refreshPeriod: 86400
    - zone: "example.com"
      method: axfr
      source: "192.168.1.1"
      refreshPeriod: 3600
```

### DNS64 (IPv6 过渡)

```yaml
config:
  dns64:
    prefix: "64:ff9b::/96"
```

### Proxy Protocol (负载均衡器后保留真实 IP)

```yaml
config:
  incoming:
    proxyProtocolFrom:
      - "10.0.0.0/8"
    proxyProtocolExceptions:
      - "10.0.0.1"
```

### DoT to Upstream (加密上游查询)

```yaml
config:
  outgoing:
    dotToAuthNames:
      - "ns1.example.com"
      - "ns2.example.com"
    dotToForwarders: true
```

### Protobuf 日志导出

```yaml
config:
  logging:
    protobufServers:
      - "192.168.1.100:4242"
    outgoingProtobufServers:
      - "192.168.1.100:4243"
    protobufLogQueries: true
    protobufLogResponses: true
```

### DNSTap 日志导出 (RFC 8618)

```yaml
config:
  logging:
    dnstapFramestreamServers:
      - "192.168.1.100:6000"
    dnstapLogQueries: true
    dnstapLogResponses: true
    dnstapIdentity: "recursor-prod-1"
```

### UDR (Unique Domain Response) 跟踪

```yaml
config:
  nod:
    enabled: true
    tracking: true
    log: true
    uniqueResponseTracking: true
    uniqueResponseLog: true
```

### Sortlist (响应排序)

```yaml
config:
  recursor:
    sortlists:
      - key: "192.168.0.0/24"
        order:
          - "192.168.0.0/24"
          - "10.0.0.0/8"
```

### 自定义 Lua 脚本

```yaml
lua:
  configEnabled: true
  configScript: |
    pdnslog("Custom config loaded")
    
  dnsEnabled: true
  dnsScript: |
    if dq.qname:equal("blocked.example.com") then
        dq:addAnswer(pdns.A, "0.0.0.0")
        return true
    end
    return false
```

### 启用 Prometheus 监控

```yaml
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    namespace: monitoring
    labels:
      release: prometheus
    interval: 30s
```

### LoadBalancer 服务

```yaml
service:
  type: LoadBalancer
  loadBalancerIP: "192.168.1.100"
  externalTrafficPolicy: Local
```

## 故障排除

### 检查 Pod 状态

```bash
kubectl get pods -n dns -l app.kubernetes.io/name=powerdns-recursor
kubectl logs -n dns -l app.kubernetes.io/name=powerdns-recursor -f
```

### 测试 DNS 解析

```bash
# 端口转发
kubectl port-forward -n dns svc/pdns-recursor 5353:53

# 测试查询
dig @127.0.0.1 -p 5353 google.com
dig @127.0.0.1 -p 5353 dnssec-failed.org +dnssec
```

### 检查配置

```bash
kubectl exec -it deploy/pdns-recursor -n dns -- cat /etc/pdns-recursor/recursor.yml
```

### 查看统计信息

```bash
kubectl port-forward -n dns svc/pdns-recursor 8082:8082
curl http://localhost:8082/api/v1/servers/localhost/statistics
```

## 升级

### 从 0.x 升级到 1.x

1.x 版本采用 Bitnami 风格重构，主要变化：

- values.yaml 结构变化
- 移除 helm-toolkit 依赖，使用 bitnami/common
- 参数命名从 snake_case 改为 camelCase

升级前请仔细检查 values.yaml 并调整配置。

## License

Copyright &copy; 2024

Licensed under the Apache License, Version 2.0.
