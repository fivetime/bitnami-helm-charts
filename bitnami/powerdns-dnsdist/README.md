# DNSdist Helm Chart

[DNSdist](https://dnsdist.org/) 是 PowerDNS 出品的高性能 DNS 负载均衡器和流量管理器。

## 概述

本 Chart 部署 DNSdist 到 Kubernetes 集群，基于 Bitnami 标准开发，提供以下特性：

- **多协议支持**: Do53、DoT、DoH、DoQ、DoH3、DNSCrypt
- **多后端池**: Recursor、Authoritative、External
- **企业级功能**: 缓存、限速、ACL、域名阻止列表
- **高可用**: PDB、HPA、VPA、反亲和性
- **可观测性**: Prometheus 指标、ServiceMonitor
- **安全加固**: 非 root 运行、NetworkPolicy、seccomp

## 先决条件

- Kubernetes 1.24+
- Helm 3.8+
- 后端 DNS 服务器 (PowerDNS Recursor/Authoritative 或其他)

## 安装

### 基本安装

```bash
helm install dnsdist ./dnsdist \
  --namespace dns \
  --create-namespace
```

### 生产环境安装

```bash
helm install dnsdist ./dnsdist \
  --namespace dns \
  --create-namespace \
  -f production-values.yaml
```

## 卸载

```bash
helm uninstall dnsdist --namespace dns
```

## 参数说明

### 全局参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `global.imageRegistry` | 全局 Docker 镜像仓库 | `""` |
| `global.imagePullSecrets` | 全局 Docker 镜像拉取密钥数组 | `[]` |
| `global.defaultStorageClass` | 全局默认 StorageClass | `""` |
| `global.security.allowInsecureImages` | 允许跳过镜像验证 | `false` |
| `global.compatibility.openshift.adaptSecurityContext` | 适配 OpenShift restricted-v2 SCC | `auto` |

### 通用参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `kubeVersion` | 覆盖 Kubernetes 版本检测 | `""` |
| `nameOverride` | 部分覆盖 common.names.fullname | `""` |
| `fullnameOverride` | 完全覆盖 common.names.fullname | `""` |
| `namespaceOverride` | 覆盖命名空间 | `""` |
| `commonLabels` | 添加到所有资源的标签 | `{}` |
| `commonAnnotations` | 添加到所有资源的注解 | `{}` |
| `clusterDomain` | Kubernetes 集群域名 | `cluster.local` |
| `extraDeploy` | 额外部署的资源数组 | `[]` |

### 诊断模式参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `diagnosticMode.enabled` | 启用诊断模式（禁用所有探针，覆盖命令） | `false` |
| `diagnosticMode.command` | 诊断模式下覆盖的命令 | `["sleep"]` |
| `diagnosticMode.args` | 诊断模式下覆盖的参数 | `["infinity"]` |

### DNSdist 镜像参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `image.registry` | DNSdist 镜像仓库 | `docker.io` |
| `image.repository` | DNSdist 镜像名称 | `powerdns/dnsdist-20` |
| `image.tag` | DNSdist 镜像标签 | `2.0.2` |
| `image.digest` | DNSdist 镜像摘要（覆盖 tag） | `""` |
| `image.pullPolicy` | DNSdist 镜像拉取策略 | `IfNotPresent` |
| `image.pullSecrets` | DNSdist 镜像拉取密钥 | `[]` |

### 部署参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `replicaCount` | DNSdist 副本数 | `2` |
| `revisionHistoryLimit` | 保留的历史版本数用于回滚 | `10` |
| `hostNetwork` | 启用主机网络 | `false` |
| `dnsPolicy` | Pod DNS 策略 | `""` |
| `dnsConfig` | Pod DNS 配置 | `{}` |
| `updateStrategy.type` | 更新策略类型 | `RollingUpdate` |
| `terminationGracePeriodSeconds` | 优雅终止等待秒数 | `30` |
| `schedulerName` | 调度器名称 | `""` |
| `priorityClassName` | Pod 优先级类名称 | `""` |
| `topologySpreadConstraints` | 拓扑分布约束 | `[]` |
| `command` | 覆盖默认容器命令 | `[]` |
| `args` | 覆盖默认容器参数 | `[]` |
| `hostAliases` | Pod 主机别名 | `[]` |
| `podLabels` | Pod 额外标签 | `{}` |
| `podAnnotations` | Pod 额外注解 | `{}` |
| `lifecycleHooks` | 容器生命周期钩子 | `{}` |
| `extraEnvVars` | 额外环境变量数组 | `[]` |
| `extraEnvVarsCM` | 包含额外环境变量的 ConfigMap 名称 | `""` |
| `extraEnvVarsSecret` | 包含额外环境变量的 Secret 名称 | `""` |
| `extraVolumes` | 额外卷数组 | `[]` |
| `extraVolumeMounts` | 额外卷挂载数组 | `[]` |
| `sidecars` | 额外 sidecar 容器 | `[]` |
| `initContainers` | 额外 init 容器 | `[]` |

### 健康检查参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `livenessProbe.enabled` | 启用存活探针 | `true` |
| `livenessProbe.initialDelaySeconds` | 存活探针初始延迟秒数 | `15` |
| `livenessProbe.periodSeconds` | 存活探针周期秒数 | `20` |
| `livenessProbe.timeoutSeconds` | 存活探针超时秒数 | `5` |
| `livenessProbe.failureThreshold` | 存活探针失败阈值 | `3` |
| `livenessProbe.successThreshold` | 存活探针成功阈值 | `1` |
| `readinessProbe.enabled` | 启用就绪探针 | `true` |
| `readinessProbe.initialDelaySeconds` | 就绪探针初始延迟秒数 | `5` |
| `readinessProbe.periodSeconds` | 就绪探针周期秒数 | `10` |
| `readinessProbe.timeoutSeconds` | 就绪探针超时秒数 | `5` |
| `readinessProbe.failureThreshold` | 就绪探针失败阈值 | `3` |
| `readinessProbe.successThreshold` | 就绪探针成功阈值 | `1` |
| `startupProbe.enabled` | 启用启动探针 | `true` |
| `startupProbe.initialDelaySeconds` | 启动探针初始延迟秒数 | `5` |
| `startupProbe.periodSeconds` | 启动探针周期秒数 | `5` |
| `startupProbe.timeoutSeconds` | 启动探针超时秒数 | `3` |
| `startupProbe.failureThreshold` | 启动探针失败阈值 | `30` |
| `startupProbe.successThreshold` | 启动探针成功阈值 | `1` |
| `customLivenessProbe` | 自定义存活探针（覆盖默认） | `{}` |
| `customReadinessProbe` | 自定义就绪探针（覆盖默认） | `{}` |
| `customStartupProbe` | 自定义启动探针（覆盖默认） | `{}` |

### 资源参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `resourcesPreset` | 资源预设 (none/nano/micro/small/medium/large/xlarge/2xlarge) | `small` |
| `resources` | 自定义资源限制（覆盖预设） | `{}` |

### Pod 安全上下文参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `podSecurityContext.enabled` | 启用 Pod 安全上下文 | `true` |
| `podSecurityContext.fsGroupChangePolicy` | 文件系统组变更策略 | `Always` |
| `podSecurityContext.sysctls` | 内核参数设置 | `[]` |
| `podSecurityContext.supplementalGroups` | 补充组 | `[]` |
| `podSecurityContext.fsGroup` | 文件系统组 ID | `953` |

### 容器安全上下文参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `containerSecurityContext.enabled` | 启用容器安全上下文 | `true` |
| `containerSecurityContext.seLinuxOptions` | SELinux 选项 | `{}` |
| `containerSecurityContext.runAsUser` | 运行用户 ID | `953` |
| `containerSecurityContext.runAsGroup` | 运行组 ID | `953` |
| `containerSecurityContext.runAsNonRoot` | 以非 root 运行 | `true` |
| `containerSecurityContext.readOnlyRootFilesystem` | 只读根文件系统 | `false` |
| `containerSecurityContext.privileged` | 特权模式 | `false` |
| `containerSecurityContext.allowPrivilegeEscalation` | 允许提权 | `false` |
| `containerSecurityContext.capabilities.drop` | 要删除的 Linux 能力 | `["ALL"]` |
| `containerSecurityContext.seccompProfile.type` | Seccomp 配置文件类型 | `RuntimeDefault` |

### 亲和性参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `affinity` | Pod 亲和性配置 | `{}` |
| `nodeSelector` | 节点选择器 | `{}` |
| `tolerations` | Pod 容忍配置 | `[]` |
| `podAffinityPreset` | Pod 亲和性预设 (soft/hard) | `""` |
| `podAntiAffinityPreset` | Pod 反亲和性预设 (soft/hard) | `soft` |
| `nodeAffinityPreset.type` | 节点亲和性类型 (soft/hard) | `""` |
| `nodeAffinityPreset.key` | 节点亲和性标签键 | `""` |
| `nodeAffinityPreset.values` | 节点亲和性标签值 | `[]` |

### 后端服务器参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `backends.recursor.enabled` | 启用 Recursor 后端池 | `true` |
| `backends.recursor.servers` | Recursor 服务器列表 [{name, address, port}] | `[{name: recursor, address: pdns-recursor, port: 53}]` |
| `backends.recursor.pool` | Recursor 池名称 | `recursor` |
| `backends.recursor.healthCheck.mode` | 健康检查模式 (lazy/up/down/auto) | `lazy` |
| `backends.recursor.healthCheck.interval` | 健康检查间隔秒数 | `5` |
| `backends.recursor.useClientSubnet` | 启用 EDNS Client Subnet | `true` |
| `backends.auth.enabled` | 启用 Authoritative 后端池 | `false` |
| `backends.auth.servers` | Auth 服务器列表 | `[{name: auth, address: pdns-auth, port: 53}]` |
| `backends.auth.pool` | Auth 池名称 | `auth` |
| `backends.auth.healthCheck.mode` | 健康检查模式 | `lazy` |
| `backends.auth.healthCheck.interval` | 健康检查间隔秒数 | `5` |
| `backends.auth.useClientSubnet` | 启用 EDNS Client Subnet | `true` |
| `backends.external.enabled` | 启用外部上游池 | `false` |
| `backends.external.servers` | 外部服务器列表 | `[]` |
| `backends.external.pool` | External 池名称 | `external` |
| `backends.external.healthCheck.mode` | 健康检查模式 | `lazy` |
| `backends.external.healthCheck.interval` | 健康检查间隔秒数 | `10` |

### Do53 监听器参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `listeners.dns.enabled` | 启用 Do53 监听器 | `true` |
| `listeners.dns.address` | 绑定地址 | `0.0.0.0` |
| `listeners.dns.port` | 监听端口 | `53` |
| `listeners.dns.tcpFastOpen` | TCP Fast Open 队列大小 | `64` |

### DoT 监听器参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `listeners.dot.enabled` | 启用 DoT 监听器 | `false` |
| `listeners.dot.address` | 绑定地址 | `0.0.0.0` |
| `listeners.dot.port` | 监听端口 | `853` |
| `listeners.dot.minTLSVersion` | 最低 TLS 版本 | `tls1.2` |
| `listeners.dot.ciphers` | TLS 加密套件（空=默认） | `""` |
| `listeners.dot.numberOfTicketsKeys` | TLS 会话票据密钥数量 | `5` |

### DoH 监听器参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `listeners.doh.enabled` | 启用 DoH 监听器 | `false` |
| `listeners.doh.address` | 绑定地址 | `0.0.0.0` |
| `listeners.doh.port` | 监听端口 | `443` |
| `listeners.doh.path` | DoH 查询路径 | `/dns-query` |
| `listeners.doh.minTLSVersion` | 最低 TLS 版本 | `tls1.2` |
| `listeners.doh.additionalPaths` | 额外 DoH 路径 | `[]` |
| `listeners.doh.customResponses` | 自定义 HTTP 响应 | `[{path: /health, status: 200, content: OK, contentType: text/plain}]` |

### DoQ 监听器参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `listeners.doq.enabled` | 启用 DoQ 监听器 | `false` |
| `listeners.doq.address` | 绑定地址 | `0.0.0.0` |
| `listeners.doq.port` | 监听端口 | `8853` |
| `listeners.doq.idleTimeout` | 空闲超时秒数 | `30` |

### DoH3 监听器参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `listeners.doh3.enabled` | 启用 DoH3 监听器 | `false` |
| `listeners.doh3.address` | 绑定地址 | `0.0.0.0` |
| `listeners.doh3.port` | 监听端口 | `8443` |
| `listeners.doh3.path` | DoH3 查询路径 | `/dns-query` |
| `listeners.doh3.idleTimeout` | 空闲超时秒数 | `30` |

### DNSCrypt 监听器参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `listeners.dnscrypt.enabled` | 启用 DNSCrypt 监听器 | `false` |
| `listeners.dnscrypt.address` | 绑定地址 | `0.0.0.0` |
| `listeners.dnscrypt.port` | 监听端口 | `8443` |
| `listeners.dnscrypt.providerName` | 提供者名称（必须以"2."开头） | `2.dnscrypt-cert.example.com` |
| `listeners.dnscrypt.certValidity` | 证书有效期（天） | `365` |

### TLS 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `tls.existingSecret` | 包含 TLS 证书的现有 Secret 名称 | `""` |
| `tls.cert` | TLS 证书内容 | `""` |
| `tls.key` | TLS 私钥内容 | `""` |
| `tls.ca` | CA 证书内容（可选） | `""` |

### 控制台参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `console.enabled` | 启用控制台 | `true` |
| `console.address` | 控制台绑定地址 | `127.0.0.1` |
| `console.port` | 控制台端口 | `5199` |
| `console.key` | 控制台密钥（空则自动生成） | `""` |
| `console.acl` | 控制台访问控制列表 | `["127.0.0.0/8", "::1/128"]` |

### Webserver/API 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `webserver.enabled` | 启用 Webserver/API | `true` |
| `webserver.address` | 绑定地址 | `0.0.0.0` |
| `webserver.port` | 监听端口 | `8083` |
| `webserver.password` | Webserver 密码（空则自动生成） | `""` |
| `webserver.apiKey` | API 密钥（空则自动生成） | `""` |
| `webserver.acl` | 访问控制列表 | `0.0.0.0/0, ::/0` |
| `webserver.statsRequireAuth` | 统计信息需要认证 | `true` |

### 缓存参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `cache.enabled` | 启用数据包缓存 | `true` |
| `cache.size` | 缓存条目数量 | `100000` |
| `cache.maxTTL` | 最大 TTL 秒数 | `86400` |
| `cache.minTTL` | 最小 TTL 秒数 | `0` |
| `cache.stale.enabled` | 启用过期数据服务 | `true` |
| `cache.stale.ttl` | 过期数据 TTL 秒数 | `60` |
| `cache.negativeTTL` | 负缓存 TTL 秒数 | `60` |

### ACL 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `acl.allowed` | 允许的客户端网络列表 | `["0.0.0.0/0", "::/0"]` |
| `acl.blocked` | 阻止的网络列表（优先处理） | `[]` |

### 限速参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `rateLimit.enabled` | 启用限速 | `true` |
| `rateLimit.delayThreshold` | 开始延迟的 QPS/IP 阈值 | `100` |
| `rateLimit.delayMs` | 延迟毫秒数 | `100` |
| `rateLimit.dropThreshold` | 开始丢弃的 QPS/IP 阈值 | `500` |
| `rateLimit.ipv4PrefixLength` | IPv4 前缀长度 | `32` |
| `rateLimit.ipv6PrefixLength` | IPv6 前缀长度 | `64` |

### 安全规则参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `security.dropChaos` | 丢弃 CHAOS 类查询 | `true` |
| `security.dropAny` | 丢弃 ANY 查询 | `false` |
| `security.minTTL` | 返回客户端的最小 TTL | `0` |
| `security.maxTTL` | 返回客户端的最大 TTL | `86400` |

### 阻止列表参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `blocklist.enabled` | 启用域名阻止列表 | `false` |
| `blocklist.action` | 阻止动作 (Drop/Refused/ServFail/NoData) | `ServFail` |
| `blocklist.domains` | 要阻止的域名列表 | `[]` |
| `blocklist.externalUrl` | 外部阻止列表 URL | `""` |
| `blocklist.batchSize` | 批量加载大小（内存优化） | `10000` |

### 路由参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `routing.defaultPool` | 默认查询池 | `recursor` |
| `routing.rules` | 自定义路由规则列表 | `[]` |

### 日志参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `logging.queries` | 记录查询到 stdout | `false` |
| `logging.verbose` | 启用详细模式 | `false` |
| `logging.responses` | 记录响应 | `false` |

### 扩展配置参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `extraConfig` | 追加到主配置的额外 Lua 代码 | `""` |
| `extraConfigFiles` | 额外配置文件（通过 includeDirectory 包含） | `{}` |

### Service 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `service.enabled` | 启用 Service | `true` |
| `service.type` | Service 类型 | `LoadBalancer` |
| `service.ports.dns` | DNS 服务端口 | `53` |
| `service.ports.dot` | DoT 服务端口 | `853` |
| `service.ports.doh` | DoH 服务端口 | `443` |
| `service.ports.doq` | DoQ 服务端口 | `8853` |
| `service.ports.doh3` | DoH3 服务端口 | `8443` |
| `service.ports.dnscrypt` | DNSCrypt 服务端口 | `8443` |
| `service.ports.webserver` | Webserver 服务端口 | `8083` |
| `service.nodePorts.dns` | DNS NodePort | `""` |
| `service.nodePorts.dot` | DoT NodePort | `""` |
| `service.nodePorts.doh` | DoH NodePort | `""` |
| `service.nodePorts.doq` | DoQ NodePort | `""` |
| `service.nodePorts.doh3` | DoH3 NodePort | `""` |
| `service.nodePorts.dnscrypt` | DNSCrypt NodePort | `""` |
| `service.nodePorts.webserver` | Webserver NodePort | `""` |
| `service.clusterIP` | Service ClusterIP | `""` |
| `service.loadBalancerIP` | LoadBalancer IP | `""` |
| `service.loadBalancerSourceRanges` | LoadBalancer 源地址范围 | `[]` |
| `service.externalIPs` | Service 外部 IP 地址 | `[]` |
| `service.externalTrafficPolicy` | 外部流量策略 | `Local` |
| `service.annotations` | Service 注解 | `{}` |
| `service.extraPorts` | Service 额外端口 | `[]` |
| `service.sessionAffinity` | 会话亲和性 | `None` |
| `service.sessionAffinityConfig` | 会话亲和性配置 | `{}` |

### Ingress 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `ingress.enabled` | 启用 DoH Ingress | `false` |
| `ingress.pathType` | Ingress 路径类型 | `Prefix` |
| `ingress.apiVersion` | 强制 Ingress API 版本 | `""` |
| `ingress.hostname` | 默认主机名 | `dns.example.com` |
| `ingress.ingressClassName` | IngressClass 名称 | `""` |
| `ingress.path` | DoH 默认路径 | `/dns-query` |
| `ingress.annotations` | Ingress 注解 | `{}` |
| `ingress.tls` | 启用 TLS | `false` |
| `ingress.selfSigned` | 使用自签名证书 | `false` |
| `ingress.extraHosts` | 额外主机名配置 | `[]` |
| `ingress.extraPaths` | 额外路径配置 | `[]` |
| `ingress.extraTls` | 额外 TLS 配置 | `[]` |
| `ingress.secrets` | 自定义 TLS 证书 Secret | `[]` |
| `ingress.extraRules` | 额外 Ingress 规则 | `[]` |

### 持久化参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `persistence.enabled` | 启用 DNSCrypt 密钥持久化 | `false` |
| `persistence.mountPath` | 挂载路径 | `/var/lib/dnsdist` |
| `persistence.storageClass` | 存储类 | `""` |
| `persistence.annotations` | PVC 注解 | `{}` |
| `persistence.accessModes` | PV 访问模式 | `["ReadWriteOnce"]` |
| `persistence.size` | PV 大小 | `100Mi` |
| `persistence.existingClaim` | 使用现有 PVC | `""` |
| `persistence.selector` | PV 选择器 | `{}` |

### ServiceAccount 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `serviceAccount.create` | 创建 ServiceAccount | `true` |
| `serviceAccount.name` | ServiceAccount 名称 | `""` |
| `serviceAccount.annotations` | ServiceAccount 注解 | `{}` |
| `serviceAccount.automountServiceAccountToken` | 自动挂载服务账户令牌 | `false` |

### NetworkPolicy 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `networkPolicy.enabled` | 启用 NetworkPolicy | `true` |
| `networkPolicy.allowExternal` | 允许外部连接（无需客户端标签） | `true` |
| `networkPolicy.allowExternalEgress` | 允许任意出站连接 | `true` |
| `networkPolicy.extraIngress` | 额外入站规则 | `[]` |
| `networkPolicy.extraEgress` | 额外出站规则 | `[]` |
| `networkPolicy.ingressNSMatchLabels` | 允许入站流量的命名空间标签 | `{}` |
| `networkPolicy.ingressNSPodMatchLabels` | 允许入站流量的 Pod 标签 | `{}` |

### PDB 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `pdb.create` | 创建 PodDisruptionBudget | `true` |
| `pdb.minAvailable` | 最小可用 Pod 数/百分比 | `1` |
| `pdb.maxUnavailable` | 最大不可用 Pod 数/百分比 | `""` |

### HPA 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `autoscaling.hpa.enabled` | 启用 HPA | `false` |
| `autoscaling.hpa.minReplicas` | 最小副本数 | `2` |
| `autoscaling.hpa.maxReplicas` | 最大副本数 | `10` |
| `autoscaling.hpa.targetCPU` | CPU 目标百分比 | `70` |
| `autoscaling.hpa.targetMemory` | 内存目标百分比 | `""` |

### VPA 参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `autoscaling.vpa.enabled` | 启用 VPA | `false` |
| `autoscaling.vpa.annotations` | VPA 注解 | `{}` |
| `autoscaling.vpa.controlledResources` | VPA 控制的资源列表 | `[]` |
| `autoscaling.vpa.maxAllowed` | VPA 最大允许资源 | `{}` |
| `autoscaling.vpa.minAllowed` | VPA 最小允许资源 | `{}` |
| `autoscaling.vpa.updatePolicy.updateMode` | VPA 更新模式 | `Auto` |

### 监控参数

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `metrics.enabled` | 启用 Prometheus 指标端点 | `false` |
| `metrics.serviceMonitor.enabled` | 创建 ServiceMonitor 资源 | `false` |
| `metrics.serviceMonitor.namespace` | ServiceMonitor 命名空间 | `""` |
| `metrics.serviceMonitor.interval` | 采集间隔 | `30s` |
| `metrics.serviceMonitor.scrapeTimeout` | 采集超时 | `10s` |
| `metrics.serviceMonitor.relabelings` | 采集前重标签配置 | `[]` |
| `metrics.serviceMonitor.metricRelabelings` | 摄入前指标重标签配置 | `[]` |
| `metrics.serviceMonitor.selector` | Prometheus 实例选择器标签 | `{}` |
| `metrics.serviceMonitor.labels` | ServiceMonitor 额外标签 | `{}` |
| `metrics.serviceMonitor.honorLabels` | 尊重指标标签 | `false` |
| `metrics.serviceMonitor.jobLabel` | 目标服务上用作 Prometheus job 名称的标签 | `""` |

## 配置示例

### 基本配置

```yaml
replicaCount: 2

backends:
  recursor:
    enabled: true
    servers:
      - name: recursor1
        address: 10.0.0.1
        port: 53
      - name: recursor2
        address: 10.0.0.2
        port: 53
```

### 启用加密 DNS

```yaml
listeners:
  dot:
    enabled: true
  doh:
    enabled: true
    additionalPaths:
      - /resolve

tls:
  existingSecret: my-tls-secret
```

### 高可用配置

```yaml
replicaCount: 3

autoscaling:
  hpa:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPU: 70

pdb:
  create: true
  minAvailable: 2

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: dnsdist
```

### 域名阻止列表

```yaml
blocklist:
  enabled: true
  action: Refused
  domains:
    - ads.example.com
    - tracking.example.com
  batchSize: 10000
```

### 路由规则

```yaml
backends:
  recursor:
    enabled: true
    servers:
      - name: internal
        address: 10.0.0.1
        port: 53
  auth:
    enabled: true
    servers:
      - name: auth
        address: 10.0.0.2
        port: 53

routing:
  defaultPool: recursor
  rules:
    - name: internal-zones
      match:
        type: suffix
        value: internal.local
      action:
        pool: auth
```

### 监控配置

```yaml
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
    interval: 15s
    labels:
      release: prometheus
```

## 故障排查

### 查看日志

```bash
kubectl logs -f deployment/dnsdist -n dns
```

### 访问控制台

```bash
kubectl exec -it deployment/dnsdist -n dns -- dnsdist -c
```

### 常见问题

1. **Pod 无法启动**: 检查后端服务器是否可达
2. **DoT/DoH 不工作**: 确认 TLS 证书已配置
3. **限速过于激进**: 调整 `rateLimit.delayThreshold` 和 `rateLimit.dropThreshold`

## 许可证

Apache License 2.0

## 参考资料

- [DNSdist 文档](https://dnsdist.org/)
- [PowerDNS 官网](https://www.powerdns.com/)
