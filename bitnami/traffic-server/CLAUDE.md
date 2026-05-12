# Apache Traffic Server Helm Chart

## 项目概述

Bitnami 风格的 Apache Traffic Server Helm Chart，**StatefulSet + 一致性哈希集群模式**专用。用于在 Kubernetes 上部署高性能 HTTP 代理和缓存服务器：
- 容器镜像代理（Docker Hub、GHCR、GCR、Quay.io、registry.k8s.io）
- Linux 发行版镜像缓存（Ubuntu、Debian、CentOS 等）
- CDN 缓存服务

## 架构

**只支持 StatefulSet**。ATS 的 cache.db 是单进程独占设计，多 pod 共享同一 cache 文件会互相覆写。Chart 仅提供两种部署形态：

| 配置 | 用法 |
|---|---|
| `replicaCount: 1` + `clusterMode.enabled: false` | 单实例，K8s 自愈做 HA（RTO 30-60s） |
| `replicaCount: 3+` + `clusterMode.enabled: true` | 集群模式，一致性哈希分片，真 HA（1 pod 挂仅 1/N 冷 miss） |

集群模式机制：
- `volumeClaimTemplates` 给每个 pod 独立 PVC（block storage / RBD）
- Headless Service 提供稳定 pod DNS（`ats-N.ats-headless.<ns>.svc.cluster.local`）
- 自动渲染 `strategies.yaml` 列出所有 peer + `consistent_hash` 策略
- 客户端访问 LB → 任意 pod → URL hash 决定哪个 peer 拥有缓存 → 必要时 peer 间转发

## 依赖关系

- 使用本地 common chart: `repository: file://../common`
- ATS 10.x 镜像：`docker.io/trafficserver/trafficserver:10.1.2`（注意 chart `appVersion: 10.0.0` 是占位，Docker Hub 没这 tag）

## 已完成功能

### 核心
- [x] StatefulSet 部署（每 pod 独立 PVC via volumeClaimTemplates）
- [x] Headless Service 提供稳定 pod DNS
- [x] 一致性哈希集群（auto-generate `strategies.yaml` peer list）
- [x] 完整 ATS 配置文件支持（records.yaml、remap.config、cache.config 等 17+）
- [x] SSL/HTTPS 源站
- [x] ConfigMap checksum 注解（变更触发 rollout）

### 运维
- [x] 日志持久化 / stdout 模式
- [x] RBAC 模板
- [x] HPA/VPA 已删除（StatefulSet + per-pod PVC 不适合自动伸缩，需要时手动 scale + 扩 strategies.yaml peer 列表）
- [x] state emptyDir for `/opt/var/trafficserver`

### 暴露
- [x] Service (LoadBalancer/ClusterIP/NodePort) — 客户端入口
- [x] Headless Service — pod-to-pod DNS
- [x] Ingress 支持
- [x] Metrics 端口 (ServiceMonitor)

## 关键文件

| 文件 | 用途 |
|------|------|
| `values.yaml` | 主配置，含 `clusterMode` 块 |
| `templates/statefulset.yaml` | 主部署模板（含 volumeClaimTemplates） |
| `templates/headless-svc.yaml` | Headless Service 用于 StatefulSet pod DNS |
| `templates/svc.yaml` | 用户访问 Service（LB/ClusterIP） |
| `templates/strategies-configmap.yaml` | 自动生成集群分片 peer list |
| `templates/startup-configmap.yaml` | 启动脚本 |
| `templates/role.yaml` | RBAC Role |
| `templates/logs-pvc.yaml` | 日志 PVC（如启用 logsPersistence） |
| `README.md` | 参数文档（中文） |
| `DEPLOYMENT.md` | 部署指南（中文） |

## 部署注意事项

### 存储（**重要**）
- 用 **RBD 块存储**（如 `hdd-rep3-rbd-pool` / `nvme-rep3-rbd-pool`），**不要用 CephFS**
- ATS 的 cache.db 用 `O_DIRECT + pwritev`，CephFS 上性能极差且单文件限制 1 TiB
- StatefulSet `volumeClaimTemplates` → `ReadWriteOnce` 是正确的（每 pod 独立 PVC）

### 集群模式（cluster mode）
启用：
```yaml
replicaCount: 3                  # 至少 3 个 peer 才有意义
clusterMode:
  enabled: true
  policy: consistent_hash
  hashKey: cache_key             # cache_key / url / path / path+query / hostname
```

remap 规则要引用 strategy：
```
map http://ubuntu.mirrors.cluster.local/ http://archive.ubuntu.com/ubuntu/ @strategy=ats-cluster
```

### Helm 升级
```bash
helm upgrade ats . -n trafficserver --reuse-values
# 或
helm upgrade ats . -n trafficserver -f my-values.yaml
```

### 已修复问题（历史）
1. **权限错误** `unable to access() local state dir '/opt/var/trafficserver': Permission denied`
   - 解决：添加 emptyDir 卷挂载到 `/opt/var/trafficserver`

2. **PVC 绑定失败** `pod has unbound immediate PersistentVolumeClaims`
   - 历史原因：之前用 Deployment + RWM CephFS 配错
   - **新架构无此问题**：StatefulSet + RWO + 块存储

3. **多 pod 缓存冲突**（之前用 Deployment + 共享 PVC）
   - 现象：`cache_writes: 1, bytes_used: 0`，请求都未命中
   - 根因：ATS cache.db 单进程独占设计，不支持多写
   - **新架构无此问题**：每 pod 独立 cache.db + 一致性哈希分流

## 容器镜像代理配置示例

```yaml
recordsConfig:
  records:
    ssl:
      client:
        verify:
          server:
            policy: PERMISSIVE

remapConfig: |
  map http://docker.mirrors.local/ https://registry-1.docker.io/ @strategy=ats-cluster
  map http://ghcr.mirrors.local/ https://ghcr.io/ @strategy=ats-cluster

cacheConfig: |
  # 不缓存认证请求
  url_regex=/v2/token action=never-cache
  url_regex=/token action=never-cache
  # 不缓存 401/403
  dest_domain=. scheme=https response_code=401 action=never-cache
  dest_domain=. scheme=https response_code=403 action=never-cache
  # 缓存镜像层 7 天
  dest_domain=registry-1.docker.io ttl-in-cache=7d
```

## 文档语言

本项目文档使用中文，因为是中文团队使用。
