# Citus Helm Chart 部署指南

本文档提供 Citus 分布式 PostgreSQL 集群的详细部署方案和最佳实践。

## 目录

- [前提条件](#前提条件)
- [部署场景](#部署场景)
  - [开发环境](#开发环境)
  - [生产环境](#生产环境)
  - [高可用部署](#高可用部署)
- [存储配置](#存储配置)
- [网络配置](#网络配置)
- [监控配置](#监控配置)
- [备份与恢复](#备份与恢复)
- [扩缩容操作](#扩缩容操作)
- [升级指南](#升级指南)
- [故障排除](#故障排除)

---

## 前提条件

### 集群要求

| 组件 | 最低版本 | 推荐版本 |
|------|----------|----------|
| Kubernetes | 1.23+ | 1.28+ |
| Helm | 3.8.0+ | 3.14+ |
| kubectl | 1.23+ | 与集群版本匹配 |

### 资源要求

**最小配置（开发/测试）：**
- Coordinator: 1 CPU, 2Gi 内存, 10Gi 存储
- Worker (x3): 每个 1 CPU, 2Gi 内存, 20Gi 存储

**推荐配置（生产）：**
- Coordinator: 4 CPU, 8Gi 内存, 100Gi SSD
- Worker (x5+): 每个 8 CPU, 16Gi 内存, 500Gi SSD

### 依赖组件

```bash
# 检查 Kubernetes 版本
kubectl version

# 检查存储类
kubectl get storageclass

# 检查是否有默认存储类
kubectl get storageclass -o=jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}'
```

---

## 部署场景

### 开发环境

适用于本地开发、功能测试。

```yaml
# values-dev.yaml
auth:
  postgresPassword: "devpassword"
  username: "developer"
  password: "devuserpass"
  database: "devdb"

coordinator:
  replicaCount: 1
  resourcesPreset: "small"  # 500m CPU, 512Mi 内存
  persistence:
    enabled: true
    size: 5Gi

worker:
  replicaCount: 2
  resourcesPreset: "small"
  persistence:
    enabled: true
    size: 10Gi
  pdb:
    create: false  # 开发环境可禁用

# 禁用生产特性
metrics:
  enabled: false

networkPolicy:
  enabled: false

backup:
  enabled: false
```

**部署命令：**

```bash
# 创建命名空间
kubectl create namespace citus-dev

# 部署
helm install citus-dev ./citus \
  --namespace citus-dev \
  -f values-dev.yaml

# 验证
kubectl get pods -n citus-dev -w
```

### 生产环境

适用于生产工作负载，包含完整的监控和备份。

```yaml
# values-prod.yaml
global:
  storageClass: "fast-ssd"  # 使用 SSD 存储类

auth:
  postgresPassword: ""  # 留空，使用 existingSecret
  existingSecret: "citus-credentials"
  secretKeys:
    adminPasswordKey: "postgres-password"
    userPasswordKey: "user-password"

image:
  tag: "13.0.3"
  pullPolicy: Always

coordinator:
  replicaCount: 1
  resourcesPreset: "large"  # 2 CPU, 2Gi 内存
  
  persistence:
    enabled: true
    storageClass: "fast-ssd"
    size: 100Gi
  
  podAntiAffinityPreset: hard
  
  # PDB 默认已启用 (minAvailable: 1)
  
  # 生产环境启用启动探针
  startupProbe:
    enabled: true
    initialDelaySeconds: 30
    periodSeconds: 10
    failureThreshold: 30

worker:
  replicaCount: 5
  resourcesPreset: "xlarge"  # 4 CPU, 4Gi 内存
  
  persistence:
    enabled: true
    storageClass: "fast-ssd"
    size: 500Gi
  
  podAntiAffinityPreset: hard
  
  # 跨可用区分布
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app.kubernetes.io/component: worker
  
  # PDB 默认已启用 (maxUnavailable: 1)
  
  startupProbe:
    enabled: true
    initialDelaySeconds: 30
    periodSeconds: 10
    failureThreshold: 30

# 启用监控
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    namespace: monitoring
    labels:
      release: prometheus
    interval: 30s

# 启用网络策略
networkPolicy:
  enabled: true
  allowExternal: true

# 启用备份
backup:
  enabled: true
  schedule: "0 2 * * *"  # 每天凌晨 2 点
  persistence:
    enabled: true
    storageClass: "standard"  # 备份可使用普通存储
    size: 200Gi
  retentionDays: 14
```

**创建 Secret：**

```bash
# 创建命名空间
kubectl create namespace citus-prod

# 创建凭据 Secret
kubectl create secret generic citus-credentials \
  --namespace citus-prod \
  --from-literal=postgres-password="$(openssl rand -base64 32)" \
  --from-literal=user-password="$(openssl rand -base64 24)"

# 查看生成的密码（可选）
kubectl get secret citus-credentials -n citus-prod -o jsonpath='{.data.postgres-password}' | base64 -d
```

**部署命令：**

```bash
helm install citus-prod ./citus \
  --namespace citus-prod \
  -f values-prod.yaml \
  --wait \
  --timeout 10m
```

### 高可用部署

适用于对可用性要求极高的场景。

```yaml
# values-ha.yaml
global:
  storageClass: "fast-ssd-replicated"  # 使用带复制的存储类

auth:
  existingSecret: "citus-credentials"

postgresql:
  maxConnections: 500
  citusShardCount: 64
  citusShardReplicationFactor: 2  # 分片复制因子

coordinator:
  replicaCount: 1
  
  resources:
    requests:
      cpu: 4
      memory: 8Gi
    limits:
      cpu: 8
      memory: 16Gi
  
  persistence:
    enabled: true
    size: 200Gi
  
  podAntiAffinityPreset: hard
  
  # 节点选择器 - 使用专用节点
  nodeSelector:
    node-role.kubernetes.io/citus: "coordinator"
  
  tolerations:
    - key: "dedicated"
      operator: "Equal"
      value: "citus"
      effect: "NoSchedule"
  
  # PDB 默认已启用 (minAvailable: 1)
  
  # VPA 自动调整资源
  vpa:
    enabled: true
    updateMode: "Initial"
    minAllowed:
      cpu: 2
      memory: 4Gi
    maxAllowed:
      cpu: 16
      memory: 32Gi

worker:
  replicaCount: 7
  
  resources:
    requests:
      cpu: 8
      memory: 16Gi
    limits:
      cpu: 16
      memory: 32Gi
  
  persistence:
    enabled: true
    size: 1Ti
  
  podAntiAffinityPreset: hard
  
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app.kubernetes.io/component: worker
    - maxSkew: 2
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: ScheduleAnyway
      labelSelector:
        matchLabels:
          app.kubernetes.io/component: worker
  
  nodeSelector:
    node-role.kubernetes.io/citus: "worker"
  
  tolerations:
    - key: "dedicated"
      operator: "Equal"
      value: "citus"
      effect: "NoSchedule"
  
  # PDB 默认已启用 (maxUnavailable: 1)
  
  # HPA 自动水平扩展
  autoscaling:
    enabled: true
    minReplicas: 7
    maxReplicas: 20
    targetCPU: 70
    targetMemory: 80
  
  # VPA 自动垂直扩展（与 HPA 配合使用 Initial 模式）
  vpa:
    enabled: true
    updateMode: "Initial"
    minAllowed:
      cpu: 4
      memory: 8Gi
    maxAllowed:
      cpu: 32
      memory: 64Gi

metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 15s
  prometheusRule:
    enabled: true
    rules:
      - alert: CitusCoordinatorDown
        expr: up{job=~".*citus.*coordinator.*"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Citus Coordinator 节点宕机"
          description: "Coordinator 已不可用超过 1 分钟"
      
      - alert: CitusWorkerDown
        expr: up{job=~".*citus.*worker.*"} == 0
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Citus Worker 节点宕机"
          description: "Worker {{ $labels.pod }} 已不可用超过 2 分钟"
      
      - alert: CitusHighConnectionUsage
        expr: pg_stat_activity_count / pg_settings_max_connections > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL 连接使用率过高"
          description: "连接使用率超过 80%"
      
      - alert: CitusReplicationLag
        expr: pg_replication_lag > 300
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Citus 复制延迟过高"
          description: "复制延迟超过 5 分钟"

networkPolicy:
  enabled: true
  allowExternal: true

backup:
  enabled: true
  schedule: "0 */6 * * *"  # 每 6 小时备份一次
  persistence:
    size: 500Gi
  retentionDays: 30
```

---

## 存储配置

### 推荐的存储类

**AWS EKS：**
```yaml
# gp3-ssd-storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "6000"
  throughput: "500"
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain
```

**GKE：**
```yaml
# ssd-storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-ssd
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: Retain
```

**本地 NVMe（使用 local-path-provisioner）：**
```yaml
# 适用于裸金属或自建集群
coordinator:
  persistence:
    storageClass: "local-path"
  nodeSelector:
    kubernetes.io/hostname: "node-with-nvme"
```

### 存储扩容

```bash
# 1. 编辑 PVC（如果存储类支持扩容）
kubectl patch pvc data-citus-worker-0 -n citus-prod \
  -p '{"spec":{"resources":{"requests":{"storage":"1Ti"}}}}'

# 2. 或者通过 Helm 升级
helm upgrade citus-prod ./citus \
  --namespace citus-prod \
  --set worker.persistence.size=1Ti \
  --reuse-values
```

---

## 网络配置

### 外部访问

**方式 1：LoadBalancer（云环境）**

```yaml
coordinator:
  service:
    type: LoadBalancer
    annotations:
      # AWS NLB
      service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
      service.beta.kubernetes.io/aws-load-balancer-internal: "true"
```

**方式 2：NodePort**

```yaml
coordinator:
  service:
    type: NodePort
    nodePorts:
      postgresql: 30432
```

**方式 3：Port Forward（临时访问）**

```bash
kubectl port-forward svc/citus-coordinator 5432:5432 -n citus-prod
```

### 网络策略示例

```yaml
networkPolicy:
  enabled: true
  allowExternal: false  # 禁止外部访问
  
  # 只允许特定命名空间的 Pod 访问
  ingressNSMatchLabels:
    app.kubernetes.io/name: my-application
  
  # 额外入口规则
  extraIngress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: application-ns
        - podSelector:
            matchLabels:
              app: backend
      ports:
        - protocol: TCP
          port: 5432
```

---

## 监控配置

### Prometheus + Grafana

**1. 安装 kube-prometheus-stack（如果没有）：**

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace
```

**2. 启用 Citus 监控：**

```yaml
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    namespace: monitoring
    labels:
      release: prometheus  # 匹配 Prometheus Operator 的 serviceMonitorSelector
    interval: 30s
    scrapeTimeout: 10s
```

**3. 导入 Grafana Dashboard：**

推荐使用以下 Dashboard：
- PostgreSQL Database (ID: 9628)
- PostgreSQL Overview (ID: 455)

### 关键指标

| 指标 | 描述 | 告警阈值 |
|------|------|----------|
| `pg_up` | 数据库是否可用 | == 0 |
| `pg_stat_activity_count` | 活跃连接数 | > 80% max_connections |
| `pg_stat_database_tup_fetched` | 读取行数 | 取决于基线 |
| `pg_stat_database_tup_inserted` | 插入行数 | 取决于基线 |
| `pg_replication_lag` | 复制延迟（秒） | > 300 |
| `pg_database_size_bytes` | 数据库大小 | 取决于存储容量 |

### 告警规则示例

```yaml
metrics:
  prometheusRule:
    enabled: true
    rules:
      - alert: CitusClusterUnhealthy
        expr: |
          count(up{job=~".*citus.*worker.*"} == 1) < 3
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Citus 集群健康 Worker 少于 3 个"
      
      - alert: CitusHighDiskUsage
        expr: |
          (pg_database_size_bytes / on(pod) group_left() 
           kubelet_volume_stats_capacity_bytes{namespace="citus-prod"}) > 0.85
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "磁盘使用率超过 85%"
```

---

## 备份与恢复

### 自动备份

```yaml
backup:
  enabled: true
  schedule: "0 2 * * *"  # 每天凌晨 2 点
  persistence:
    enabled: true
    size: 200Gi
  retentionDays: 14
  
  # 自定义资源
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 2
      memory: 2Gi
```

### 手动备份

```bash
# 创建备份 Job
kubectl create job --from=cronjob/citus-backup manual-backup-$(date +%Y%m%d) -n citus-prod

# 查看备份状态
kubectl logs -f job/manual-backup-$(date +%Y%m%d) -n citus-prod
```

### 恢复流程

**1. 停止应用写入**

```bash
# 可选：缩容应用
kubectl scale deployment my-app --replicas=0 -n app-ns
```

**2. 恢复 Coordinator**

```bash
# 获取备份文件
BACKUP_POD=$(kubectl get pods -n citus-prod -l app.kubernetes.io/component=backup -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $BACKUP_POD -n citus-prod -- ls -la /backups/

# 恢复（需要停止 Coordinator）
kubectl scale statefulset citus-coordinator --replicas=0 -n citus-prod

# 复制备份到新 PVC 或使用 pg_restore
# ...

kubectl scale statefulset citus-coordinator --replicas=1 -n citus-prod
```

**3. 重新平衡分片**

```bash
kubectl exec -it citus-coordinator-0 -n citus-prod -- \
  psql -U postgres -d citus -c "SELECT rebalance_table_shards();"
```

### 跨区域备份

```yaml
# 使用外部存储（如 S3）
backup:
  enabled: true
  # 自定义备份脚本，上传到 S3
  # 参考 extraVolumes 和 extraVolumeMounts 挂载 AWS 凭据
```

---

## 扩缩容操作

### 水平扩展 Worker

**方式 1：手动扩展**

```bash
# 扩展到 7 个 Worker
kubectl scale statefulset citus-worker -n citus-prod --replicas=7

# 等待新 Worker 就绪
kubectl rollout status statefulset/citus-worker -n citus-prod

# 重新运行注册 Job（如果需要）
kubectl delete job citus-worker-registration -n citus-prod
helm upgrade citus-prod ./citus --namespace citus-prod --reuse-values
```

**方式 2：HPA 自动扩展**

```yaml
worker:
  autoscaling:
    enabled: true
    minReplicas: 5
    maxReplicas: 20
    targetCPU: 70
    targetMemory: 80
```

### 重新平衡分片

扩展后需要重新平衡数据：

```bash
# 连接到 Coordinator
kubectl exec -it citus-coordinator-0 -n citus-prod -- psql -U postgres -d citus

-- 查看当前分片分布
SELECT nodename, count(*) as shard_count 
FROM pg_dist_shard_placement 
GROUP BY nodename 
ORDER BY shard_count DESC;

-- 重新平衡（在线操作，但会消耗资源）
SELECT rebalance_table_shards();

-- 查看重新平衡进度
SELECT * FROM get_rebalance_progress();
```

### 垂直扩展（VPA）

```yaml
coordinator:
  vpa:
    enabled: true
    updateMode: "Auto"  # 或 "Initial" 更保守
    minAllowed:
      cpu: 1
      memory: 2Gi
    maxAllowed:
      cpu: 8
      memory: 16Gi

worker:
  vpa:
    enabled: true
    updateMode: "Initial"  # 与 HPA 配合时推荐
    minAllowed:
      cpu: 2
      memory: 4Gi
    maxAllowed:
      cpu: 16
      memory: 32Gi
```

---

## 升级指南

### Chart 升级

```bash
# 1. 查看变更
helm diff upgrade citus-prod ./citus \
  --namespace citus-prod \
  -f values-prod.yaml

# 2. 执行升级
helm upgrade citus-prod ./citus \
  --namespace citus-prod \
  -f values-prod.yaml \
  --wait \
  --timeout 15m

# 3. 验证
kubectl rollout status statefulset/citus-coordinator -n citus-prod
kubectl rollout status statefulset/citus-worker -n citus-prod
```

### Citus 版本升级

**小版本升级（如 13.0.2 -> 13.0.3）：**

```bash
helm upgrade citus-prod ./citus \
  --namespace citus-prod \
  --set image.tag=13.0.3 \
  --reuse-values
```

**大版本升级（如 12.x -> 13.x）：**

1. 备份数据
2. 阅读 Citus 升级文档
3. 测试环境验证
4. 滚动更新

```bash
# 先升级 Worker
kubectl set image statefulset/citus-worker citus=citusdata/citus:13.0.3 -n citus-prod
kubectl rollout status statefulset/citus-worker -n citus-prod

# 再升级 Coordinator
kubectl set image statefulset/citus-coordinator citus=citusdata/citus:13.0.3 -n citus-prod
kubectl rollout status statefulset/citus-coordinator -n citus-prod

# 运行升级脚本（如果需要）
kubectl exec -it citus-coordinator-0 -n citus-prod -- \
  psql -U postgres -d citus -c "ALTER EXTENSION citus UPDATE;"
```

---

## 故障排除

### 常见问题

#### 1. Worker 无法注册

**症状：** `citus_get_active_worker_nodes()` 返回空或缺少节点

**排查步骤：**

```bash
# 检查 Worker Pod 状态
kubectl get pods -n citus-prod -l app.kubernetes.io/component=worker

# 检查注册 Job 日志
kubectl logs -n citus-prod -l app.kubernetes.io/component=worker-registration

# 手动测试连通性
kubectl exec -it citus-coordinator-0 -n citus-prod -- \
  pg_isready -h citus-worker-0.citus-worker-hl.citus-prod.svc.cluster.local -p 5432

# 手动注册
kubectl exec -it citus-coordinator-0 -n citus-prod -- \
  psql -U postgres -d citus -c "SELECT citus_add_node('citus-worker-0.citus-worker-hl.citus-prod.svc.cluster.local', 5432);"
```

#### 2. 连接被拒绝

**症状：** `FATAL: no pg_hba.conf entry for host`

**解决方案：**

```bash
# 检查 pg_hba.conf
kubectl exec -it citus-coordinator-0 -n citus-prod -- cat /var/lib/postgresql/data/pgdata/pg_hba.conf

# 如果缺少条目，重启 Pod 让初始化脚本运行
kubectl delete pod citus-coordinator-0 -n citus-prod
```

#### 3. 分片重平衡失败

**症状：** `rebalance_table_shards()` 报错

**排查步骤：**

```bash
# 检查 WAL 级别
kubectl exec -it citus-coordinator-0 -n citus-prod -- \
  psql -U postgres -c "SHOW wal_level;"  # 应该是 logical

# 检查复制槽
kubectl exec -it citus-coordinator-0 -n citus-prod -- \
  psql -U postgres -c "SELECT * FROM pg_replication_slots;"

# 查看详细错误
kubectl exec -it citus-coordinator-0 -n citus-prod -- \
  psql -U postgres -d citus -c "SELECT * FROM get_rebalance_progress();"
```

#### 4. Pod 启动缓慢

**症状：** Pod 长时间处于 `Init` 或 `ContainerCreating` 状态

**排查步骤：**

```bash
# 查看 Pod 事件
kubectl describe pod citus-coordinator-0 -n citus-prod

# 检查 PVC 是否绑定
kubectl get pvc -n citus-prod

# 检查存储类
kubectl get storageclass
```

#### 5. 内存不足 (OOMKilled)

**症状：** Pod 被 OOMKilled

**解决方案：**

```yaml
# 增加资源限制
coordinator:
  resources:
    limits:
      memory: 8Gi
    requests:
      memory: 4Gi

# 或启用 VPA
coordinator:
  vpa:
    enabled: true
    updateMode: Auto
```

### 日志收集

```bash
# Coordinator 日志
kubectl logs citus-coordinator-0 -n citus-prod --tail=100

# Worker 日志
kubectl logs citus-worker-0 -n citus-prod --tail=100

# 所有 Citus Pod 日志
kubectl logs -n citus-prod -l app.kubernetes.io/name=citus --tail=50

# 导出日志到文件
kubectl logs citus-coordinator-0 -n citus-prod > coordinator.log
```

### 健康检查

```bash
# 集群状态检查脚本
cat << 'EOF' | kubectl exec -i citus-coordinator-0 -n citus-prod -- psql -U postgres -d citus
-- 检查 Citus 版本
SELECT citus_version();

-- 检查活跃 Worker
SELECT * FROM citus_get_active_worker_nodes();

-- 检查分片分布
SELECT nodename, count(*) as shards 
FROM pg_dist_shard_placement 
GROUP BY nodename;

-- 检查连接数
SELECT count(*) as connections FROM pg_stat_activity;

-- 检查数据库大小
SELECT pg_size_pretty(pg_database_size('citus'));
EOF
```

---

## 附录

### 环境变量参考

| 变量 | 描述 | 默认值 |
|------|------|--------|
| `POSTGRES_USER` | 管理员用户名 | `postgres` |
| `POSTGRES_PASSWORD` | 管理员密码 | 来自 Secret |
| `POSTGRES_DB` | 默认数据库 | `citus` |
| `PGDATA` | 数据目录 | `/var/lib/postgresql/data/pgdata` |
| `CITUS_NODE_ROLE` | 节点角色 | `coordinator` 或 `worker` |

### 有用的 SQL 命令

```sql
-- 创建分布式表
SELECT create_distributed_table('table_name', 'distribution_column');

-- 创建引用表（所有节点都有完整副本）
SELECT create_reference_table('lookup_table');

-- 查看分片位置
SELECT * FROM pg_dist_shard_placement;

-- 查看分布式表
SELECT * FROM pg_dist_partition;

-- 移动分片
SELECT citus_move_shard_placement(shard_id, 'source_node', 5432, 'target_node', 5432);

-- 设置节点属性
SELECT citus_set_node_property('node_name', 5432, 'shouldhaveshards', true);
```

### 相关链接

- [Citus 官方文档](https://docs.citusdata.com/)
- [Citus GitHub](https://github.com/citusdata/citus)
- [PostgreSQL 文档](https://www.postgresql.org/docs/)
- [Kubernetes StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
