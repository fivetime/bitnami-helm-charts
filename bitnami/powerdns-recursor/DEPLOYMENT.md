# PowerDNS Recursor 部署指南

本文档提供 PowerDNS Recursor Helm Chart 的详细部署指南。

## 目录

1. [环境准备](#1-环境准备)
2. [基础部署](#2-基础部署)
3. [高可用部署](#3-高可用部署)
4. [转发区域配置](#4-转发区域配置)
5. [DNSSEC 配置](#5-dnssec-配置)
6. [RPZ 配置](#6-rpz-配置)
7. [Lua 脚本](#7-lua-脚本)
8. [监控配置](#8-监控配置)
9. [安全加固](#9-安全加固)
10. [高级功能](#10-高级功能)
11. [常见问题](#11-常见问题)

---

## 1. 环境准备

### 1.1 系统要求

| 组件 | 最低版本 | 推荐版本 |
|------|---------|---------|
| Kubernetes | 1.25+ | 1.28+ |
| Helm | 3.8.0+ | 3.14+ |

### 1.2 资源规划

| 规模 | 副本数 | CPU (每副本) | 内存 (每副本) | 适用场景 |
|-----|-------|-------------|-------------|---------|
| 开发 | 1 | 100m-500m | 128Mi-256Mi | 测试环境 |
| 小型 | 2 | 250m-1000m | 256Mi-512Mi | 小型生产 |
| 中型 | 3 | 500m-2000m | 512Mi-1Gi | 中等流量 |
| 大型 | 5+ | 1000m-4000m | 1Gi-2Gi | 高流量 |

### 1.3 网络端口

| 端口 | 协议 | 用途 |
|-----|------|------|
| 53 | UDP | DNS 查询 |
| 53 | TCP | DNS 查询/大响应 |
| 8082 | TCP | Webserver/API |

---

## 2. 基础部署

### 2.1 创建命名空间

```bash
kubectl create namespace dns
```

### 2.2 基本配置

```yaml
# values-basic.yaml
replicaCount: 2

service:
  type: ClusterIP

webserver:
  enabled: true
```

### 2.3 部署

```bash
helm install pdns-recursor ./powerdns-recursor \
  --namespace dns \
  -f values-basic.yaml
```

### 2.4 验证部署

```bash
# 检查 Pod 状态
kubectl get pods -n dns -l app.kubernetes.io/name=powerdns-recursor

# 查看日志
kubectl logs -n dns -l app.kubernetes.io/name=powerdns-recursor -f

# 测试 DNS 查询
kubectl run dns-test --rm -it --restart=Never --image=busybox -- \
  nslookup google.com pdns-recursor.dns.svc.cluster.local
```

---

## 3. 高可用部署

### 3.1 Pod 反亲和性

```yaml
replicaCount: 3

podAntiAffinityPreset: hard
```

### 3.2 拓扑分布约束

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: powerdns-recursor
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: powerdns-recursor
```

### 3.3 HPA 自动伸缩

```yaml
autoscaling:
  hpa:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPU: 70
    targetMemory: 80
```

### 3.4 PDB 配置

```yaml
pdb:
  create: true
  minAvailable: 2
```

### 3.5 完整高可用配置

```yaml
# values-ha.yaml
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

service:
  type: LoadBalancer
  externalTrafficPolicy: Local
```

---

## 4. 转发区域配置

### 4.1 转发内部域名到 PowerDNS Auth

```yaml
forwardZones:
  zones:
    # 内部域名转发到 Auth 服务器（不递归）
    - zone: internal.example.com
      forwarders:
        - 10.0.0.10
        - 10.0.0.11
      recurse: false
    
    # 公司域名
    - zone: corp.example.com
      forwarders:
        - 10.0.0.10
      recurse: false
```

### 4.2 使用上游 DNS 服务器

```yaml
forwardZones:
  recursiveZones:
    # 所有其他查询转发到公共 DNS
    - zone: "."
      forwarders:
        - 8.8.8.8
        - 8.8.4.4
        - 1.1.1.1
```

### 4.3 混合配置

```yaml
forwardZones:
  # 非递归转发（内部 Auth 服务器）
  zones:
    - zone: internal.example.com
      forwarders:
        - pdns-auth.dns.svc.cluster.local
      recurse: false
  
  # 递归转发（上游 DNS）
  recursiveZones:
    - zone: "."
      forwarders:
        - 8.8.8.8
        - 1.1.1.1
```

---

## 5. DNSSEC 配置

### 5.1 启用 DNSSEC 验证

默认已启用，配置选项：

```yaml
config:
  dnssec:
    # 验证模式: off, process-no-validate, process, log-fail, validate
    validation: validate
    # 记录 BOGUS 响应
    logBogus: true
    # NSEC 缓存大小
    aggressiveNsecCacheSize: 100000
```

### 5.2 配置私有区域的信任锚点

对于内部使用 DNSSEC 签名的区域，需要配置信任锚点：

```yaml
trustAnchors:
  enabled: true
  anchors:
    - zone: internal.example.com
      dsRecord: "54970 13 1 27efe1c1a790c3cbb43b947d6d6dfac62507097e"
    - zone: secure.corp.com
      dsRecord: "12345 8 2 abcdef1234567890..."
```

### 5.3 生成 DS 记录

在 PowerDNS Auth 服务器上生成 DS 记录：

```bash
# 在 Auth 服务器上
pdnsutil show-zone internal.example.com

# 输出类似：
# DS = internal.example.com IN DS 54970 13 1 27efe1c1...
```

---

## 6. RPZ 配置

### 6.1 启用 RPZ

Response Policy Zones 用于阻止恶意域名：

```yaml
rpz:
  enabled: true
  zones:
    # 从 URL 加载
    - name: malware-block
      url: "https://example.com/rpz.zone"
      refresh: 3600
      policy: NXDOMAIN
    
    # 从本地文件加载
    - name: local-policy
      file: /etc/pdns-recursor/rpz/local.zone
      policy: NODATA
```

### 6.2 RPZ 策略类型

| 策略 | 描述 |
|------|------|
| NXDOMAIN | 返回 NXDOMAIN |
| NODATA | 返回 NODATA |
| DROP | 丢弃查询 |
| PASSTHRU | 允许查询 |
| TCP-Only | 强制使用 TCP |

### 6.3 挂载自定义 RPZ 文件

```yaml
extraVolumes:
  - name: rpz-data
    configMap:
      name: rpz-local-zone

extraVolumeMounts:
  - name: rpz-data
    mountPath: /etc/pdns-recursor/rpz
    readOnly: true
```

---

## 7. Lua 脚本

### 7.1 配置脚本 (config.lua)

用于高级配置，如动态添加信任锚点：

```yaml
lua:
  configEnabled: true
  configScript: |
    pdnslog("Loading custom configuration")
    
    -- 动态添加信任锚点
    addTA("dynamic.example.com", "12345 13 1 abcdef...")
    
    -- 设置自定义 forward zones
    addForwardZone("special.example.com", {"192.168.1.1", "192.168.1.2"})
```

### 7.2 DNS 脚本 (dns.lua)

用于拦截和修改 DNS 查询：

```yaml
lua:
  dnsEnabled: true
  dnsScript: |
    -- 阻止特定域名
    if dq.qname:equal("blocked.example.com") then
        dq:addAnswer(pdns.A, "0.0.0.0")
        return true
    end
    
    -- 重定向查询
    if dq.qname:isPartOf("old.example.com") then
        dq.followupName = "new.example.com"
        dq.followupPrefix = dq.qname:makeRelative(newDN("old.example.com"))
        dq.followupFunction = "followCNAMERecords"
        return false
    end
    
    -- 日志记录
    if dq.qtype == pdns.A then
        pdnslog("A query for: " .. dq.qname:toString())
    end
    
    return false
```

### 7.3 组合使用

```yaml
lua:
  configEnabled: true
  configScript: |
    pdnslog("Config loaded")
    
  dnsEnabled: true
  dnsScript: |
    -- 阻止广告域名
    local blocked = {
        ["ad.example.com"] = true,
        ["tracker.example.com"] = true,
    }
    
    if blocked[dq.qname:toString()] then
        dq:addAnswer(pdns.A, "0.0.0.0")
        return true
    end
    return false

trustAnchors:
  enabled: true
  anchors:
    - zone: internal.example.com
      dsRecord: "54970 13 1 27efe1c1..."
```

---

## 8. 监控配置

### 8.1 启用 Prometheus 监控

```yaml
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    namespace: monitoring
    labels:
      release: prometheus
    interval: 30s
    scrapeTimeout: 10s
```

### 8.2 重要指标

| 指标 | 描述 |
|------|------|
| `pdns_recursor_questions` | 收到的查询数 |
| `pdns_recursor_answers` | 发送的响应数 |
| `pdns_recursor_cache_hits` | 缓存命中数 |
| `pdns_recursor_cache_misses` | 缓存未命中数 |
| `pdns_recursor_outgoing_timeouts` | 出站超时数 |
| `pdns_recursor_servfail_answers` | SERVFAIL 响应数 |

### 8.3 告警规则示例

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: pdns-recursor-alerts
  namespace: monitoring
spec:
  groups:
    - name: pdns-recursor
      rules:
        - alert: RecursorDown
          expr: up{job="pdns-recursor"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "PowerDNS Recursor is down"
            
        - alert: HighServfailRate
          expr: |
            rate(pdns_recursor_servfail_answers[5m]) / 
            rate(pdns_recursor_answers[5m]) > 0.1
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "High SERVFAIL rate"
            
        - alert: LowCacheHitRate
          expr: |
            rate(pdns_recursor_cache_hits[5m]) / 
            (rate(pdns_recursor_cache_hits[5m]) + rate(pdns_recursor_cache_misses[5m])) < 0.5
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "Low cache hit rate"
```

---

## 9. 安全加固

### 9.1 安全上下文

默认启用的安全设置：

```yaml
podSecurityContext:
  enabled: true
  fsGroup: 953

containerSecurityContext:
  enabled: true
  runAsUser: 953
  runAsGroup: 953
  runAsNonRoot: true
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault
```

### 9.2 NetworkPolicy

```yaml
networkPolicy:
  enabled: true
  allowExternal: true
  allowExternalEgress: true
  
  # 限制入站来源
  extraIngress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: allowed-namespace
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
```

### 9.3 限制允许的客户端

```yaml
config:
  incoming:
    allowFrom:
      - "10.0.0.0/8"
      - "192.168.0.0/16"
      # 移除 0.0.0.0/0 以限制访问
```

### 9.4 API 认证

```yaml
webserver:
  enabled: true
  password: "your-secure-password"
  apiKey: "your-api-key"
  allowFrom:
    - "10.0.0.0/8"  # 限制 API 访问来源
```

---

## 10. 高级功能

### 10.1 DNS64 (IPv6 过渡)

DNS64 允许纯 IPv6 客户端访问仅有 IPv4 地址的资源。

```yaml
config:
  dns64:
    prefix: "64:ff9b::/96"  # 标准 NAT64 前缀
```

**工作原理**: 当客户端查询 AAAA 记录但域名只有 A 记录时，Recursor 会合成一个 AAAA 记录，将 IPv4 地址嵌入到 DNS64 前缀中。

### 10.2 Proxy Protocol

在负载均衡器后面部署时，使用 Proxy Protocol 保留真实客户端 IP。

```yaml
config:
  incoming:
    proxyProtocolFrom:
      - "10.0.0.0/8"      # 负载均衡器网段
    proxyProtocolExceptions:
      - "10.0.0.1"        # 健康检查 IP（不使用 Proxy Protocol）
```

**注意**: 需要确保负载均衡器配置了 Proxy Protocol v2。

### 10.3 Zone to Cache

预加载热点区域到缓存，提高查询性能。

```yaml
zoneToCache:
  enabled: true
  zones:
    # 预加载根区域
    - zone: "."
      method: url
      source: "https://www.internic.net/domain/root.zone"
      refreshPeriod: 86400      # 每天刷新

    # 从权威服务器 AXFR
    - zone: "example.com"
      method: axfr
      source: "192.168.1.1"
      refreshPeriod: 3600       # 每小时刷新
```

### 10.4 DoT to Upstream (加密上游查询)

对上游服务器使用 DNS over TLS 加密查询。

```yaml
config:
  outgoing:
    # 对指定权威服务器强制使用 DoT
    dotToAuthNames:
      - "ns1.example.com"
      - "ns2.example.com"

    # 对 853 端口的 forwarder 自动启用 DoT
    dotToForwarders: true

forwardZones:
  zones:
    - zone: "secure.example.com"
      forwarders:
        - "192.168.1.1:853"   # 使用 853 端口自动启用 DoT
      recurse: false
```

### 10.5 Protobuf 日志导出

将查询/响应日志导出到 Protobuf 服务器进行分析。

```yaml
config:
  logging:
    # 入站查询日志
    protobufServers:
      - "192.168.1.100:4242"

    # 出站查询日志
    outgoingProtobufServers:
      - "192.168.1.100:4243"

    # IP 掩码（隐私保护）
    protobufMaskV4: 24          # /24 掩码
    protobufMaskV6: 56          # /56 掩码

    # 日志内容
    protobufLogQueries: true
    protobufLogResponses: true

    # 高级选项
    protobufAlwaysCache: false
    protobufTaggedOnly: false
```

### 10.6 DNSTap 日志导出 (RFC 8618)

使用标准化的 DNSTap 格式导出日志。

```yaml
config:
  logging:
    dnstapFramestreamServers:
      - "192.168.1.100:6000"

    dnstapLogQueries: true
    dnstapLogResponses: true
    dnstapIdentity: "recursor-prod-1"
```

**兼容工具**: 
- dnstap-read
- dnsdist
- dnscap
- passivedns

### 10.7 UDR (Unique Domain Response) 跟踪

跟踪每个域名的唯一响应，用于安全分析。

```yaml
config:
  nod:
    enabled: true
    tracking: true
    log: true

    # UDR 配置
    uniqueResponseTracking: true
    uniqueResponseLog: true
    uniqueResponseDbSize: 67108864    # 64MB
    uniqueResponsePbTag: "pdns-udr"
```

### 10.8 Sortlist (响应排序)

按客户端 IP 对 A/AAAA 记录进行排序优化。

```yaml
config:
  recursor:
    sortlists:
      # 192.168.0.0/24 客户端优先返回同网段地址
      - key: "192.168.0.0/24"
        order:
          - "192.168.0.0/24"
          - "10.0.0.0/8"

      # 10.0.0.0/8 客户端优先返回内网地址
      - key: "10.0.0.0/8"
        order:
          - "10.0.0.0/8"
          - "192.168.0.0/16"
```

### 10.9 Extended DNS Errors (RFC 8914)

返回详细的 DNS 错误信息，便于调试。

```yaml
config:
  recursor:
    extendedResolutionErrors: true    # 默认启用
```

**错误代码示例**:
- `DNSSEC Bogus`: DNSSEC 验证失败
- `DNSSEC Indeterminate`: DNSSEC 验证不确定
- `Network Error`: 网络连接问题
- `No Reachable Authority`: 无法连接权威服务器

### 10.10 Allow Notify (缓存失效)

接收 NOTIFY 通知并清除相关缓存。

```yaml
config:
  incoming:
    allowNotifyFrom:
      - "192.168.1.0/24"      # 允许发送 NOTIFY 的服务器

    allowNotifyFor:
      - "example.com"          # 允许接收 NOTIFY 的域名
      - "internal.corp"
```

**用途**: 当权威服务器更新区域后，发送 NOTIFY 通知 Recursor 清除缓存。

---

## 11. 常见问题

### 11.1 Pod 启动失败

**排查步骤**:

```bash
# 查看 Pod 事件
kubectl describe pod -n dns -l app.kubernetes.io/name=powerdns-recursor

# 查看日志
kubectl logs -n dns -l app.kubernetes.io/name=powerdns-recursor --previous
```

### 11.2 DNS 查询超时

**排查步骤**:

```bash
# 检查 Service
kubectl get svc -n dns
kubectl get endpoints -n dns

# 测试 Pod 内部 DNS
kubectl exec -it deploy/pdns-recursor -n dns -- \
  dig @127.0.0.1 google.com

# 检查出站连接
kubectl exec -it deploy/pdns-recursor -n dns -- \
  dig @8.8.8.8 google.com
```

### 11.3 DNSSEC 验证失败

**症状**: 某些域名返回 SERVFAIL

**排查步骤**:

```bash
# 检查 DNSSEC 状态
kubectl exec -it deploy/pdns-recursor -n dns -- \
  dig @127.0.0.1 example.com +dnssec

# 查看日志中的 BOGUS 记录
kubectl logs -n dns deploy/pdns-recursor | grep -i bogus
```

### 11.4 转发区域不工作

**排查步骤**:

```bash
# 检查配置
kubectl exec -it deploy/pdns-recursor -n dns -- \
  cat /etc/pdns-recursor/recursor.yml | grep -A 10 forward

# 测试转发目标
kubectl exec -it deploy/pdns-recursor -n dns -- \
  dig @<forwarder-ip> internal.example.com
```

### 11.5 缓存问题

**清除缓存**:

```bash
# 通过 API 清除缓存
kubectl port-forward -n dns svc/pdns-recursor 8082:8082
curl -X PUT http://localhost:8082/api/v1/servers/localhost/cache/flush?domain=example.com
```

---

## 附录

### A. 常用 API 操作

```bash
# 获取统计信息
curl http://localhost:8082/api/v1/servers/localhost/statistics

# 获取配置
curl http://localhost:8082/api/v1/servers/localhost/config

# 清除缓存
curl -X PUT "http://localhost:8082/api/v1/servers/localhost/cache/flush?domain=example.com"

# 获取缓存统计
curl http://localhost:8082/api/v1/servers/localhost/cache
```

### B. 性能调优

```yaml
config:
  recursor:
    # 增加线程数（建议等于 CPU 核心数）
    threads: 8
    
  cache:
    # 增加缓存大小
    maxCacheEntries: 2000000
    # 调整 TTL
    maxCacheTtl: 86400
    maxNegativeTtl: 3600

resources:
  requests:
    cpu: 2000m
    memory: 2Gi
  limits:
    cpu: 4000m
    memory: 4Gi
```

### C. 调试模式

```yaml
diagnosticMode:
  enabled: true
  command:
    - sleep
  args:
    - infinity
```

然后进入容器调试：

```bash
kubectl exec -it deploy/pdns-recursor -n dns -- /bin/bash
```
