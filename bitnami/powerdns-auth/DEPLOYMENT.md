# PowerDNS Authoritative Server 部署指南

本文档提供 PowerDNS Authoritative Server Helm Chart 的详细部署指南。

## 目录

1. [环境准备](#1-环境准备)
2. [数据库准备](#2-数据库准备)
3. [基础部署](#3-基础部署)
4. [高可用部署](#4-高可用部署)
5. [区域传输配置](#5-区域传输配置)
6. [GeoDNS 部署](#6-geodns-部署)
7. [安全加固](#7-安全加固)
8. [监控配置](#8-监控配置)
9. [常见问题](#9-常见问题)
10. [升级与回滚](#10-升级与回滚)
11. [卸载](#11-卸载)

---

## 1. 环境准备

### 1.1 系统要求

| 组件 | 最低版本 | 推荐版本 |
|------|---------|---------|
| Kubernetes | 1.25+ | 1.28+ |
| Helm | 3.8.0+ | 3.14+ |
| 数据库 | PostgreSQL 14+ / MySQL 8.0+ | PostgreSQL 16 |

### 1.2 资源规划

| 规模 | 副本数 | CPU (每副本) | 内存 (每副本) | 适用场景 |
|-----|-------|-------------|-------------|---------|
| 开发 | 1 | 100m-500m | 128Mi-256Mi | 测试/开发环境 |
| 小型 | 2 | 250m-1000m | 256Mi-512Mi | 小型生产环境 |
| 中型 | 3 | 500m-2000m | 512Mi-1Gi | 中等流量生产环境 |
| 大型 | 5+ | 1000m-4000m | 1Gi-2Gi | 高流量生产环境 |

### 1.3 网络端口

| 端口 | 协议 | 用途 | 默认开放 |
|-----|------|------|---------|
| 53 | UDP | DNS 查询 | ✅ |
| 53 | TCP | DNS 查询/AXFR | ✅ |
| 8081 | TCP | API/Webserver | ✅ (可选) |

---

## 2. 数据库准备

### 2.1 PostgreSQL 部署

#### 使用 Bitnami PostgreSQL Chart

```bash
# 添加 Bitnami 仓库
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# 部署 PostgreSQL
helm install postgresql bitnami/postgresql \
  --namespace database --create-namespace \
  --set auth.postgresPassword=admin-password \
  --set auth.username=pdns \
  --set auth.password=pdns-password \
  --set auth.database=pdns
```

#### 验证数据库连接

```bash
kubectl run postgresql-client --rm --tty -i --restart='Never' \
  --namespace database \
  --image docker.io/bitnami/postgresql:16 \
  --env="PGPASSWORD=pdns-password" \
  --command -- psql --host postgresql -U pdns -d pdns -p 5432 -c "SELECT 1"
```

### 2.2 MySQL 部署

#### 使用 Bitnami MySQL Chart

```bash
helm install mysql bitnami/mysql \
  --namespace database --create-namespace \
  --set auth.rootPassword=root-password \
  --set auth.database=pdns \
  --set auth.username=pdns \
  --set auth.password=pdns-password
```

### 2.3 使用 Kubernetes Secret 存储凭据

推荐使用 Kubernetes Secret 存储数据库凭据：

```yaml
# pdns-db-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: pdns-db-credentials
  namespace: dns
type: Opaque
stringData:
  admin-password: "your-admin-password"
  user-password: "your-user-password"
```

```bash
kubectl apply -f pdns-db-secret.yaml
```

在 values.yaml 中引用：

```yaml
database:
  existingSecret:
    enabled: true
    name: pdns-db-credentials
    adminPasswordKey: admin-password
    userPasswordKey: user-password
```

---

## 3. 基础部署

### 3.1 创建命名空间

```bash
kubectl create namespace dns
```

### 3.2 创建 values.yaml

```yaml
# values-basic.yaml
database:
  type: postgresql
  postgresql:
    host: postgresql.database.svc.cluster.local
    port: 5432
    database: pdns
    username: pdns
    password: "pdns-password"
    adminUsername: postgres
    adminPassword: "admin-password"

webserver:
  enabled: true
  apiKey: "your-secure-api-key"

replicaCount: 2

service:
  type: ClusterIP
```

### 3.3 部署 Chart

```bash
helm install pdns-auth ./powerdns-auth \
  --namespace dns \
  -f values-basic.yaml
```

### 3.4 验证部署

```bash
# 检查 Pod 状态
kubectl get pods -n dns -l app.kubernetes.io/name=powerdns-auth

# 检查 Service
kubectl get svc -n dns

# 查看日志
kubectl logs -n dns -l app.kubernetes.io/name=powerdns-auth -f
```

### 3.5 测试 DNS 查询

```bash
# 获取 Service IP
SERVICE_IP=$(kubectl get svc -n dns pdns-auth -o jsonpath='{.spec.clusterIP}')

# 测试查询 (需要先创建 zone)
kubectl run dns-test --rm -it --restart=Never --image=busybox -- \
  nslookup -port=53 example.com $SERVICE_IP
```

---

## 4. 高可用部署

### 4.1 Pod 反亲和性

确保 Pod 分布在不同节点：

```yaml
# values-ha.yaml
replicaCount: 3

podAntiAffinityPreset: hard

# 或者使用自定义亲和性
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: powerdns-auth
        topologyKey: kubernetes.io/hostname
```

### 4.2 拓扑分布约束

跨可用区分布：

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: powerdns-auth
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: powerdns-auth
```

### 4.3 HPA 自动伸缩

```yaml
autoscaling:
  hpa:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPU: 70
    targetMemory: 80
```

### 4.4 PDB 配置

```yaml
pdb:
  create: true
  minAvailable: 2
  # 或者使用 maxUnavailable
  # maxUnavailable: 1
```

### 4.5 资源配置

```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 1Gi
```

### 4.6 完整高可用配置示例

```yaml
# values-production.yaml
replicaCount: 3

podAntiAffinityPreset: hard

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: powerdns-auth

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

database:
  type: postgresql
  existingSecret:
    enabled: true
    name: pdns-db-credentials
  postgresql:
    host: postgresql-ha-pgpool.database.svc.cluster.local
    database: pdns
    username: pdns
```

---

## 5. 区域传输配置

### 5.1 Primary 服务器配置

Primary 服务器负责管理 Zone 数据并向 Secondary 发送通知：

```yaml
# values-primary.yaml
config:
  primary: true
  disableAxfr: false
  allowAxfrIps: "10.0.0.0/8,192.168.0.0/16"
  alsoNotify: "192.168.2.10:53,192.168.2.11:53"

tsig:
  enabled: true
  keys:
    - name: transfer-key
      algorithm: hmac-sha256
      secret: "生成的Base64密钥"
```

生成 TSIG 密钥：

```bash
# 生成随机密钥
openssl rand -base64 32
# 输出类似: K8sU3x9J...==
```

### 5.2 Secondary 服务器配置

Secondary 服务器从 Primary 接收 Zone 数据：

```yaml
# values-secondary.yaml
config:
  secondary: true
  autosecondary: true
  allowUnsignedNotify: false

tsig:
  enabled: true
  keys:
    - name: transfer-key
      algorithm: hmac-sha256
      secret: "与Primary相同的密钥"
```

### 5.3 使用 pdnsutil 管理 TSIG

```bash
# 进入 Pod
kubectl exec -it deploy/pdns-auth -n dns -- /bin/bash

# 列出 TSIG 密钥
pdnsutil list-tsig-keys

# 为 Zone 配置 TSIG
pdnsutil set-meta example.com TSIG-ALLOW-AXFR transfer-key
pdnsutil set-meta example.com AXFR-MASTER-TSIG transfer-key
```

### 5.4 验证区域传输

```bash
# 在 Secondary 上检查 Zone 状态
kubectl exec -it deploy/pdns-auth-secondary -n dns -- pdnsutil list-zone example.com

# 手动触发 AXFR
kubectl exec -it deploy/pdns-auth-secondary -n dns -- pdns_control retrieve example.com
```

---

## 6. GeoDNS 部署

GeoDNS 根据客户端地理位置返回不同的 DNS 解析结果，适用于 CDN、多区域部署等场景。

### 6.1 GeoDNS 实现方式对比

| 特性 | GeoIP Backend | LUA Records |
|------|--------------|-------------|
| 配置方式 | YAML 文件 (静态) | 数据库记录 (动态) |
| 管理接口 | 需重启 Pod | API/PowerDNS-Admin |
| 适用规模 | 中小规模 | 大规模 (百万级域名) |
| 灵活性 | 较低 | 高 (支持复杂逻辑) |
| 推荐场景 | 固定配置的 GeoDNS | 动态管理的 GeoDNS |

**推荐**: 对于需要动态管理的场景，使用 **LUA Records** 模式。

### 6.2 准备 GeoIP 数据库

GeoIP 数据库由独立的 `geoip-database` Chart 管理：

```bash
# 部署 geoip-database chart（在 kube-infra 命名空间）
helm install geoip-database fivetime/geoip-database -n kube-infra -f geoip-values.yaml
```

详细配置请参考 `geoip-database` Chart 文档。

### 6.3 LUA Records GeoDNS 部署

#### 6.3.1 配置文件

```yaml
# values-geodns.yaml
replicaCount: 3

config:
  # 性能配置
  performance:
    receiverThreads: 8          # 建议等于 CPU 核心数
    distributorThreads: 2
    signingThreads: 4
    reuseport: true
    udpTruncationThreshold: 1232
  
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
    ednsSubnetProcessing: true
    execLimit: 5000
    healthChecks:
      enabled: true
      interval: 5
      expireDelay: 3600
      maxConcurrent: 16
      timeout: 2000
    axfrFormat: native

# GeoIP 数据库挂载（使用 geoip-database chart 的 PVC）
geoipVolume:
  enabled: true
  existingClaim: geoip-database-data  # 来自 geoip-database chart

# 不需要 GeoIP Backend
geoip:
  enabled: false

# 数据库配置
database:
  type: postgresql
  existingSecret:
    enabled: true
    name: pdns-db-credentials
  postgresql:
    host: postgresql.database.svc.cluster.local
    database: pdns
    username: pdns

# 启用 API
webserver:
  enabled: true
  apiKey: "your-api-key"

# 资源配置
resources:
  requests:
    cpu: "2"
    memory: "2Gi"
  limits:
    cpu: "4"
    memory: "4Gi"

# 高可用配置
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

#### 6.3.2 部署

```bash
helm install pdns-auth ./powerdns-auth \
  --namespace dns \
  -f values-geodns.yaml
```

#### 6.3.3 验证部署

```bash
# 检查 Pod 状态
kubectl get pods -n dns -l app.kubernetes.io/name=powerdns-auth

# 检查 GeoIP 数据库是否挂载
kubectl exec -it deploy/pdns-auth -n dns -- ls -la /usr/share/GeoIP/

# 检查 CronJob
kubectl get cronjob -n dns

# 检查 ConfigMap (hash)
kubectl get configmap -n dns pdns-auth-geoip-hash -o yaml
```

### 6.4 创建 LUA 记录

#### 6.4.1 通过 API 创建

```bash
API_KEY="your-api-key"
API_URL="http://pdns-auth.dns.svc.cluster.local:8081/api/v1"

# 创建按国家返回的 GeoDNS 记录
curl -X PATCH -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d '{
    "rrsets": [{
      "name": "www.example.com.",
      "type": "LUA",
      "ttl": 300,
      "changetype": "REPLACE",
      "records": [{
        "content": "A \"country({JP='\''103.1.1.1'\'', CN='\''116.2.2.2'\'', US='\''198.3.3.3'\'', default='\''103.1.1.1'\''})\"",
        "disabled": false
      }]
    }]
  }' \
  $API_URL/servers/localhost/zones/example.com.
```

#### 6.4.2 通过 SQL 创建

```bash
kubectl exec -it deploy/pdns-auth -n dns -- psql -h $DB_HOST -U pdns -d pdns
```

```sql
-- 按大洲返回
INSERT INTO records (domain_id, name, type, content, ttl)
SELECT id, 'cdn.example.com', 'LUA', 
       'A "continent({AS=''103.1.1.1'', EU=''185.2.2.2'', NA=''198.3.3.3'', default=''103.1.1.1''})"',
       300
FROM domains WHERE name = 'example.com';

-- 选择最近节点
INSERT INTO records (domain_id, name, type, content, ttl)
SELECT id, 'edge.example.com', 'LUA',
       'A "pickclosest({''103.1.1.1'', ''185.2.2.2'', ''198.3.3.3''})"',
       300
FROM domains WHERE name = 'example.com';

-- 带健康检查
INSERT INTO records (domain_id, name, type, content, ttl)
SELECT id, 'ha.example.com', 'LUA',
       'A "ifportup(443, {''103.1.1.1'', ''185.2.2.2''}, {''198.3.3.3''})"',
       300
FROM domains WHERE name = 'example.com';
```

### 6.5 常用 LUA 函数

| 函数 | 用途 | 示例 |
|------|------|------|
| `country({...})` | 按国家代码返回 | `country({JP='1.1.1.1', default='2.2.2.2'})` |
| `continent({...})` | 按大洲返回 | `continent({AS='1.1.1.1', EU='2.2.2.2'})` |
| `region({...})` | 按地区/省份返回 | `region({13='1.1.1.1'})` (东京=13) |
| `asnum({...})` | 按 ASN 返回 | `asnum({1234='1.1.1.1'})` |
| `pickclosest({...})` | 返回地理最近节点 | `pickclosest({'1.1.1.1','2.2.2.2'})` |
| `pickwhashed(...)` | 加权哈希选择 | `pickwhashed(0.7,'1.1.1.1',0.3,'2.2.2.2')` |
| `pickrandom({...})` | 随机选择 | `pickrandom({'1.1.1.1','2.2.2.2'})` |
| `ifportup(port,{...})` | 端口健康检查 | `ifportup(443,{'1.1.1.1','2.2.2.2'})` |
| `ifurlup(url,{...})` | URL 健康检查 | `ifurlup('https://hc.example.com',{'1.1.1.1'})` |

### 6.6 测试 GeoDNS

```bash
# 模拟来自不同地区的查询 (使用 EDNS Client Subnet)
# 模拟日本客户端
dig @pdns-auth.dns.svc.cluster.local www.example.com +subnet=103.0.0.0/24

# 模拟美国客户端
dig @pdns-auth.dns.svc.cluster.local www.example.com +subnet=8.8.8.0/24

# 模拟欧洲客户端
dig @pdns-auth.dns.svc.cluster.local www.example.com +subnet=185.0.0.0/24
```

### 6.7 GeoIP 数据库更新

GeoIP 数据库更新由 `geoip-database` Chart 管理。如需在数据库更新后自动重启 PowerDNS Pod，可监听 `geoip-database-hash` ConfigMap 的变化，或使用 Reloader 等工具。

```bash
# 查看当前数据库 hash
kubectl get configmap geoip-database-hash -n kube-infra -o yaml
```

### 6.8 GeoDNS 性能调优

#### 6.8.1 关键配置

```yaml
config:
  performance:
    receiverThreads: 8          # = CPU 核心数
    reuseport: true             # 必须启用
  
  cache:
    ttl: 30                     # 响应缓存
    queryTtl: 20                # 查询缓存
  
  luaRecords:
    healthChecks:
      interval: 5               # 检查间隔
      expireDelay: 3600         # 结果缓存 1 小时
      maxConcurrent: 16         # 并发检查数
```

#### 6.8.2 性能预估

| 配置 | 单 Pod QPS | 说明 |
|------|-----------|------|
| 纯 geo 函数 | 30,000+ | country/continent 等 |
| 带 pickclosest | 25,000+ | 需要计算距离 |
| 带 ifportup (缓存) | 20,000+ | 健康检查结果已缓存 |
| 带 ifportup (无缓存) | <500 | 避免！每次查询都检查 |

#### 6.8.3 水平扩展

```yaml
autoscaling:
  hpa:
    enabled: true
    minReplicas: 3
    maxReplicas: 20
    targetCPU: 70
```

预估集群容量：`单 Pod QPS × 副本数 × 0.7`

---

## 7. 安全加固

### 6.1 安全上下文

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

### 6.2 NetworkPolicy

默认启用 NetworkPolicy：

```yaml
networkPolicy:
  enabled: true
  allowExternal: true
  allowExternalEgress: true
  
  # 限制入口流量来源
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
  
  # 限制出口流量
  extraEgress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: database
      ports:
        - port: 5432
          protocol: TCP
```

### 6.3 通过 Ingress 启用 TLS

```yaml
ingress:
  enabled: true
  className: nginx
  hostname: pdns-api.example.com
  path: /api
  tls: true
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
```

### 6.4 API 认证

```yaml
webserver:
  enabled: true
  apiKey: "your-secure-api-key-here"
  password: "your-webserver-password"
  allowFrom: "10.0.0.0/8"  # 限制 API 访问来源
```

---

## 8. 监控配置

### 7.1 启用 Prometheus 监控

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

### 7.2 重要指标

PowerDNS Auth 暴露的关键指标：

| 指标 | 描述 |
|------|------|
| `pdns_auth_queries` | 查询总数 |
| `pdns_auth_answers` | 响应总数 |
| `pdns_auth_cache_hits` | 缓存命中数 |
| `pdns_auth_cache_misses` | 缓存未命中数 |
| `pdns_auth_latency` | 查询延迟 |
| `pdns_auth_uptime` | 运行时间 |

### 7.3 Grafana Dashboard

推荐使用 PowerDNS 官方 Dashboard：
- Dashboard ID: 12688 (Grafana.com)

### 7.4 告警规则示例

```yaml
# prometheus-rules.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: pdns-auth-alerts
  namespace: monitoring
spec:
  groups:
    - name: pdns-auth
      rules:
        - alert: PowerDNSAuthDown
          expr: up{job="pdns-auth"} == 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "PowerDNS Auth is down"
            
        - alert: PowerDNSHighLatency
          expr: pdns_auth_latency_avg > 100
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "PowerDNS Auth high query latency"
            
        - alert: PowerDNSLowCacheHitRate
          expr: |
            pdns_auth_cache_hits / (pdns_auth_cache_hits + pdns_auth_cache_misses) < 0.8
          for: 15m
          labels:
            severity: warning
          annotations:
            summary: "PowerDNS Auth cache hit rate below 80%"
```

---

## 9. 常见问题

### 9.1 Pod 启动失败

**症状**: Pod 处于 CrashLoopBackOff 状态

**排查步骤**:

```bash
# 查看 Pod 日志
kubectl logs -n dns deploy/pdns-auth --previous

# 检查 db-init/db-sync Job 状态
kubectl get jobs -n dns
kubectl logs -n dns job/pdns-auth-db-init
kubectl logs -n dns job/pdns-auth-db-sync

# 检查数据库连接
kubectl exec -it deploy/pdns-auth -n dns -- \
  psql -h $DB_HOST -U pdns -d pdns -c "SELECT 1"
```

### 9.2 数据库连接失败

**症状**: db-init 或 db-sync Job 失败

**排查步骤**:

```bash
# 检查数据库服务是否可达
kubectl run db-test --rm -it --restart=Never --image=postgres:16-alpine -- \
  pg_isready -h postgresql.database.svc.cluster.local -p 5432

# 检查凭据是否正确
kubectl get secret pdns-db-credentials -n dns -o yaml

# 手动测试连接
kubectl run db-test --rm -it --restart=Never --image=postgres:16-alpine \
  --env="PGPASSWORD=your-password" -- \
  psql -h postgresql.database.svc.cluster.local -U pdns -d pdns -c "SELECT 1"
```

**常见原因**:
- 数据库主机名错误
- 密码不正确
- 网络策略阻止连接
- 数据库未就绪

### 9.3 DNS 查询无响应

**症状**: DNS 查询超时或无响应

**排查步骤**:

```bash
# 检查 Service 端点
kubectl get endpoints -n dns pdns-auth

# 检查 Pod 是否就绪
kubectl get pods -n dns -l app.kubernetes.io/name=powerdns-auth -o wide

# 测试 Pod 内部 DNS
kubectl exec -it deploy/pdns-auth -n dns -- \
  dig @127.0.0.1 -p 53 example.com

# 检查防火墙/NetworkPolicy
kubectl get networkpolicy -n dns
```

### 9.4 AXFR 传输失败

**症状**: Secondary 无法从 Primary 同步 Zone

**排查步骤**:

```bash
# 检查 Primary 配置
kubectl exec -it deploy/pdns-auth-primary -n dns -- \
  pdnsutil list-zone example.com

# 检查 TSIG 密钥
kubectl exec -it deploy/pdns-auth-primary -n dns -- \
  pdnsutil list-tsig-keys

# 手动测试 AXFR
kubectl exec -it deploy/pdns-auth-secondary -n dns -- \
  dig @pdns-auth-primary.dns.svc.cluster.local AXFR example.com

# 检查日志中的 AXFR 错误
kubectl logs -n dns deploy/pdns-auth-secondary | grep -i axfr
```

**常见原因**:
- TSIG 密钥不匹配
- allow-axfr-ips 未包含 Secondary IP
- NetworkPolicy 阻止 TCP 53 端口

### 9.5 API 无法访问

**症状**: 无法连接到 PowerDNS API

**排查步骤**:

```bash
# 检查 webserver 是否启用
kubectl exec -it deploy/pdns-auth -n dns -- cat /etc/pdns/pdns.conf | grep webserver

# 端口转发测试
kubectl port-forward -n dns svc/pdns-auth 8081:8081

# 测试 API
curl -v -H "X-API-Key: your-api-key" http://localhost:8081/api/v1/servers/localhost

# 检查日志
kubectl logs -n dns deploy/pdns-auth | grep -i api
```

### 9.6 GeoDNS 不生效

**症状**: LUA 记录返回相同结果，不区分地区

**排查步骤**:

```bash
# 检查 LUA 记录是否启用
kubectl exec -it deploy/pdns-auth -n dns -- cat /etc/pdns/pdns.conf | grep lua

# 检查 GeoIP 数据库是否存在
kubectl exec -it deploy/pdns-auth -n dns -- ls -la /usr/share/GeoIP/

# 检查 EDNS Client Subnet 是否启用
kubectl exec -it deploy/pdns-auth -n dns -- cat /etc/pdns/pdns.conf | grep edns

# 测试带 ECS 的查询
dig @pdns-auth.dns.svc.cluster.local www.example.com +subnet=103.0.0.0/24
dig @pdns-auth.dns.svc.cluster.local www.example.com +subnet=8.8.8.0/24

# 检查 LUA 记录内容
kubectl exec -it deploy/pdns-auth -n dns -- \
  psql -h $DB_HOST -U pdns -d pdns -c "SELECT name, content FROM records WHERE type='LUA'"
```

**常见原因**:
- `ednsSubnetProcessing` 未启用
- GeoIP 数据库未挂载或文件损坏
- LUA 记录语法错误
- 客户端未发送 EDNS Client Subnet

### 9.7 GeoIP 更新失败

**症状**: GeoIP 数据库未更新或 Pod 未重启

**排查步骤**:

```bash
# 检查 geoip-database chart 状态
kubectl get cronjob -n kube-infra | grep geoip

# 查看数据库文件
kubectl run -it --rm check-geoip -n kube-infra --image=busybox --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"check","image":"busybox","command":["ls","-lh","/data"],"volumeMounts":[{"name":"geoip","mountPath":"/data"}]}],"volumes":[{"name":"geoip","persistentVolumeClaim":{"claimName":"geoip-database-data"}}]}}'

# 检查 ConfigMap hash
kubectl get configmap geoip-database-hash -n kube-infra -o yaml
```

**常见原因**:
- geoip-database chart 未正确部署
- PVC 未正确挂载到 PowerDNS Pod
- 跨命名空间 PVC 访问问题

### 9.8 健康检查导致性能问题

**症状**: GeoDNS 查询延迟高，QPS 下降

**排查步骤**:

```bash
# 检查健康检查配置
kubectl exec -it deploy/pdns-auth -n dns -- cat /etc/pdns/pdns.conf | grep lua-health

# 查看后端健康状态
kubectl exec -it deploy/pdns-auth -n dns -- \
  curl -s http://localhost:8081/api/v1/servers/localhost/statistics | jq '.[] | select(.name | contains("lua"))'
```

**解决方案**:

```yaml
config:
  luaRecords:
    healthChecks:
      # 增加缓存时间 (关键！)
      expireDelay: 3600
      # 减少并发检查数
      maxConcurrent: 8
      # 增加检查间隔
      interval: 10
```

---

## 10. 升级与回滚

### 10.1 升级 Chart

```bash
# 查看当前版本
helm list -n dns

# 获取当前 values
helm get values pdns-auth -n dns > current-values.yaml

# 升级到新版本
helm upgrade pdns-auth ./powerdns-auth \
  -n dns \
  -f current-values.yaml \
  --set image.tag=5.0.3
```

### 10.2 滚动更新策略

Chart 默认使用 RollingUpdate 策略：

```yaml
updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1
    maxSurge: 1
```

### 10.3 回滚操作

```bash
# 查看历史版本
helm history pdns-auth -n dns

# 回滚到上一版本
helm rollback pdns-auth -n dns

# 回滚到指定版本
helm rollback pdns-auth 2 -n dns
```

### 10.4 数据库 Schema 升级

数据库 Schema 由 db-sync Job 管理，会在每次 Helm 升级时自动运行。

如需手动执行：

```bash
# 删除旧 Job
kubectl delete job pdns-auth-db-sync -n dns

# 重新部署触发 Job
helm upgrade pdns-auth ./powerdns-auth -n dns -f values.yaml
```

---

## 11. 卸载

### 11.1 卸载 Chart

```bash
helm uninstall pdns-auth -n dns
```

### 11.2 清理 PVC (如果使用持久化)

```bash
kubectl delete pvc -n dns -l app.kubernetes.io/name=powerdns-auth
```

### 11.3 清理 Secret

```bash
kubectl delete secret -n dns pdns-db-credentials
```

### 11.4 删除命名空间

```bash
kubectl delete namespace dns
```

### 11.5 注意事项

- 卸载 Chart 不会删除数据库中的数据
- 如需保留配置，先导出 values：`helm get values pdns-auth -n dns > backup-values.yaml`
- PVC 不会自动删除，需手动清理

---

## 附录

### A. 常用 pdnsutil 命令

```bash
# Zone 管理
pdnsutil create-zone example.com ns1.example.com
pdnsutil delete-zone example.com
pdnsutil list-zone example.com
pdnsutil list-all-zones

# 记录管理
pdnsutil add-record example.com www A 300 192.0.2.1
pdnsutil delete-rrset example.com www A
pdnsutil edit-zone example.com

# DNSSEC
pdnsutil secure-zone example.com
pdnsutil show-zone example.com
pdnsutil rectify-zone example.com

# TSIG
pdnsutil generate-tsig-key transfer-key hmac-sha256
pdnsutil list-tsig-keys
pdnsutil delete-tsig-key transfer-key
```

### B. API 常用操作

```bash
API_KEY="your-api-key"
API_URL="http://localhost:8081/api/v1"

# 获取服务器信息
curl -H "X-API-Key: $API_KEY" $API_URL/servers/localhost

# 列出所有 Zone
curl -H "X-API-Key: $API_KEY" $API_URL/servers/localhost/zones

# 创建 Zone
curl -X POST -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d '{"name":"example.com.","kind":"Native","nameservers":["ns1.example.com."]}' \
  $API_URL/servers/localhost/zones

# 添加记录
curl -X PATCH -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d '{"rrsets":[{"name":"www.example.com.","type":"A","ttl":300,"changetype":"REPLACE","records":[{"content":"192.0.2.1","disabled":false}]}]}' \
  $API_URL/servers/localhost/zones/example.com.
```

### C. 性能调优

#### C.1 基础性能配置

```yaml
config:
  performance:
    # 接收线程数 (建议 = CPU 核心数)
    receiverThreads: 8
    # 分发线程数 (通常 1-2 即可)
    distributorThreads: 2
    # DNSSEC 签名线程数
    signingThreads: 4
    # 启用端口复用 (多副本必须启用)
    reuseport: true
    # UDP 截断阈值 (IPv6 兼容性)
    udpTruncationThreshold: 1232
  
  cache:
    # 响应缓存 TTL
    ttl: 60
    # 负查询缓存 TTL
    negTtl: 120
    # 启用查询缓存
    queryEnabled: true
    # 查询缓存 TTL
    queryTtl: 20
  
  # TCP 优化
  tcpFastOpen: 128
  maxTcpConnections: 100

resources:
  requests:
    cpu: 1000m
    memory: 1Gi
  limits:
    cpu: 4000m
    memory: 2Gi
```

#### C.2 GeoDNS 性能配置

```yaml
config:
  luaRecords:
    enabled: true
    # EDNS Client Subnet 必须启用
    ednsSubnetProcessing: true
    # Lua 指令限制 (复杂脚本可增加)
    execLimit: 5000
    healthChecks:
      enabled: true
      # 检查间隔 (秒)
      interval: 5
      # 结果缓存时间 (秒) - 关键！
      expireDelay: 3600
      # 最大并发检查数
      maxConcurrent: 16
      # 检查超时 (毫秒)
      timeout: 2000
```

#### C.3 性能指标参考

| 场景 | 单 Pod QPS | 配置要点 |
|------|-----------|---------|
| 纯权威 DNS | 50,000+ | 缓存优化 |
| GeoDNS (纯 geo) | 30,000+ | EDNS 处理 |
| GeoDNS (健康检查) | 20,000+ | 缓存 expireDelay |
| DNSSEC 签名 | 10,000+ | 增加签名线程 |

#### C.4 调优检查清单

- [ ] `reuseport: true` 已启用
- [ ] `receiverThreads` >= CPU 核心数
- [ ] 缓存 TTL 根据业务需求设置
- [ ] GeoDNS 健康检查 `expireDelay` >= 60s
- [ ] 资源 limits 足够
- [ ] HPA 已配置
