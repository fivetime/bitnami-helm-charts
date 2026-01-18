# PowerDNS Authoritative Server 部署指南

本文档提供 PowerDNS Authoritative Server Helm Chart 的详细部署指南。

## 目录

1. [环境准备](#1-环境准备)
2. [数据库准备](#2-数据库准备)
3. [基础部署](#3-基础部署)
4. [高可用部署](#4-高可用部署)
5. [区域传输配置](#5-区域传输配置)
6. [安全加固](#6-安全加固)
7. [监控配置](#7-监控配置)
8. [常见问题](#8-常见问题)
9. [升级与回滚](#9-升级与回滚)
10. [卸载](#10-卸载)

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

## 6. 安全加固

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
  ingressClassName: nginx
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

## 7. 监控配置

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

## 8. 常见问题

### 8.1 Pod 启动失败

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

### 8.2 数据库连接失败

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

### 8.3 DNS 查询无响应

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

### 8.4 AXFR 传输失败

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

### 8.5 API 无法访问

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

---

## 9. 升级与回滚

### 9.1 升级 Chart

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

### 9.2 滚动更新策略

Chart 默认使用 RollingUpdate 策略：

```yaml
updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1
    maxSurge: 1
```

### 9.3 回滚操作

```bash
# 查看历史版本
helm history pdns-auth -n dns

# 回滚到上一版本
helm rollback pdns-auth -n dns

# 回滚到指定版本
helm rollback pdns-auth 2 -n dns
```

### 9.4 数据库 Schema 升级

数据库 Schema 由 db-sync Job 管理，会在每次 Helm 升级时自动运行。

如需手动执行：

```bash
# 删除旧 Job
kubectl delete job pdns-auth-db-sync -n dns

# 重新部署触发 Job
helm upgrade pdns-auth ./powerdns-auth -n dns -f values.yaml
```

---

## 10. 卸载

### 10.1 卸载 Chart

```bash
helm uninstall pdns-auth -n dns
```

### 10.2 清理 PVC (如果使用持久化)

```bash
kubectl delete pvc -n dns -l app.kubernetes.io/name=powerdns-auth
```

### 10.3 清理 Secret

```bash
kubectl delete secret -n dns pdns-db-credentials
```

### 10.4 删除命名空间

```bash
kubectl delete namespace dns
```

### 10.5 注意事项

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

```yaml
config:
  # 增加接收线程 (CPU 核心数)
  receiverThreads: 4
  
  # 增加缓存 TTL
  cacheTtl: 60
  negqueryCacheTtl: 120
  
  # TCP 优化
  tcpFastOpen: 128
  maxTcpConnections: 100
  
  # 启用端口复用
  reuseport: true

resources:
  requests:
    cpu: 1000m
    memory: 1Gi
  limits:
    cpu: 4000m
    memory: 2Gi
```
