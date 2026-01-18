# Apache Traffic Server Helm Chart 部署指南

本文档提供 Apache Traffic Server Helm Chart 的详细部署指南，包括环境准备、安装步骤、配置示例和运维操作。

## 目录

- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [安装方式](#安装方式)
- [配置指南](#配置指南)
- [部署场景](#部署场景)
- [升级与回滚](#升级与回滚)
- [监控与告警](#监控与告警)
- [故障排除](#故障排除)
- [卸载](#卸载)

## 环境要求

### Kubernetes 版本

| 组件 | 最低版本 | 推荐版本 |
|------|----------|----------|
| Kubernetes | 1.23+ | 1.28+ |
| Helm | 3.8+ | 3.14+ |

### 资源要求

| 部署规模 | CPU | 内存 | 存储 |
|----------|-----|------|------|
| 开发/测试 | 500m | 512Mi | 10Gi |
| 小型生产 | 2 | 4Gi | 100Gi |
| 中型生产 | 4 | 8Gi | 500Gi |
| 大型生产 | 8+ | 16Gi+ | 1Ti+ |

### 可选依赖

| 组件 | 用途 | 版本要求 |
|------|------|----------|
| Prometheus Operator | 监控集成 | 0.50+ |
| Vertical Pod Autoscaler | 垂直自动伸缩 | 0.10+ |
| Cert-Manager | TLS 证书管理 | 1.0+ |

## 快速开始

### 1. 添加 Helm 仓库（如适用）

```bash
# 如果从本地安装，跳过此步骤
helm repo add myrepo https://charts.example.com
helm repo update
```

### 2. 创建命名空间

```bash
kubectl create namespace trafficserver
```

### 3. 安装 Chart

```bash
# 从本地目录安装
helm install ats ./trafficserver -n trafficserver

# 或从仓库安装
helm install ats myrepo/trafficserver -n trafficserver
```

### 4. 验证安装

```bash
# 查看 Pod 状态
kubectl get pods -n trafficserver -l app.kubernetes.io/name=trafficserver

# 查看服务
kubectl get svc -n trafficserver

# 查看日志
kubectl logs -n trafficserver -l app.kubernetes.io/name=trafficserver
```

## 安装方式

### 方式一：使用默认配置

```bash
helm install ats ./trafficserver -n trafficserver
```

### 方式二：使用自定义 values 文件

```bash
# 创建自定义配置文件
cat > my-values.yaml <<EOF
replicaCount: 3

image:
  tag: "10.0.0"

resources:
  requests:
    cpu: 2
    memory: 4Gi
  limits:
    cpu: 4
    memory: 8Gi

persistence:
  size: 500Gi
  storageClass: "fast-ssd"
EOF

# 使用自定义配置安装
helm install ats ./trafficserver -n trafficserver -f my-values.yaml
```

### 方式三：使用 --set 参数

```bash
helm install ats ./trafficserver -n trafficserver \
  --set replicaCount=3 \
  --set image.tag=10.0.0 \
  --set persistence.size=500Gi
```

### 方式四：组合使用

```bash
helm install ats ./trafficserver -n trafficserver \
  -f my-values.yaml \
  --set replicaCount=5
```

## 配置指南

### 基础配置

#### 镜像配置

```yaml
image:
  registry: docker.io
  repository: trafficserver/trafficserver
  tag: "10.0.0"  # 生产环境请使用固定版本
  pullPolicy: IfNotPresent
  # 私有仓库认证
  pullSecrets:
    - name: my-registry-secret
```

#### 副本与资源

```yaml
replicaCount: 3

resources:
  requests:
    cpu: 2
    memory: 4Gi
  limits:
    cpu: 4
    memory: 8Gi
```

### URL 重映射配置

```yaml
remapConfig: |
  # Ubuntu 镜像
  map http://ubuntu.mirrors.example.com/ http://archive.ubuntu.com/ubuntu/
  map https://ubuntu.mirrors.example.com/ https://archive.ubuntu.com/ubuntu/
  
  # PyPI 镜像
  map http://pypi.mirrors.example.com/ https://pypi.org/
  
  # Docker Registry 镜像
  map http://docker.mirrors.example.com/ https://registry-1.docker.io/
  
  # 反向代理
  reverse_map http://backend.internal/ http://api.example.com/
```

### 缓存配置

#### 存储配置

```yaml
storageConfig: |
  # 使用 256MB 内存缓存
  /opt/var/cache/trafficserver 256M
  
  # 或使用更大的缓存
  # /opt/var/cache/trafficserver 10G
```

#### 缓存策略

```yaml
cacheConfig: |
  # 缓存所有 .deb 文件 30 天
  dest_domain=. suffix=deb ttl-in-cache=30d
  
  # 缓存 Docker 镜像层 7 天
  dest_domain=registry-1.docker.io ttl-in-cache=7d
  
  # 不缓存特定路径
  dest_domain=api.example.com prefix=/v1/realtime ttl-in-cache=0
```

### 核心参数配置

```yaml
recordsConfig:
  records:
    # 线程配置
    accept_threads: 2
    exec_thread:
      autoconfig:
        enabled: 1
      limit: 8
    task_threads: 2
    
    # 缓存配置
    cache:
      ram_cache:
        size: 4294967296  # 4GB RAM 缓存
      ram_cache_cutoff: 4194304  # 4MB
      
    # HTTP 配置
    http:
      server_ports: "8080 8080:ipv6 8443:ssl 8443:ssl:ipv6"
      keep_alive_no_activity_timeout_in: 120
      keep_alive_no_activity_timeout_out: 120
      connect_attempts_timeout: 30
      
    # 网络配置
    net:
      connections_throttle: 100000
      max_connections_in: 100000
      
    # 日志配置
    log:
      logging_enabled: 3
      max_space_mb_for_logs: 25000
      rolling_enabled: 1
      rolling_interval_sec: 86400
```

### TLS/SSL 配置

#### SNI 配置

```yaml
sniConfig: |
  sni:
    - fqdn: "*.example.com"
      verify_client: NONE
      host_sni_policy: PERMISSIVE
    - fqdn: "secure.example.com"
      verify_client: STRICT
      client_cert: /etc/ssl/client-ca.pem
```

#### SSL 多证书

```yaml
sslMulticertConfig: |
  ssl_cert_name=example.com.pem ssl_key_name=example.com.key
  ssl_cert_name=wildcard.example.com.pem ssl_key_name=wildcard.example.com.key
```

### 持久化配置

```yaml
persistence:
  enabled: true
  storageClass: "fast-ssd"  # 使用 SSD 存储类
  accessModes:
    - ReadWriteMany  # 多副本共享存储
  size: 500Gi
  
  # 或使用现有 PVC
  # existingClaim: "my-existing-pvc"
```

### 网络配置

#### Service 配置

```yaml
service:
  type: LoadBalancer  # 或 ClusterIP, NodePort
  ports:
    http: 80
    https: 443
  # 云厂商注解
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
```

#### Ingress 配置

```yaml
ingress:
  enabled: true
  ingressClassName: nginx
  hostname: ats.example.com
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
  tls: true
```

### 日志配置

#### 方式一：输出到 stdout（推荐）

默认启用，日志输出到标准输出，由 Kubernetes 日志采集系统（如 Fluentd、Loki、ELK）处理：

```yaml
logsPersistence:
  toStdout: true  # 默认值
  enabled: false
```

这是云原生最佳实践，适用于大多数场景。

#### 方式二：日志持久化

如果需要将日志写入持久化存储：

```yaml
logsPersistence:
  enabled: true
  toStdout: false
  storageClass: "standard"
  accessModes:
    - ReadWriteOnce
  size: 10Gi
```

> **注意**: 多副本部署时，建议使用 `toStdout: true`，因为共享日志 PVC 可能导致文件锁冲突。

### RBAC 配置

如果需要 Pod 访问 Kubernetes API（如读取 ConfigMap 或 Secret）：

```yaml
rbac:
  create: true
  rules:
    - apiGroups: [""]
      resources: ["configmaps", "secrets"]
      verbs: ["get", "list", "watch"]

serviceAccount:
  create: true
  automountServiceAccountToken: true
```

## 部署场景

### 场景一：开发测试环境

```yaml
# dev-values.yaml
replicaCount: 1

resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 1
    memory: 1Gi

persistence:
  enabled: true
  size: 10Gi

autoscaling:
  hpa:
    enabled: false

networkPolicy:
  enabled: false
```

```bash
helm install ats-dev ./trafficserver -n dev -f dev-values.yaml
```

### 场景二：生产高可用环境

```yaml
# prod-values.yaml
replicaCount: 3

image:
  tag: "10.0.0"

resources:
  requests:
    cpu: 4
    memory: 8Gi
  limits:
    cpu: 8
    memory: 16Gi

persistence:
  enabled: true
  storageClass: "fast-ssd"
  size: 1Ti
  accessModes:
    - ReadWriteMany

autoscaling:
  hpa:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPU: 70
    targetMemory: 80

podAntiAffinityPreset: hard

pdb:
  create: true
  minAvailable: 2

metrics:
  enabled: true
  serviceMonitor:
    enabled: true

recordsConfig:
  records:
    accept_threads: 4
    exec_thread:
      limit: 16
    cache:
      ram_cache:
        size: 8589934592  # 8GB
    net:
      connections_throttle: 100000
```

```bash
helm install ats-prod ./trafficserver -n production -f prod-values.yaml
```

### 场景三：APT/YUM 镜像服务

```yaml
# mirror-values.yaml
replicaCount: 2

remapConfig: |
  # Ubuntu
  map http://ubuntu.mirrors.local/ http://archive.ubuntu.com/ubuntu/
  map http://ubuntu.mirrors.local/ http://security.ubuntu.com/ubuntu/
  
  # Debian
  map http://debian.mirrors.local/ http://deb.debian.org/debian/
  
  # CentOS
  map http://centos.mirrors.local/ http://mirror.centos.org/centos/
  
  # EPEL
  map http://epel.mirrors.local/ http://download.fedoraproject.org/pub/epel/

cacheConfig: |
  # 缓存包文件 30 天
  dest_domain=. suffix=deb ttl-in-cache=30d
  dest_domain=. suffix=rpm ttl-in-cache=30d
  dest_domain=. suffix=gz ttl-in-cache=30d
  dest_domain=. suffix=xz ttl-in-cache=30d
  
  # 元数据缓存 1 小时
  dest_domain=. suffix=Release ttl-in-cache=1h
  dest_domain=. suffix=Packages ttl-in-cache=1h
  dest_domain=. suffix=repomd.xml ttl-in-cache=1h

persistence:
  size: 2Ti
```

### 场景四：容器镜像代理

支持 Docker Hub、GHCR、GCR、Quay.io 等容器镜像仓库的代理和缓存，包含 SSL 和认证 Token 透传支持。

```yaml
# registry-proxy-values.yaml
# 核心配置 - 启用 SSL 连接到 HTTPS 源站
recordsConfig:
  records:
    http:
      server_ports: "8080 8080:ipv6"
      cache:
        cache_responses_to_cookies: 0
      insert_request_via_str: 0
      insert_response_via_str: 0
    ssl:
      client:
        # 启用与上游 HTTPS 站点的 SSL 连接
        verify:
          server:
            policy: PERMISSIVE
        cert:
          filename: ""
        private_key:
          filename: ""
        CA:
          cert:
            filename: ""

# URL 重映射配置
remapConfig: |
  # Docker Hub
  map http://docker.mirrors.local/ https://registry-1.docker.io/

  # GitHub Container Registry
  map http://ghcr.mirrors.local/ https://ghcr.io/

  # Google Container Registry
  map http://gcr.mirrors.local/ https://gcr.io/

  # Quay.io
  map http://quay.mirrors.local/ https://quay.io/

  # Kubernetes Container Registry
  map http://registry-k8s.mirrors.local/ https://registry.k8s.io/

# 缓存策略 - 支持认证透传
cacheConfig: |
  # 不缓存认证相关的请求
  url_regex=/v2/token action=never-cache
  url_regex=/token action=never-cache
  url_regex=/oauth2/token action=never-cache
  url_regex=/auth action=never-cache

  # 不缓存 401/403 响应
  dest_domain=. scheme=https response_code=401 action=never-cache
  dest_domain=. scheme=https response_code=403 action=never-cache

  # 缓存镜像层和 manifest (7 天)
  dest_domain=registry-1.docker.io ttl-in-cache=7d
  dest_domain=ghcr.io ttl-in-cache=7d
  dest_domain=gcr.io ttl-in-cache=7d
  dest_domain=quay.io ttl-in-cache=7d
  dest_domain=registry.k8s.io ttl-in-cache=7d
```

#### 客户端配置

配置 Docker/containerd 使用代理：

```bash
# Docker daemon.json
{
  "registry-mirrors": ["http://docker.mirrors.local"]
}

# 或者在 pull 时指定
docker pull docker.mirrors.local/library/nginx:latest
```

#### 私有仓库认证

客户端登录后，Authorization header 会自动透传到上游仓库：

```bash
# 登录会话会透传认证
docker login docker.mirrors.local -u username -p token
docker pull docker.mirrors.local/myorg/private-image:tag
```

### 场景五：多租户隔离

```yaml
# multi-tenant-values.yaml
networkPolicy:
  enabled: true
  allowExternal: false
  ingressNSMatchLabels:
    tenant: allowed
  ingressNSPodMatchLabels:
    role: client

podSecurityContext:
  enabled: true
  fsGroup: 1001
  runAsUser: 1001
  runAsNonRoot: true

containerSecurityContext:
  enabled: true
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: false
  runAsNonRoot: true
```

## 升级与回滚

### 升级 Chart

```bash
# 查看当前版本
helm list -n trafficserver

# 更新配置（使用 values 文件）
helm upgrade ats ./trafficserver -n trafficserver -f my-values.yaml

# 更新并保留之前的参数（不使用 values 文件时推荐）
helm upgrade ats ./trafficserver -n trafficserver --reuse-values

# 更新并等待完成
helm upgrade ats ./trafficserver -n trafficserver -f my-values.yaml --wait --timeout 10m
```

> **重要**: 如果不使用 `-f values.yaml`，请添加 `--reuse-values` 参数保留之前的配置，否则所有参数会恢复为默认值。

### 查看历史版本

```bash
helm history ats -n trafficserver
```

### 回滚到上一版本

```bash
helm rollback ats -n trafficserver
```

### 回滚到指定版本

```bash
helm rollback ats 2 -n trafficserver
```

### 零宕机升级策略

Chart 默认配置了滚动更新策略：

```yaml
updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0
```

配合 PodDisruptionBudget 确保升级期间服务可用：

```yaml
pdb:
  create: true
  minAvailable: 2  # 至少保持 2 个 Pod 可用
```

## 监控与告警

### 启用 Prometheus 监控

```yaml
metrics:
  enabled: true
  port: 8083
  path: /_stats
  
  serviceMonitor:
    enabled: true
    interval: 30s
    scrapeTimeout: 10s
    labels:
      release: prometheus
```

### 配置告警规则

```yaml
metrics:
  prometheusRule:
    enabled: true
    rules:
      - alert: TrafficServerDown
        expr: up{job="trafficserver"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Traffic Server 实例宕机"
          description: "{{ $labels.instance }} 已宕机超过 5 分钟"
      
      - alert: TrafficServerHighCPU
        expr: rate(process_cpu_seconds_total{job="trafficserver"}[5m]) > 0.8
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Traffic Server CPU 使用率过高"
          description: "{{ $labels.instance }} CPU 使用率超过 80%"
      
      - alert: TrafficServerHighMemory
        expr: process_resident_memory_bytes{job="trafficserver"} / 1024 / 1024 / 1024 > 12
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Traffic Server 内存使用过高"
          description: "{{ $labels.instance }} 内存使用超过 12GB"
```

### Grafana 仪表板

推荐指标：

| 指标 | 描述 |
|------|------|
| `proxy.process.http.total_client_connections` | 客户端总连接数 |
| `proxy.process.http.current_client_connections` | 当前客户端连接数 |
| `proxy.process.cache.bytes_used` | 缓存使用量 |
| `proxy.process.cache.bytes_total` | 缓存总量 |
| `proxy.process.http.cache_hit_ratio` | 缓存命中率 |
| `proxy.process.http.transaction_counts` | 事务计数 |

## 故障排除

### 常见问题

#### Pod 无法启动

```bash
# 检查 Pod 状态
kubectl describe pod -n trafficserver -l app.kubernetes.io/name=trafficserver

# 检查事件
kubectl get events -n trafficserver --sort-by='.lastTimestamp'

# 常见原因：
# 1. 存储类不存在 - 检查 persistence.storageClass
# 2. 资源不足 - 检查 resources 配置
# 3. 镜像拉取失败 - 检查 image 配置和 pullSecrets
```

#### 服务无法访问

```bash
# 检查服务状态
kubectl get svc -n trafficserver

# 检查端点
kubectl get endpoints -n trafficserver

# 测试连接
kubectl run -it --rm debug --image=curlimages/curl -- curl http://ats-trafficserver:80/_stats
```

#### 缓存不生效

```bash
# 进入容器检查配置
kubectl exec -it -n trafficserver deploy/ats-trafficserver -- cat /opt/etc/trafficserver/remap.config

# 检查缓存状态
kubectl exec -it -n trafficserver deploy/ats-trafficserver -- ls -la /opt/var/cache/trafficserver/

# 查看统计信息
curl http://<service-ip>/_stats
```

### 日志查看

```bash
# 查看实时日志
kubectl logs -n trafficserver -l app.kubernetes.io/name=trafficserver -f

# 查看最近 100 行
kubectl logs -n trafficserver -l app.kubernetes.io/name=trafficserver --tail=100

# 查看所有容器日志
kubectl logs -n trafficserver -l app.kubernetes.io/name=trafficserver --all-containers
```

### 进入容器调试

```bash
# 进入运行中的容器
kubectl exec -it -n trafficserver deploy/ats-trafficserver -- /bin/bash

# 常用调试命令
ls -la /opt/etc/trafficserver/  # 查看配置文件
cat /opt/var/log/trafficserver/error.log  # 查看错误日志
/opt/bin/traffic_ctl config match proxy  # 查看运行时配置
```

### 重启 Pod

```bash
# 滚动重启
kubectl rollout restart deployment -n trafficserver ats-trafficserver

# 等待重启完成
kubectl rollout status deployment -n trafficserver ats-trafficserver
```

## 卸载

### 卸载 Chart

```bash
helm uninstall ats -n trafficserver
```

### 清理 PVC（可选）

```bash
# 查看 PVC
kubectl get pvc -n trafficserver

# 删除 PVC（警告：将删除所有缓存数据）
kubectl delete pvc -n trafficserver -l app.kubernetes.io/name=trafficserver
```

### 删除命名空间（可选）

```bash
kubectl delete namespace trafficserver
```

## 附录

### A. 配置文件说明

| 文件 | 用途 | 格式 |
|------|------|------|
| records.yaml | 核心配置 | YAML |
| remap.config | URL 重映射规则 | 文本 |
| plugin.config | 插件配置 | 文本 |
| storage.config | 缓存存储配置 | 文本 |
| ip_allow.yaml | IP 访问控制 | YAML |
| logging.yaml | 日志配置 | YAML |
| sni.yaml | SNI/TLS 配置 | YAML |
| cache.config | 缓存策略 | 文本 |
| parent.config | 父代理配置 | 文本 |
| strategies.yaml | 上游路由策略 | YAML |
| ssl_multicert.config | SSL 多证书 | 文本 |
| hosting.config | 卷分配配置 | 文本 |
| volume.config | 缓存卷定义 | 文本 |
| splitdns.config | DNS 分离配置 | 文本 |
| socks.config | SOCKS 代理配置 | 文本 |
| jsonrpc.yaml | JSON-RPC 接口配置 | YAML |

### B. 有用的命令

```bash
# 查看所有资源
kubectl get all -n trafficserver -l app.kubernetes.io/name=trafficserver

# 查看配置映射
kubectl get configmap -n trafficserver

# 导出当前配置
helm get values ats -n trafficserver > current-values.yaml

# 模拟升级
helm upgrade ats ./trafficserver -n trafficserver -f my-values.yaml --dry-run

# 查看渲染后的模板
helm template ats ./trafficserver -f my-values.yaml
```

### C. 参考链接

- [Apache Traffic Server 官方文档](https://docs.trafficserver.apache.org/)
- [Kubernetes 官方文档](https://kubernetes.io/docs/)
- [Helm 官方文档](https://helm.sh/docs/)
- [Bitnami Helm Charts](https://github.com/bitnami/charts)
