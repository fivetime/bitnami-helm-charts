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

### remap.config 解耦挂载（支持运行时热加载）

**所有配置文件都是 subPath 挂载，唯独 remap.config 是目录挂载** —— 这是有意为之，不要"修复"回 subPath：
- `templates/statefulset.yaml`：remap-config 挂到 `/opt/etc/trafficserver/remap.d/`（目录，无 subPath）
- `recordsConfig.records.url_remap.filename: "remap.d/remap.config"` 指引 ATS 去读这个路径

**目的**：K8s 已知行为是 **subPath 挂载不会自动 sync ConfigMap 更新**。改成目录挂载后，kubelet 会在 ~60s 内把 ConfigMap data 变更 sync 到 pod 内文件，配合 `traffic_ctl config reload` 实现零中断热加载。

**两种工作流共存**：
1. `remapConfig: |` 模式（chart 自管）：改 values.yaml + `helm upgrade` → `checksum/remap-config` 注解触发 rolling restart → 新规则自动加载。chart 的标准行为，没有特殊性。
2. `existingRemapConfigmap: <name>` 模式（外置管理）：chart 完全不创建 ConfigMap，用户自己 `kubectl create cm` 提供。`kubectl edit cm` 改完后 `traffic_ctl config reload` 热加载，helm upgrade 永远不动这个 ConfigMap（template `{{- if not .Values.existingRemapConfigmap }}` 守卫）。这是给"运行时频繁改 remap、不想每次 helm upgrade"的运维场景设计的。

**`checksum/remap-config` 注解必须保留**：
- 模式 1：值随 remap 内容变化，触发 rollout
- 模式 2：模板渲染为空，哈希恒定，永不触发 rollout
- 自动按两种模式给出正确行为。**不要删这个注解** —— 之前删过一次，错了。

### 默认 HTTPS 容器端口为空字符串

`containerPorts.https: ""` 是有意的默认值，不要改回 `8443`：
- 默认 `recordsConfig.records.http.server_ports` 只配了 HTTP（`"8080 8080:ipv6"`），ATS 实际不监听 8443
- 如果默认 `containerPorts.https: 8443`，会导致 Service / Headless Service / NetworkPolicy 都开放 8443 端口 → LB 上 443 端口悬空、连接被 refuse
- 大多数部署用前置 Ingress / LB 做 TLS 终结，ATS 不需要监听 HTTPS

四个模板（svc / headless-svc / statefulset / networkpolicy）都用 `{{- if .Values.containerPorts.https }}` 守卫，空值时 HTTPS 相关字段完全不渲染。

启用 ATS 自身 HTTPS 监听需要：
1. `containerPorts.https: 8443`
2. `recordsConfig.records.http.server_ports: "8080 8080:ipv6 8443:ssl"`
3. `sslMulticertConfig` 提供证书

### 健康探针路径可配置

`livenessProbe.path` / `readinessProbe.path` / `startupProbe.path` 默认 `/_stats`，依赖 `pluginConfig` 里加载了 `stats_over_http.so`（chart 默认已加载）。

如果用户禁用该插件：
- 改 path 到其他可访问 URL
- 或用 `customLivenessProbe` 走 `tcpSocket: { port: http }`

statefulset.yaml 渲染时用 `omit ... "path"` 把 path 从顶层探针配置剔除，避免重复出现在 `httpGet.path` 之外。

### strategies.yaml 渲染路径

`clusterMode.enabled` 时：
1. `templates/strategies-configmap.yaml` 生成 strategies.yaml 模板（`__SELF_HOST__` 占位符）
2. subPath 挂载到 `/opt/etc/trafficserver/strategies.yaml.tpl`（只读）
3. 启动脚本渲染 `__SELF_HOST__` → 输出到 **`/opt/var/trafficserver/strategies.yaml`**（state emptyDir 卷）
4. `templates/records-configmap.yaml` 自动注入 `url_remap.strategies.filename: /opt/var/trafficserver/strategies.yaml` 到 records.yaml

**不要把渲染产物路径改回 `/tmp/`** —— 早期版本用过 `/tmp/strategies-rendered.yaml`，已迁移到 state 卷以便：
- 解耦 `readOnlyRootFilesystem`
- 提高可发现性（运维进 pod 一眼能看到）
- 跟其他临时文件分开

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
