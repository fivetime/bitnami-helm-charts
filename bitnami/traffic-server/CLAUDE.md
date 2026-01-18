# Apache Traffic Server Helm Chart

## 项目概述

Bitnami 风格的 Apache Traffic Server Helm Chart，用于在 Kubernetes 上部署高性能 HTTP 代理和缓存服务器。主要用途：
- 容器镜像代理（Docker Hub、GHCR、GCR、Quay.io、registry.k8s.io）
- Linux 发行版镜像缓存（Ubuntu、Debian、CentOS 等）
- CDN 缓存服务

## 依赖关系

- 使用本地 common chart: `repository: file://../common`
- 已删除 `charts/common/` 目录，改用共享的 `bitnami/common`

## 已完成功能

### 核心功能
- [x] 完整的 ATS 配置文件支持（records.yaml、remap.config、cache.config 等 17+ 配置文件）
- [x] SSL/HTTPS 源站支持（可代理 HTTPS 后端）
- [x] 认证 Token 透传（Authorization header 自动转发）
- [x] ConfigMap checksum 注解（配置变更自动触发 Pod 重启）

### 运维功能
- [x] 日志持久化 (`logsPersistence.enabled`)
- [x] 日志输出到 stdout (`logsPersistence.toStdout: true`，默认启用，云原生最佳实践)
- [x] RBAC 模板 (`templates/role.yaml`, `templates/rolebinding.yaml`)
- [x] VPA 验证（`controlledResources` 默认为 `["cpu", "memory"]`，空值显示警告）
- [x] 状态目录 emptyDir (`/opt/var/trafficserver`)

### 暴露方式
- [x] Service (LoadBalancer/ClusterIP/NodePort)
- [x] Ingress 支持
- [x] Metrics 端口 (ServiceMonitor)

## 关键文件

| 文件 | 用途 |
|------|------|
| `values.yaml` | 主配置，包含容器镜像代理示例 |
| `templates/deployment.yaml` | 部署模板，含所有 ConfigMap checksum |
| `templates/startup-configmap.yaml` | 启动脚本，支持日志转发 |
| `templates/role.yaml` | RBAC Role 模板 |
| `templates/rolebinding.yaml` | RBAC RoleBinding 模板 |
| `templates/logs-pvc.yaml` | 日志 PVC 模板 |
| `README.md` | 参数文档（中文） |
| `DEPLOYMENT.md` | 部署指南（中文） |

## 部署注意事项

### 存储
- 多副本部署使用 CephFS (`ReadWriteMany`)，单副本可用 RBD (`ReadWriteOnce`)
- 日志建议用 `toStdout: true`，避免多 Pod 共享日志 PVC 的锁冲突

### Helm 升级
```bash
# 保留之前的参数
helm upgrade traffic-server . -n traffic-server --reuse-values

# 或使用 values 文件
helm upgrade traffic-server . -n traffic-server -f my-values.yaml
```

### 已修复问题
1. **权限错误** `unable to access() local state dir '/opt/var/trafficserver': Permission denied`
   - 解决：添加 emptyDir 卷挂载到 `/opt/var/trafficserver`

2. **PVC 绑定失败** `pod has unbound immediate PersistentVolumeClaims`
   - 原因：`ReadWriteMany` 不兼容 RBD
   - 解决：使用 CephFS 存储类

3. **nil pointer 错误** `nil pointer evaluating interface {}.toStdout`
   - 原因：`--reuse-values` 时旧配置无 `logsPersistence` 字段
   - 解决：模板中添加 `.Values.logsPersistence` 存在性检查

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
  map http://docker.mirrors.local/ https://registry-1.docker.io/
  map http://ghcr.mirrors.local/ https://ghcr.io/

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

## 待办/后续优化

- [ ] 测试更多容器镜像仓库的兼容性
- [ ] 添加 Prometheus 告警规则示例
- [ ] 考虑添加 HPA 基于自定义指标的伸缩

## 文档语言

本项目文档使用中文，因为是中文团队使用。
