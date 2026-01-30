# Nacos Helm Chart

[Nacos](https://nacos.io/) 是一个易于使用的动态服务发现、配置管理和服务管理平台，用于构建云原生应用程序。

## 特性

- ✅ 支持集群模式和单机模式
- ✅ 支持 MySQL 和 PostgreSQL 数据库
- ✅ 自动数据库初始化
- ✅ 内置认证支持
- ✅ Prometheus 监控指标
- ✅ Prometheus 服务发现（SD）
- ✅ Istio xDS 协议集成
- ✅ Kubernetes 服务同步
- ✅ Ingress 支持
- ✅ Pod 反亲和性
- ✅ HPA 自动伸缩
- ✅ NetworkPolicy 支持

## 前置条件

- Kubernetes 1.23+
- Helm 3.8+
- 外部数据库（MySQL 8.0+ 或 PostgreSQL 14+）用于集群模式

## 快速开始

### 添加 Helm 仓库

```bash
# 如果已发布到 Helm 仓库
helm repo add nacos https://your-helm-repo
helm repo update
```

### 安装

**单机模式（测试用）**：

```bash
helm install nacos ./nacos \
  --set mode=standalone \
  --set database.type=embedded
```

**集群模式（生产用）**：

```bash
helm install nacos ./nacos \
  --namespace kube-infra \
  --create-namespace \
  --set database.type=mysql \
  --set database.host=mysql.database.svc \
  --set database.port=3306 \
  --set database.name=nacos \
  --set database.username=nacos \
  --set database.password=your-password
```

### 使用已有的数据库密码 Secret

```bash
# 创建 Secret
kubectl create secret generic nacos-db-secret \
  --namespace kube-infra \
  --from-literal=database-password=your-password

# 安装时引用
helm install nacos ./nacos \
  --namespace kube-infra \
  --set database.type=mysql \
  --set database.host=mysql.database.svc \
  --set database.name=nacos \
  --set database.username=nacos \
  --set database.existingSecret=nacos-db-secret
```

## 配置参数

### 全局参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `global.imageRegistry` | 全局镜像仓库 | `""` |
| `global.imagePullSecrets` | 全局镜像拉取密钥 | `[]` |
| `global.storageClass` | 全局存储类 | `""` |

### Nacos 基础参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `mode` | 运行模式：`standalone` 或 `cluster` | `cluster` |
| `replicaCount` | 副本数（集群模式建议奇数：3, 5, 7） | `3` |
| `image.registry` | 镜像仓库 | `docker.io` |
| `image.repository` | 镜像名称 | `nacos/nacos-server` |
| `image.tag` | 镜像标签 | `v3.1.1` |

### 认证参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `auth.enabled` | 启用认证 | `true` |
| `auth.token` | JWT Token（Base64，最小32字节，留空自动生成） | `""` |
| `auth.identity.key` | 节点间认证密钥 | `""` |
| `auth.identity.value` | 节点间认证值 | `""` |
| `auth.existingSecret` | 使用已有的认证 Secret | `""` |

### 数据库参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `database.type` | 数据库类型：`mysql`、`postgresql`、`embedded` | `mysql` |
| `database.host` | 数据库主机 | `""` |
| `database.port` | 数据库端口 | MySQL: `3306`, PostgreSQL: `5432` |
| `database.name` | 数据库名称 | `nacos` |
| `database.username` | 数据库用户名 | `nacos` |
| `database.password` | 数据库密码 | `""` |
| `database.existingSecret` | 使用已有的数据库密码 Secret | `""` |
| `database.init.enabled` | 自动初始化数据库 Schema | `true` |

**MySQL 特定参数**：

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `database.mysql.param` | JDBC 连接参数 | `characterEncoding=utf8&...` |

**PostgreSQL 特定参数**：

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `database.postgresql.param` | JDBC 连接参数 | `tcpKeepAlive=true&...` |
| `database.postgresql.pool.maximumPoolSize` | 最大连接池大小 | `20` |

### JVM 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `jvm.xms` | 初始堆大小 | `1g` |
| `jvm.xmx` | 最大堆大小 | `1g` |
| `jvm.xmn` | 年轻代大小 | `512m` |
| `jvm.metaspaceSize` | Metaspace 初始大小 | `128m` |
| `jvm.maxMetaspaceSize` | Metaspace 最大大小 | `320m` |
| `jvm.extraOpts` | 额外 JVM 参数 | `""` |

### Service 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `service.type` | Service 类型 | `ClusterIP` |
| `service.labels` | 额外的 Service 标签 | `{}` |
| `service.annotations` | 额外的 Service 注解 | `{}` |
| `service.ports.http` | Console HTTP 端口 | `8080` |
| `service.ports.client` | Client API 端口 | `8848` |
| `service.ports.clientRpc` | Client gRPC 端口 | `9848` |
| `service.ports.raftRpc` | Raft gRPC 端口 | `9849` |
| `service.loadBalancerIP` | LoadBalancer IP | `""` |
| `service.externalTrafficPolicy` | 外部流量策略 | `""` |

### 持久化参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `persistence.enabled` | 启用持久化存储 | `true` |
| `persistence.storageClass` | 存储类 | `""` |
| `persistence.size` | 存储大小 | `10Gi` |
| `persistence.accessModes` | 访问模式 | `["ReadWriteOnce"]` |

### 监控参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `metrics.enabled` | 启用 metrics 端点 | `false` |
| `metrics.serviceMonitor.enabled` | 创建 ServiceMonitor | `false` |
| `metrics.serviceMonitor.interval` | 抓取间隔 | `30s` |

### Prometheus 服务发现参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `prometheus.sd.enabled` | 启用 Prometheus 服务发现 | `false` |

### Istio 集成参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `istio.enabled` | 启用 Istio xDS 协议支持 | `false` |
| `istio.mcp.enabled` | 启用 MCP 服务器 | `true` |
| `istio.mcp.full` | 全量推送模式（false=增量推送） | `true` |

### Kubernetes 服务同步参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `k8sSync.enabled` | 启用 K8s 服务同步到 Nacos | `false` |
| `k8sSync.outsideCluster` | 在 K8s 集群外运行 | `false` |
| `k8sSync.kubeConfig` | kubeconfig 路径（集群外时使用） | `""` |
| `k8sSync.rbac.create` | 创建 RBAC 资源 | `true` |

## 使用场景

### 场景一：基础部署（MySQL 集群模式）

```yaml
# values-production.yaml
mode: cluster
replicaCount: 3

database:
  type: mysql
  host: mysql.database.svc
  port: 3306
  name: nacos
  username: nacos
  existingSecret: nacos-db-secret

persistence:
  enabled: true
  size: 20Gi
  storageClass: ceph-rbd

resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 2Gi
```

```bash
helm install nacos ./nacos -f values-production.yaml -n kube-infra
```

### 场景二：LoadBalancer + Cilium BGP

```yaml
# values-cilium.yaml
service:
  type: LoadBalancer
  labels:
    io.cilium/bgp: "private"
  annotations:
    lbipam.cilium.io/ips: "10.224.18.21"
  externalTrafficPolicy: Local

database:
  type: mysql
  host: percona-xtradb-haproxy
  existingSecret: nacos-db-secret
```

```bash
helm install nacos ./nacos -f values-cilium.yaml -n kube-infra
```

### 场景三：启用 Prometheus 服务发现

此功能允许 Prometheus 自动发现 Nacos 中注册的微服务。

```yaml
# values-prometheus-sd.yaml
prometheus:
  sd:
    enabled: true
```

Prometheus 配置：

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'nacos-services'
    http_sd_configs:
      - url: 'http://nacos.kube-infra.svc:8848/nacos/prometheus'
```

### 场景四：Istio 服务网格集成

让 Nacos 作为 xDS 服务端，与 Istio/Envoy 集成。

```yaml
# values-istio.yaml
istio:
  enabled: true
  mcp:
    enabled: true
    full: false  # 使用增量推送，适合大集群
```

Envoy 配置示例：

```yaml
# envoy.yaml
dynamic_resources:
  ads_config:
    api_type: GRPC
    transport_api_version: V3
    grpc_services:
      - envoy_grpc:
          cluster_name: nacos_xds

static_resources:
  clusters:
    - name: nacos_xds
      type: STATIC
      connect_timeout: 1s
      load_assignment:
        cluster_name: nacos_xds
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: nacos.kube-infra.svc
                      port_value: 18848
```

### 场景五：Kubernetes 服务同步

将 K8s 中的 Service 自动同步到 Nacos 服务发现，适用于混合部署场景。

```yaml
# values-k8s-sync.yaml
k8sSync:
  enabled: true
  rbac:
    create: true
```

启用后，K8s 中的 Service 会自动出现在 Nacos 的服务列表中。

### 场景六：完整生产配置

```yaml
# values-full-production.yaml
mode: cluster
replicaCount: 3

image:
  tag: v3.1.1

auth:
  enabled: true
  existingSecret: nacos-auth-secret

database:
  type: mysql
  host: percona-xtradb-haproxy.database.svc
  port: 3306
  name: nacos
  username: nacos
  existingSecret: nacos-db-secret
  mysql:
    param: "characterEncoding=utf8&connectTimeout=10000&socketTimeout=30000&autoReconnect=true&useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=Asia/Shanghai"

jvm:
  xms: "2g"
  xmx: "2g"
  xmn: "1g"

service:
  type: LoadBalancer
  labels:
    io.cilium/bgp: "private"
  annotations:
    lbipam.cilium.io/ips: "10.224.18.21"
  externalTrafficPolicy: Local

persistence:
  enabled: true
  size: 50Gi
  storageClass: ceph-rbd

resources:
  requests:
    cpu: 1000m
    memory: 2Gi
  limits:
    cpu: 4000m
    memory: 4Gi

podAntiAffinityPreset: hard

metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 30s

prometheus:
  sd:
    enabled: true

# 按需启用
# istio:
#   enabled: true
# k8sSync:
#   enabled: true
```

## 端口说明

| 端口 | 名称 | 用途 |
|------|------|------|
| 8080 | http | Web 控制台、健康检查 |
| 8848 | client | Client API、Prometheus metrics |
| 9848 | client-rpc | Client gRPC 通信 |
| 9849 | raft-rpc | Raft 协议 gRPC 通信 |
| 7848 | old-raft | 旧版 Raft 协议（兼容） |
| 9080 | mcp | MCP 协议端口 |
| 18848 | xds | Istio xDS 协议端口（需启用） |

## 健康检查

Nacos 3.x 使用新的 v3 API 端点：

| 探针 | 端点 | 端口 |
|------|------|------|
| startupProbe | `/v3/console/health/readiness` | 8080 |
| livenessProbe | `/v3/console/health/liveness` | 8080 |
| readinessProbe | `/v3/console/health/readiness` | 8080 |

## 访问控制台

安装完成后，根据 Service 类型访问：

**ClusterIP（端口转发）**：

```bash
kubectl port-forward -n kube-infra svc/nacos 8080:8080 8848:8848
# 访问 http://localhost:8080/nacos
```

**LoadBalancer**：

```bash
export SERVICE_IP=$(kubectl get svc -n kube-infra nacos -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Console: http://$SERVICE_IP:8080/nacos"
```

**默认凭据**：
- 用户名：`nacos`
- 密码：`nacos`

⚠️ **重要**：首次登录后请立即修改默认密码！

## 升级

```bash
helm upgrade nacos ./nacos -n kube-infra -f values.yaml
```

**注意**：升级集群模式时，建议先备份数据库。

## 卸载

```bash
helm uninstall nacos -n kube-infra

# 如果需要清理 PVC
kubectl delete pvc -n kube-infra -l app.kubernetes.io/name=nacos
```

## 故障排查

### 查看 Pod 日志

```bash
kubectl logs -n kube-infra nacos-0 -c nacos -f
```

### 检查集群状态

```bash
# 进入 Pod
kubectl exec -it -n kube-infra nacos-0 -c nacos -- bash

# 查看集群成员
curl http://localhost:8848/nacos/v2/core/cluster/node/list
```

### 常见问题

**1. Pod 启动失败：数据库连接错误**

检查数据库连接参数和网络连通性：

```bash
kubectl exec -n kube-infra nacos-0 -c nacos -- \
  curl -s "http://localhost:8848/nacos/v1/console/health/readiness"
```

**2. MySQL utf8mb4 索引超长**

本 Chart 已包含修复后的 Schema，使用索引前缀解决 3072 字节限制。

**3. 健康检查失败**

确保使用 v3 API 端点（`/v3/console/health/*`）和端口 8080。

## 参考链接

- [Nacos 官方文档](https://nacos.io/docs/latest/)
- [Nacos GitHub](https://github.com/alibaba/nacos)
- [Nacos Docker](https://github.com/nacos-group/nacos-docker)

## 许可证

Apache License 2.0
