# Changelog

本文档记录 PowerDNS Authoritative Server Helm Chart 的所有重要变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.3.0] - 2026-01-17

### 新增 - Bitnami 命名风格完善

**新增标准参数**
- `automountServiceAccountToken`: 是否自动挂载 ServiceAccount Token
- `hostNetwork`: 是否启用主机网络
- `hostIPC`: 是否启用主机 IPC
- `dnsPolicy`: Pod 的 DNS 策略
- `dnsConfig`: Pod 的 DNS 配置
- `runtimeClassName`: Runtime class 名称
- `revisionHistoryLimit`: 保留的历史版本数量

### 变更
- 与 PowerDNS Recursor Chart 保持一致的 Bitnami 命名风格

## [1.2.0] - 2026-01-17

### 新增
- DNS UPDATE (RFC 2136) 支持
  - `config.allowDnsupdateFrom`: 允许发送 DNS UPDATE 的 IP
  - `config.dnsupdateRequireTsig`: 是否要求 TSIG 认证
  - `config.forwardDnsupdate`: 转发 DNS UPDATE 到主服务器
- HPA (Horizontal Pod Autoscaler) 自动伸缩
  - `autoscaling.hpa.enabled`: 启用 HPA
  - `autoscaling.hpa.minReplicas/maxReplicas`: 副本数范围
  - `autoscaling.hpa.targetCPU/targetMemory`: 目标资源使用率
- VPA (Vertical Pod Autoscaler) 支持
  - `autoscaling.vpa.enabled`: 启用 VPA
  - `autoscaling.vpa.updatePolicy`: 更新策略
- TSIG 声明式配置
  - `tsig.enabled`: 启用 TSIG
  - `tsig.keys`: TSIG 密钥列表
  - `tsig.existingSecret`: 引用外部 Secret
- LUA Records 支持
  - `config.enableLuaRecords`: 启用 LUA 记录
- Cache TTL 精细控制
  - `config.cacheTtl`: 缓存 TTL
  - `config.negqueryCacheTtl`: 负查询缓存 TTL
  - `config.queryCacheEnabled`: 启用查询缓存
- SOA 默认值配置
  - `config.defaultSoaContent`: 默认 SOA 内容
  - `config.defaultSoaMail`: 默认 SOA 邮箱
  - `config.defaultSoaName`: 默认 SOA 名称
  - `config.defaultTtl`: 默认 TTL
- 诊断模式
  - `diagnosticMode.enabled`: 启用诊断模式
  - `diagnosticMode.command/args`: 覆盖启动命令

### 变更
- 增强安全上下文配置
  - 新增 `seccompProfile` 支持
  - 新增 `capabilities.drop` 配置
  - 默认启用 `readOnlyRootFilesystem`
- 资源预设系统
  - 新增 `resourcesPreset` 支持 (none, nano, micro, small, medium, large, xlarge, 2xlarge)

### 修复
- 修复 README.md 中文编码问题

## [1.1.0] - 2026-01-16

### 新增
- GeoIP 后端支持
  - `geoip.enabled`: 启用 GeoIP 后端
  - `geoip.databases`: GeoIP 数据库路径
  - `geoipZones`: GeoIP 区域配置
  - `geoipVolume`: GeoIP 数据卷配置
- Primary/Secondary 区域传输
  - `config.primary`: 作为主服务器运行
  - `config.secondary`: 作为从服务器运行
  - `config.alsoNotify`: NOTIFY 目标列表
  - `config.autosecondary`: 自动从服务器模式
- Ingress 支持 API 访问
- ServiceMonitor 支持 Prometheus 监控
- NetworkPolicy 网络策略

### 变更
- 从 OpenStack-Helm 风格迁移到 Bitnami 风格
- 使用 bitnami/common 替代 helm-toolkit

## [1.0.0] - 2026-01-15

### 新增
- 初始版本发布
- PowerDNS Authoritative Server 5.0.2 支持
- PostgreSQL 和 MySQL 双数据库后端
- 数据库自动初始化 (db-init Job)
- Schema 自动同步 (db-sync Job)
- API/Webserver 支持
- 高可用部署支持 (多副本 + 共享数据库)
- Pod 反亲和性配置
- PodDisruptionBudget 支持
- 资源限制配置
- 健康检查探针 (startup, liveness, readiness)
- Service 类型配置 (ClusterIP, LoadBalancer, NodePort)
- existingSecret 支持引用外部 Secret

---

## 版本兼容性

| Chart 版本 | PowerDNS 版本 | Kubernetes 版本 | Helm 版本 |
|-----------|--------------|----------------|-----------|
| 1.3.x | 5.0.x | 1.25+ | 3.8+ |
| 1.2.x | 5.0.x | 1.25+ | 3.8+ |
| 1.1.x | 5.0.x | 1.25+ | 3.8+ |
| 1.0.x | 5.0.x | 1.25+ | 3.8+ |

## 升级指南

### 从 1.1.x 升级到 1.2.x

1.2.0 为向后兼容版本，无需修改现有配置即可升级。

新功能默认禁用，按需启用：

```yaml
# 启用 HPA
autoscaling:
  hpa:
    enabled: true

# 启用 TSIG
tsig:
  enabled: true
  keys:
    - name: transfer-key
      algorithm: hmac-sha256
      secret: "your-secret"
```

### 从 1.0.x 升级到 1.1.x

1.1.0 引入了 GeoIP 和区域传输支持，向后兼容。

如需启用新功能：

```yaml
# 启用 GeoIP
geoip:
  enabled: true

# 启用 Primary 模式
config:
  primary: true
  disableAxfr: false
```
