# DNSdist 部署指南

本文档提供 DNSdist Helm Chart 的详细部署指南，包含生产环境最佳实践。

## 目录

1. [架构概述](#架构概述)
2. [快速开始](#快速开始)
3. [生产环境部署](#生产环境部署)
4. [加密 DNS 配置](#加密-dns-配置)
5. [高可用架构](#高可用架构)
6. [监控与告警](#监控与告警)
7. [安全加固](#安全加固)
8. [性能调优](#性能调优)
9. [运维操作](#运维操作)
10. [故障排查](#故障排查)

## 架构概述

### 系统架构

```
                                    ┌─────────────────────────────────────┐
                                    │           Kubernetes Cluster        │
                                    │                                     │
    ┌──────────┐                    │  ┌───────────────────────────────┐  │
    │          │   Do53/DoT/DoH     │  │         DNSdist Pods          │  │
    │  客户端   │◄──────────────────┼─►│  ┌─────┐ ┌─────┐ ┌─────┐     │  │
    │          │                    │  │  │Pod 1│ │Pod 2│ │Pod 3│     │  │
    └──────────┘                    │  │  └──┬──┘ └──┬──┘ └──┬──┘     │  │
                                    │  └─────┼──────┼──────┼─────────┘  │
                                    │        │      │      │            │
                                    │        ▼      ▼      ▼            │
                                    │  ┌───────────────────────────────┐  │
                                    │  │        Backend Pools          │  │
                                    │  │  ┌─────────┐ ┌─────────────┐  │  │
                                    │  │  │Recursor │ │Authoritative│  │  │
                                    │  │  │  Pool   │ │    Pool     │  │  │
                                    │  │  └─────────┘ └─────────────┘  │  │
                                    │  └───────────────────────────────┘  │
                                    └─────────────────────────────────────┘
```

### 组件说明

| 组件 | 描述 |
|------|------|
| **DNSdist Pod** | DNS 负载均衡器，处理客户端请求 |
| **Main Service** | LoadBalancer/NodePort，暴露 DNS 服务端口 |
| **API Service** | ClusterIP，内部 API/Metrics 访问 |
| **ConfigMap** | Lua 配置文件 |
| **Secret** | API 密钥、TLS 证书 |

### 支持的协议

| 协议 | 端口 | 描述 |
|------|------|------|
| Do53 UDP/TCP | 53 | 传统 DNS |
| DoT | 853 | DNS over TLS |
| DoH | 443 | DNS over HTTPS |
| DoQ | 8853 | DNS over QUIC |
| DoH3 | 8443 | DNS over HTTP/3 |
| DNSCrypt | 8443 | DNSCrypt v2 |

## 快速开始

### 1. 最小化部署

```bash
# 创建命名空间
kubectl create namespace dns

# 使用默认配置安装
helm install dnsdist ./dnsdist -n dns
```

### 2. 验证安装

```bash
# 检查 Pod 状态
kubectl get pods -n dns -l app.kubernetes.io/name=dnsdist

# 获取服务地址
kubectl get svc -n dns

# 测试 DNS 解析
DNS_IP=$(kubectl get svc dnsdist -n dns -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
dig @$DNS_IP example.com
```

## 生产环境部署

### 推荐配置

创建 `production-values.yaml`:

```yaml
# 副本数
replicaCount: 3

# 镜像配置
image:
  registry: docker.io
  repository: powerdns/dnsdist-20
  tag: "2.0.2"
  pullPolicy: IfNotPresent

# 后端服务器
backends:
  recursor:
    enabled: true
    servers:
      - name: recursor-1
        address: pdns-recursor-0.pdns-recursor.dns.svc.cluster.local
        port: 53
      - name: recursor-2
        address: pdns-recursor-1.pdns-recursor.dns.svc.cluster.local
        port: 53
      - name: recursor-3
        address: pdns-recursor-2.pdns-recursor.dns.svc.cluster.local
        port: 53
    healthCheck:
      mode: lazy
      interval: 5
      lazyThreshold: 20
      lazySampleSize: 100
      lazyMinSampleCount: 10

# 监听器
listeners:
  dns:
    enabled: true
    tcpFastOpen: 128
  dot:
    enabled: true
  doh:
    enabled: true
    additionalPaths:
      - /resolve

# TLS 配置
tls:
  existingSecret: dnsdist-tls

# 缓存配置
cache:
  enabled: true
  size: 500000
  maxTTL: 86400
  minTTL: 60
  stale:
    enabled: true
    ttl: 300
  negativeTTL: 60

# 限速配置
rateLimit:
  enabled: true
  delayThreshold: 200
  delayMs: 50
  dropThreshold: 1000
  ipv4PrefixLength: 32
  ipv6PrefixLength: 56

# 安全规则
security:
  dropChaos: true
  dropAny: true
  minTTL: 30
  maxTTL: 86400

# 资源配置
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi

# Pod 调度
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: dnsdist
        topologyKey: kubernetes.io/hostname

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: dnsdist

# PDB
pdb:
  create: true
  minAvailable: 2

# HPA
autoscaling:
  hpa:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPU: 70
    targetMemory: 80

# 网络策略
networkPolicy:
  enabled: true
  allowExternal: true

# 监控
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 15s
    labels:
      release: prometheus

# Service 配置
service:
  type: LoadBalancer
  externalTrafficPolicy: Local
  annotations:
    # AWS NLB
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
```

### 部署命令

```bash
helm install dnsdist ./dnsdist \
  --namespace dns \
  --create-namespace \
  -f production-values.yaml
```

## 加密 DNS 配置

### 创建 TLS 证书

#### 方式一：使用 cert-manager

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: dnsdist-tls
  namespace: dns
spec:
  secretName: dnsdist-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - dns.example.com
    - "*.dns.example.com"
```

#### 方式二：手动创建 Secret

```bash
kubectl create secret tls dnsdist-tls \
  --cert=tls.crt \
  --key=tls.key \
  -n dns
```

### DoT 配置

```yaml
listeners:
  dot:
    enabled: true
    address: "0.0.0.0"
    port: 853
    minTLSVersion: tls1.2
    ciphers: ""  # 使用默认安全加密套件
    numberOfTicketsKeys: 5

tls:
  existingSecret: dnsdist-tls
```

测试 DoT:

```bash
kdig +tls @dns.example.com example.com
```

### DoH 配置

```yaml
listeners:
  doh:
    enabled: true
    address: "0.0.0.0"
    port: 443
    path: /dns-query
    minTLSVersion: tls1.2
    additionalPaths:
      - /resolve
      - /query
    customResponses:
      - path: /health
        status: 200
        content: "OK"
        contentType: text/plain
      - path: /ready
        status: 200
        content: "READY"
        contentType: text/plain

tls:
  existingSecret: dnsdist-tls
```

测试 DoH:

```bash
# JSON 格式
curl -H "accept: application/dns-json" \
  "https://dns.example.com/dns-query?name=example.com&type=A"

# Wire 格式
curl -H "content-type: application/dns-message" \
  --data-binary @query.bin \
  "https://dns.example.com/dns-query"
```

### DoQ 配置

```yaml
listeners:
  doq:
    enabled: true
    address: "0.0.0.0"
    port: 8853
    idleTimeout: 30

tls:
  existingSecret: dnsdist-tls
```

### DoH3 配置

```yaml
listeners:
  doh3:
    enabled: true
    address: "0.0.0.0"
    port: 8443
    path: /dns-query
    idleTimeout: 30

tls:
  existingSecret: dnsdist-tls
```

### DNSCrypt 配置

```yaml
listeners:
  dnscrypt:
    enabled: true
    address: "0.0.0.0"
    port: 8443
    providerName: "2.dnscrypt-cert.dns.example.com"
    certValidity: 365

# 持久化 DNSCrypt 密钥
persistence:
  enabled: true
  size: 100Mi
```

## 高可用架构

### 多区域部署

```yaml
# Zone A 部署
replicaCount: 2

affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: topology.kubernetes.io/zone
              operator: In
              values:
                - zone-a
```

### 跨区域负载均衡

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: dnsdist
```

### HPA 配置

```yaml
autoscaling:
  hpa:
    enabled: true
    minReplicas: 3
    maxReplicas: 20
    targetCPU: 70
    targetMemory: 80
    behavior:
      scaleDown:
        stabilizationWindowSeconds: 300
        policies:
          - type: Percent
            value: 10
            periodSeconds: 60
      scaleUp:
        stabilizationWindowSeconds: 0
        policies:
          - type: Percent
            value: 100
            periodSeconds: 15
```

## 监控与告警

### Prometheus 指标

DNSdist 暴露以下关键指标:

| 指标 | 描述 |
|------|------|
| `dnsdist_queries` | 查询总数 |
| `dnsdist_responses` | 响应总数 |
| `dnsdist_cache_hits` | 缓存命中数 |
| `dnsdist_cache_misses` | 缓存未命中数 |
| `dnsdist_latency` | 延迟分布 |
| `dnsdist_backend_*` | 后端状态 |

### Grafana 仪表板

推荐使用 DNSdist 官方 Grafana 仪表板或自定义:

```json
{
  "title": "DNSdist Overview",
  "panels": [
    {
      "title": "QPS",
      "targets": [
        {
          "expr": "rate(dnsdist_queries[5m])"
        }
      ]
    },
    {
      "title": "Cache Hit Rate",
      "targets": [
        {
          "expr": "rate(dnsdist_cache_hits[5m]) / (rate(dnsdist_cache_hits[5m]) + rate(dnsdist_cache_misses[5m]))"
        }
      ]
    }
  ]
}
```

### 告警规则

```yaml
groups:
  - name: dnsdist
    rules:
      - alert: DNSdistDown
        expr: up{job="dnsdist"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "DNSdist 实例宕机"

      - alert: DNSdistHighLatency
        expr: histogram_quantile(0.99, rate(dnsdist_latency_bucket[5m])) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "DNSdist P99 延迟过高"

      - alert: DNSdistLowCacheHitRate
        expr: |
          rate(dnsdist_cache_hits[5m]) / 
          (rate(dnsdist_cache_hits[5m]) + rate(dnsdist_cache_misses[5m])) < 0.5
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "DNSdist 缓存命中率过低"

      - alert: DNSdistBackendDown
        expr: dnsdist_backend_status == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "DNSdist 后端服务器宕机"
```

## 安全加固

### Pod 安全策略

```yaml
podSecurityContext:
  enabled: true
  fsGroup: 953
  seccompProfile:
    type: RuntimeDefault

containerSecurityContext:
  enabled: true
  runAsUser: 953
  runAsGroup: 953
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false  # DNSCrypt 需要写权限
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault
```

### NetworkPolicy

```yaml
networkPolicy:
  enabled: true
  allowExternal: true
  extraIngress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
      ports:
        - port: 8083
          protocol: TCP
  extraEgress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: dns-backend
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
```

### ACL 配置

```yaml
acl:
  allowed:
    - "10.0.0.0/8"      # 内部网络
    - "172.16.0.0/12"   # 内部网络
    - "192.168.0.0/16"  # 内部网络
  blocked:
    - "0.0.0.0/8"       # 本地地址
    - "224.0.0.0/4"     # 组播地址
```

## 性能调优

### 缓存优化

```yaml
cache:
  enabled: true
  size: 1000000        # 大型部署增加缓存大小
  maxTTL: 86400        # 24小时
  minTTL: 60           # 最小1分钟，避免频繁查询
  stale:
    enabled: true
    ttl: 3600          # 过期后继续服务1小时
  negativeTTL: 300     # 负缓存5分钟
```

### 连接优化

```yaml
listeners:
  dns:
    enabled: true
    tcpFastOpen: 256   # 增加 TFO 队列大小

extraConfig: |
  -- TCP 连接池优化
  setTCPRecvTimeout(2)
  setTCPSendTimeout(2)
  setMaxTCPConnectionsPerClient(10)
  setMaxTCPQueriesPerConnection(100)
```

### 资源建议

| 规模 | QPS | CPU | 内存 | 副本数 |
|------|-----|-----|------|--------|
| 小型 | <1K | 500m | 512Mi | 2 |
| 中型 | 1K-10K | 1000m | 1Gi | 3 |
| 大型 | 10K-100K | 2000m | 2Gi | 5+ |
| 超大型 | >100K | 4000m | 4Gi | 10+ |

## 运维操作

### 滚动更新

```bash
# 更新镜像
helm upgrade dnsdist ./dnsdist \
  --namespace dns \
  --set image.tag=2.0.3 \
  --reuse-values

# 查看更新状态
kubectl rollout status deployment/dnsdist -n dns
```

### 回滚

```bash
# 查看历史版本
helm history dnsdist -n dns

# 回滚到指定版本
helm rollback dnsdist 2 -n dns
```

### 扩缩容

```bash
# 手动扩容
kubectl scale deployment/dnsdist -n dns --replicas=5

# 或修改 values
helm upgrade dnsdist ./dnsdist \
  --namespace dns \
  --set replicaCount=5 \
  --reuse-values
```

### 配置热更新

DNSdist 支持通过控制台热更新部分配置:

```bash
# 进入控制台
kubectl exec -it deployment/dnsdist -n dns -- dnsdist -c

# 示例：添加新的后端服务器
> newServer({address="10.0.0.10:53", name="new-backend", pool="recursor"})

# 示例：修改 ACL
> addACL("192.168.100.0/24")
```

## 故障排查

### 常见问题

#### 1. Pod 无法启动

```bash
# 查看 Pod 状态
kubectl describe pod -n dns -l app.kubernetes.io/name=dnsdist

# 查看日志
kubectl logs -n dns -l app.kubernetes.io/name=dnsdist --tail=100
```

常见原因:
- 后端服务器不可达
- TLS 证书配置错误
- 资源不足

#### 2. DNS 解析失败

```bash
# 测试连通性
kubectl exec -it deployment/dnsdist -n dns -- dnsdist -c
> showServers()
> getServer(0):isUp()
```

#### 3. 高延迟

```bash
# 检查缓存状态
kubectl exec -it deployment/dnsdist -n dns -- dnsdist -c
> showCacheStats()
> showResponseLatency()
```

#### 4. 证书问题

```bash
# 检查证书
kubectl get secret dnsdist-tls -n dns -o yaml

# 验证证书有效期
kubectl exec -it deployment/dnsdist -n dns -- \
  openssl x509 -in /etc/dnsdist/tls/tls.crt -noout -dates
```

### 日志分析

启用详细日志:

```yaml
logging:
  queries: true
  verbose: true
  responses: true
```

查看日志:

```bash
kubectl logs -f deployment/dnsdist -n dns | grep -E "query|response|error"
```

### 性能诊断

```bash
# 进入控制台
kubectl exec -it deployment/dnsdist -n dns -- dnsdist -c

# 查看统计
> showServers()
> showBinds()
> showRules()
> showResponseLatency()
> showTCPStats()
> showCacheStats()
> topQueries(20)
> topResponses(20)
```

## 附录

### 版本兼容性

| Chart 版本 | DNSdist 版本 | Kubernetes 版本 |
|-----------|-------------|----------------|
| 1.0.x | 2.0.x | 1.24+ |

### 参考资料

- [DNSdist 官方文档](https://dnsdist.org/)
- [PowerDNS 官网](https://www.powerdns.com/)
- [Kubernetes DNS 最佳实践](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
