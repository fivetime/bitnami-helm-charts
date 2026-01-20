# PowerDNS-Admin Helm Chart 部署指南

本文档提供 PowerDNS-Admin Helm Chart 的详细部署说明和最佳实践。

## 目录

- [快速开始](#快速开始)
- [部署架构](#部署架构)
- [部署前准备](#部署前准备)
- [部署场景](#部署场景)
- [生产环境部署](#生产环境部署)
- [高可用部署](#高可用部署)
- [安全加固](#安全加固)
- [监控与告警](#监控与告警)
- [备份与恢复](#备份与恢复)
- [升级与回滚](#升级与回滚)
- [故障排除](#故障排除)

---

## 快速开始

### 最小化部署（开发/测试环境）

```bash
# 添加依赖
helm dependency update

# 使用 SQLite（仅开发环境）
helm install powerdns-admin . \
  --namespace powerdns-admin \
  --create-namespace \
  --set powerdnsAdmin.secretKey="$(openssl rand -hex 32)" \
  --set database.type=sqlite
```

### 标准部署（使用外部 PostgreSQL）

```bash
# 生成密钥
export SECRET_KEY=$(openssl rand -hex 32)
export DB_PASSWORD=$(openssl rand -base64 24)

# 创建数据库 Secret
kubectl create namespace powerdns-admin
kubectl create secret generic powerdns-admin-db \
  --namespace powerdns-admin \
  --from-literal=password="${DB_PASSWORD}"

# 部署
helm install powerdns-admin . \
  --namespace powerdns-admin \
  --set powerdnsAdmin.secretKey="${SECRET_KEY}" \
  --set externalDatabase.host=postgresql.database.svc.cluster.local \
  --set externalDatabase.existingSecret=powerdns-admin-db
```

---

## 部署架构

### 单副本架构（开发/测试）

```
┌─────────────────────────────────────────────────────┐
│                    Kubernetes Cluster               │
│  ┌───────────────────────────────────────────────┐  │
│  │              Namespace: powerdns-admin        │  │
│  │                                               │  │
│  │  ┌─────────────┐      ┌─────────────────┐    │  │
│  │  │   Service   │──────│  Pod (PDA)      │    │  │
│  │  │  ClusterIP  │      │  - Gunicorn     │    │  │
│  │  └─────────────┘      │  - Flask App    │    │  │
│  │                       └────────┬────────┘    │  │
│  │                                │             │  │
│  │                       ┌────────▼────────┐    │  │
│  │                       │      PVC        │    │  │
│  │                       │  (SQLite/Data)  │    │  │
│  │                       └─────────────────┘    │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### 高可用架构（生产环境）

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster                           │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────────┐  │
│  │                    Namespace: powerdns-admin                   │  │
│  │                                                                │  │
│  │  ┌─────────────┐                                               │  │
│  │  │   Ingress   │  (TLS termination)                            │  │
│  │  └──────┬──────┘                                               │  │
│  │         │                                                      │  │
│  │  ┌──────▼──────┐                                               │  │
│  │  │   Service   │                                               │  │
│  │  │  ClusterIP  │                                               │  │
│  │  └──────┬──────┘                                               │  │
│  │         │                                                      │  │
│  │  ┌──────┴──────────────────┬───────────────────┐               │  │
│  │  │                         │                   │               │  │
│  │  ▼                         ▼                   ▼               │  │
│  │ ┌───────────┐        ┌───────────┐       ┌───────────┐         │  │
│  │ │  Pod #1   │        │  Pod #2   │       │  Pod #3   │         │  │
│  │ │ (PDA)     │        │ (PDA)     │       │ (PDA)     │         │  │
│  │ └─────┬─────┘        └─────┬─────┘       └─────┬─────┘         │  │
│  │       │                    │                   │               │  │
│  │       └────────────────────┼───────────────────┘               │  │
│  │                            │                                   │  │
│  │                    ┌───────▼───────┐                           │  │
│  │                    │  PostgreSQL   │  (External HA Database)   │  │
│  │                    │  Cluster      │                           │  │
│  │                    └───────────────┘                           │  │
│  │                                                                │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌────────────────┐  │  │
│  │  │ ServiceMonitor  │  │  NetworkPolicy  │  │      HPA       │  │  │
│  │  │ (Prometheus)    │  │  (Security)     │  │  (Autoscale)   │  │  │
│  │  └─────────────────┘  └─────────────────┘  └────────────────┘  │  │
│  └────────────────────────────────────────────────────────────────┘  │
│                                                                      │
│                    ┌───────────────────────────┐                     │
│                    │      PowerDNS Auth        │                     │
│                    │      (DNS Server)         │                     │
│                    └───────────────────────────┘                     │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 部署前准备

### 1. 环境要求

| 组件 | 最低版本 | 推荐版本 |
|------|----------|----------|
| Kubernetes | 1.23+ | 1.28+ |
| Helm | 3.8+ | 3.14+ |
| kubectl | 1.23+ | 1.28+ |

### 2. 资源规划

| 环境 | CPU Request | CPU Limit | Memory Request | Memory Limit | 副本数 |
|------|-------------|-----------|----------------|--------------|--------|
| 开发 | 100m | 500m | 128Mi | 512Mi | 1 |
| 测试 | 250m | 1000m | 256Mi | 1Gi | 2 |
| 生产 | 500m | 2000m | 512Mi | 2Gi | 3+ |

### 3. 生成必要的密钥

```bash
# Flask SECRET_KEY（必需，用于会话加密）
export SECRET_KEY=$(openssl rand -hex 32)

# 密码哈希 SALT（可选，建议设置）
export SALT=$(openssl rand -hex 16)

# 数据库密码
export DB_PASSWORD=$(openssl rand -base64 24)

# PowerDNS API 密钥（如需集成）
export PDNS_API_KEY=$(openssl rand -hex 32)
```

### 4. 创建命名空间和 Secrets

```bash
# 创建命名空间
kubectl create namespace powerdns-admin

# 创建应用 Secret
kubectl create secret generic powerdns-admin-secret \
  --namespace powerdns-admin \
  --from-literal=secret-key="${SECRET_KEY}" \
  --from-literal=salt="${SALT}"

# 创建数据库 Secret
kubectl create secret generic powerdns-admin-db \
  --namespace powerdns-admin \
  --from-literal=password="${DB_PASSWORD}"

# 创建 PowerDNS API Secret（如需要）
kubectl create secret generic powerdns-api \
  --namespace powerdns-admin \
  --from-literal=api-key="${PDNS_API_KEY}"
```

---

## 部署场景

### 场景 1: 开发环境（SQLite）

```yaml
# values-dev.yaml
powerdnsAdmin:
  secretKey: "dev-secret-key-change-in-production"
  signupEnabled: true

database:
  type: sqlite

sqlite:
  path: "/data/powerdns-admin.db"

persistence:
  enabled: true
  size: 1Gi

replicaCount: 1

resourcesPreset: "small"

ingress:
  enabled: true
  hostname: pdns-admin.dev.local
```

```bash
helm install powerdns-admin . -f values-dev.yaml --namespace powerdns-admin
```

### 场景 2: 测试环境（PostgreSQL）

```yaml
# values-test.yaml
powerdnsAdmin:
  existingSecret: "powerdns-admin-secret"
  signupEnabled: false

database:
  type: postgresql

externalDatabase:
  host: "postgresql.database.svc.cluster.local"
  port: 5432
  database: "powerdns_admin_test"
  username: "powerdns_admin"
  existingSecret: "powerdns-admin-db"

replicaCount: 2

resourcesPreset: "medium"

ingress:
  enabled: true
  hostname: pdns-admin.test.example.com
  tls: true
  className: nginx
```

```bash
helm install powerdns-admin . -f values-test.yaml --namespace powerdns-admin
```

### 场景 3: 生产环境（完整配置）

```yaml
# values-prod.yaml
powerdnsAdmin:
  existingSecret: "powerdns-admin-secret"
  signupEnabled: false
  sessionCookieSecure: true
  csrfCookieSecure: true

database:
  type: postgresql

externalDatabase:
  host: "postgresql-primary.database.svc.cluster.local"
  port: 5432
  database: "powerdns_admin"
  username: "powerdns_admin"
  existingSecret: "powerdns-admin-db"

powerdnsApi:
  enabled: true
  url: "http://powerdns-auth.dns.svc.cluster.local:8081"
  existingSecret: "powerdns-api"

replicaCount: 3

resourcesPreset: "large"

# 或者自定义资源
# resources:
#   requests:
#     cpu: 500m
#     memory: 512Mi
#   limits:
#     cpu: 2000m
#     memory: 2Gi

ingress:
  enabled: true
  hostname: dns-admin.example.com
  tls: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/ssl-redirect: "true"

autoscaling:
  hpa:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPU: 70
    targetMemory: 80

pdb:
  create: true
  minAvailable: 2

networkPolicy:
  enabled: true
  allowExternal: true

metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s
  grafana:
    enabled: true

backup:
  enabled: true
  schedule: "0 2 * * *"
  retention: 30
```

```bash
helm install powerdns-admin . -f values-prod.yaml --namespace powerdns-admin
```

---

## 生产环境部署

### 部署检查清单

- [ ] **密钥管理**
  - [ ] 使用 existingSecret 而非明文密码
  - [ ] SECRET_KEY 使用足够强度的随机值（至少 32 字节）
  - [ ] 定期轮换敏感凭据

- [ ] **数据库**
  - [ ] 使用外部托管的 PostgreSQL/MySQL
  - [ ] 数据库启用 SSL/TLS 连接
  - [ ] 配置数据库连接池
  - [ ] 设置适当的连接超时

- [ ] **网络安全**
  - [ ] 启用 NetworkPolicy
  - [ ] 配置 Ingress TLS
  - [ ] 设置 HTTPS 重定向
  - [ ] 配置 CORS（如需要）

- [ ] **资源配置**
  - [ ] 设置适当的 CPU/内存请求和限制
  - [ ] 配置 HPA 自动扩缩
  - [ ] 设置 PDB 确保高可用

- [ ] **监控告警**
  - [ ] 启用 Prometheus 指标
  - [ ] 配置 ServiceMonitor
  - [ ] 设置告警规则
  - [ ] 部署 Grafana Dashboard

- [ ] **备份恢复**
  - [ ] 启用定期备份
  - [ ] 验证备份恢复流程
  - [ ] 配置备份存储（S3 或 PVC）

### 生产部署命令

```bash
# 1. 验证配置
helm template powerdns-admin . -f values-prod.yaml --namespace powerdns-admin | kubectl apply --dry-run=client -f -

# 2. 部署
helm install powerdns-admin . \
  -f values-prod.yaml \
  --namespace powerdns-admin \
  --create-namespace \
  --wait \
  --timeout 10m

# 3. 验证部署
kubectl get pods -n powerdns-admin
kubectl get svc -n powerdns-admin
kubectl get ingress -n powerdns-admin

# 4. 检查应用健康
kubectl exec -it deploy/powerdns-admin -n powerdns-admin -- curl -s localhost:9191/health
```

---

## 高可用部署

### HPA 配置

```yaml
autoscaling:
  hpa:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
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
        selectPolicy: Max
        policies:
          - type: Percent
            value: 100
            periodSeconds: 15
          - type: Pods
            value: 4
            periodSeconds: 15
```

### Pod 反亲和性配置

```yaml
podAntiAffinityPreset: hard

# 或者自定义亲和性
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: powerdns-admin
        topologyKey: kubernetes.io/hostname
```

### 拓扑分布约束

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: powerdns-admin
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: powerdns-admin
```

### PDB 配置

```yaml
pdb:
  create: true
  minAvailable: 2
  # 或者使用 maxUnavailable
  # maxUnavailable: 1
```

---

## 安全加固

### 1. Pod 安全配置

```yaml
podSecurityContext:
  enabled: true
  fsGroup: 1001
  fsGroupChangePolicy: "OnRootMismatch"
  sysctls: []

containerSecurityContext:
  enabled: true
  runAsUser: 1001
  runAsGroup: 1001
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: false
  privileged: false
  capabilities:
    drop:
      - ALL
  seccompProfile:
    type: RuntimeDefault
```

### 2. NetworkPolicy 配置

```yaml
networkPolicy:
  enabled: true
  allowExternal: true
  allowExternalEgress: true
  
  # 自定义入站规则
  ingressRules:
    customRules:
      - from:
          - namespaceSelector:
              matchLabels:
                name: ingress-nginx
        ports:
          - port: 9191
            protocol: TCP

  # 自定义出站规则
  egressRules:
    customRules:
      - to:
          - namespaceSelector:
              matchLabels:
                name: database
        ports:
          - port: 5432
            protocol: TCP
```

### 3. HTTPS 强制配置

```yaml
powerdnsAdmin:
  sessionCookieSecure: true
  csrfCookieSecure: true
  hstsEnabled: true

ingress:
  enabled: true
  tls: true
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
```

### 4. 认证配置（LDAP 示例）

```yaml
auth:
  local:
    enabled: false  # 禁用本地认证
  
  ldap:
    enabled: true
    type: "ldap"
    uri: "ldaps://ldap.example.com:636"
    baseDn: "dc=example,dc=com"
    adminUsername: "cn=readonly,dc=example,dc=com"
    existingSecret: "ldap-credentials"
    userFilter: "(uid={0})"
    groupDn: "ou=groups,dc=example,dc=com"
    sgEnabled: true

  twoFactor:
    enabled: true
    issuerName: "PowerDNS-Admin"
```

---

## 监控与告警

### Prometheus 监控配置

```yaml
metrics:
  enabled: true
  port: 9191
  path: /metrics

  serviceMonitor:
    enabled: true
    namespace: monitoring
    interval: 30s
    scrapeTimeout: 10s
    labels:
      release: prometheus

  prometheusRule:
    enabled: true
    namespace: monitoring
    labels:
      release: prometheus
    rules:
      - alert: PowerDNSAdminDown
        expr: up{job="powerdns-admin"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "PowerDNS-Admin is down"
          description: "PowerDNS-Admin has been down for more than 5 minutes."
      
      - alert: PowerDNSAdminHighErrorRate
        expr: rate(flask_http_request_total{status=~"5.."}[5m]) > 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High error rate in PowerDNS-Admin"
          description: "Error rate is above 10% for the last 5 minutes."

  grafana:
    enabled: true
    namespace: monitoring
    labels:
      grafana_dashboard: "1"
```

### Grafana Dashboard

部署后，Grafana 会自动发现并加载 Dashboard。主要监控指标：

- 请求速率和延迟
- 错误率
- 活跃用户数
- 数据库连接状态
- 资源使用情况

---

## 备份与恢复

### 启用自动备份

```yaml
backup:
  enabled: true
  schedule: "0 2 * * *"  # 每天凌晨 2 点
  retention: 30          # 保留 30 天
  
  image:
    registry: docker.io
    repository: postgres
    tag: "16-alpine"
  
  resources:
    limits:
      cpu: 500m
      memory: 256Mi
    requests:
      cpu: 100m
      memory: 128Mi
  
  storage:
    type: pvc
    pvc:
      size: 10Gi
      storageClass: "standard"
```

### S3 备份配置

```yaml
backup:
  enabled: true
  schedule: "0 2 * * *"
  retention: 30
  
  storage:
    type: s3
    s3:
      bucket: "powerdns-admin-backups"
      endpoint: "https://s3.amazonaws.com"
      region: "us-west-2"
      existingSecret: "s3-credentials"
```

### 手动备份

```bash
# 创建手动备份 Job
kubectl create job --from=cronjob/powerdns-admin-backup manual-backup-$(date +%Y%m%d) -n powerdns-admin

# 查看备份状态
kubectl get jobs -n powerdns-admin

# 查看备份日志
kubectl logs job/manual-backup-$(date +%Y%m%d) -n powerdns-admin
```

### 恢复流程

```bash
# 1. 列出可用备份
kubectl exec -it deploy/powerdns-admin -n powerdns-admin -- ls -la /backups/

# 2. 恢复数据库（PostgreSQL 示例）
kubectl exec -it deploy/powerdns-admin -n powerdns-admin -- \
  pg_restore -h $DB_HOST -U $DB_USER -d $DB_NAME /backups/backup-20240101.sql

# 3. 重启应用
kubectl rollout restart deployment/powerdns-admin -n powerdns-admin
```

---

## 升级与回滚

### 升级 Chart

```bash
# 1. 获取当前版本
helm list -n powerdns-admin

# 2. 查看变更
helm diff upgrade powerdns-admin . -f values-prod.yaml -n powerdns-admin

# 3. 执行升级
helm upgrade powerdns-admin . \
  -f values-prod.yaml \
  --namespace powerdns-admin \
  --wait \
  --timeout 10m

# 4. 验证升级
kubectl rollout status deployment/powerdns-admin -n powerdns-admin
```

### 回滚

```bash
# 查看历史版本
helm history powerdns-admin -n powerdns-admin

# 回滚到上一版本
helm rollback powerdns-admin -n powerdns-admin

# 回滚到指定版本
helm rollback powerdns-admin 3 -n powerdns-admin
```

### 金丝雀发布

```bash
# 使用 --set 覆盖部分配置进行测试
helm upgrade powerdns-admin . \
  -f values-prod.yaml \
  --namespace powerdns-admin \
  --set replicaCount=1 \
  --set image.tag=v0.4.3-rc1 \
  --wait
```

---

## 故障排除

### 常见问题

#### 1. Pod 启动失败

```bash
# 查看 Pod 状态
kubectl describe pod -l app.kubernetes.io/name=powerdns-admin -n powerdns-admin

# 查看日志
kubectl logs -l app.kubernetes.io/name=powerdns-admin -n powerdns-admin --tail=100

# 检查 Init Container
kubectl logs -l app.kubernetes.io/name=powerdns-admin -n powerdns-admin -c wait-for-db
```

#### 2. 数据库连接失败

```bash
# 测试数据库连接
kubectl run -it --rm debug --image=postgres:16-alpine --restart=Never -n powerdns-admin -- \
  psql -h postgresql.database.svc.cluster.local -U powerdns_admin -d powerdns_admin -c "SELECT 1"

# 检查 Secret
kubectl get secret powerdns-admin-db -n powerdns-admin -o jsonpath='{.data.password}' | base64 -d
```

#### 3. Ingress 无法访问

```bash
# 检查 Ingress 配置
kubectl describe ingress powerdns-admin -n powerdns-admin

# 检查证书
kubectl get certificate -n powerdns-admin

# 测试后端服务
kubectl port-forward svc/powerdns-admin 9191:80 -n powerdns-admin
curl http://localhost:9191/
```

#### 4. 认证失败

```bash
# 检查 LDAP 连接
kubectl exec -it deploy/powerdns-admin -n powerdns-admin -- \
  ldapsearch -x -H ldaps://ldap.example.com:636 -D "cn=admin,dc=example,dc=com" -W -b "dc=example,dc=com"

# 检查 OAuth 配置
kubectl get secret -n powerdns-admin -o yaml | grep -A5 oauth
```

### 调试模式

```yaml
# 启用诊断模式
diagnosticMode:
  enabled: true
  command: ["sleep"]
  args: ["infinity"]
```

```bash
# 部署诊断模式
helm upgrade powerdns-admin . --set diagnosticMode.enabled=true -n powerdns-admin

# 进入容器调试
kubectl exec -it deploy/powerdns-admin -n powerdns-admin -- /bin/bash
```

### 日志级别调整

```yaml
powerdnsAdmin:
  logLevel: "DEBUG"  # DEBUG, INFO, WARNING, ERROR, CRITICAL
```

---

## 附录

### 环境变量参考

| 变量 | 描述 | 必需 |
|------|------|------|
| `SECRET_KEY` | Flask 会话密钥 | 是 |
| `SALT` | 密码哈希盐值 | 否 |
| `SQLALCHEMY_DATABASE_URI` | 数据库连接字符串 | 是 |
| `PDNS_API_URL` | PowerDNS API URL | 否 |
| `PDNS_API_KEY` | PowerDNS API 密钥 | 否 |

### 端口参考

| 端口 | 用途 |
|------|------|
| 9191 | HTTP 服务 |
| 9191 | Prometheus 指标 |

### 健康检查端点

| 端点 | 用途 |
|------|------|
| `/` | Liveness/Readiness 检查 |
| `/health` | 健康状态（如配置） |
| `/metrics` | Prometheus 指标 |

---

## 许可证

本 Helm Chart 基于 Apache 2.0 许可证发布。
