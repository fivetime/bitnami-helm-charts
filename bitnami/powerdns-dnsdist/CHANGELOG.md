# Changelog

本文档记录 DNSdist Helm Chart 的所有重要变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.1.0] - 2026-01-17

### 新增 - Bitnami 命名风格完善

**新增标准参数**
- `automountServiceAccountToken`: 是否自动挂载 ServiceAccount Token（顶级参数）
- `hostIPC`: 是否启用主机 IPC
- `runtimeClassName`: Runtime class 名称

### 变更
- 与 PowerDNS Auth/Recursor Chart 保持一致的 Bitnami 命名风格
- 优化 deployment.yaml 中 hostNetwork/hostIPC 的渲染顺序

## [1.0.0] - 2026-01-16

### 新增
- 初始版本发布
- DNSdist 2.0.2 支持
- 多后端服务器池配置 (recursor, auth, external)
- DNS/DoH/DoT/DoQ/DoH3 多协议监听支持
- DNSCrypt 协议支持
- TLS 证书管理 (自签名/手动/cert-manager)
- 控制台访问 (Console) 支持
- Webserver API 支持
- 缓存配置
- ACL 访问控制
- 速率限制
- 域名阻止列表
- 智能路由规则
- Prometheus 监控指标
- HPA/VPA 自动伸缩
- NetworkPolicy 网络策略
- PodDisruptionBudget 支持
- Ingress 支持

---

## 版本兼容性

| Chart 版本 | DNSdist 版本 | Kubernetes 版本 | Helm 版本 |
|-----------|-------------|----------------|-----------|
| 1.1.x | 2.0.x | 1.25+ | 3.8+ |
| 1.0.x | 2.0.x | 1.25+ | 3.8+ |
