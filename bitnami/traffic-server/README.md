<!--- app-name: Apache Traffic Server -->

# Bitnami 风格 Helm Chart for Apache Traffic Server

Apache Traffic Server (ATS) 是一个高性能的 HTTP 代理和缓存服务器，可用作正向代理、反向代理和 CDN。非常适合构建企业级缓存基础设施和镜像服务。

[Apache Traffic Server 概述](https://trafficserver.apache.org)

商标声明: 此软件列表由 Bitnami 打包。提及的各商标归其各自公司所有，使用它们并不意味着任何隶属关系或认可。

## TL;DR

```console
helm install my-release oci://registry-1.docker.io/bitnamicharts/trafficserver
```

## 简介

此 chart 使用 [Helm](https://helm.sh) 包管理器在 [Kubernetes](https://kubernetes.io) 集群上部署 [Apache Traffic Server](https://trafficserver.apache.org)。

## 前提条件

- Kubernetes 1.23+
- Helm 3.8.0+
- 支持 ReadWriteMany 访问模式的存储类（如 CephFS，用于高可用部署）

## 安装 Chart

使用发布名称 `my-release` 安装 chart：

```console
helm install my-release oci://REGISTRY_NAME/REPOSITORY_NAME/trafficserver
```

> 注意: 您需要将占位符 `REGISTRY_NAME` 和 `REPOSITORY_NAME` 替换为您的 Helm chart 注册表和仓库的引用。

这些命令使用默认配置在 Kubernetes 集群上部署 Apache Traffic Server。

> **提示**: 使用 `helm list` 列出所有发布

## 支持的配置文件

此 Helm Chart 支持 Apache Traffic Server 的所有官方配置文件：

| 配置文件 | 用途 | 默认启用 |
|---------|------|----------|
| `records.yaml` | 核心配置（线程、缓存、网络、SSL等） | ✅ 是 |
| `remap.config` | URL重映射规则 | ✅ 是 |
| `plugin.config` | 插件配置 | ✅ 是 |
| `storage.config` | 缓存存储配置 | ✅ 是 |
| `ip_allow.yaml` | IP访问控制 | ✅ 是 |
| `logging.yaml` | 日志格式和输出配置 | ✅ 是 |
| `jsonrpc.yaml` | JSON-RPC管理接口 | ✅ 是 |
| `sni.yaml` | SNI/TLS配置 | 可选 |
| `cache.config` | 缓存策略规则 | 可选 |
| `parent.config` | 父代理配置 | 可选 |
| `strategies.yaml` | 上游路由策略 | 可选 |
| `ssl_multicert.config` | SSL多证书配置 | 可选 |
| `hosting.config` | 卷分配配置 | 可选 |
| `volume.config` | 缓存卷定义 | 可选 |
| `splitdns.config` | DNS分离配置 | 可选 |
| `socks.config` | SOCKS代理配置 | 可选 |
| `body_factory` | 自定义错误页面 | 可选 |

## 配置和安装详情

### 资源请求和限制

Bitnami charts 允许为所有容器设置资源请求和限制。这些设置在 `resources` 值中（参见参数表）。为生产工作负载设置请求至关重要，这些应根据您的具体用例进行调整。

为简化此过程，chart 包含 `resourcesPreset` 值，它会根据不同的预设自动设置 `resources` 部分。在 [bitnami/common chart](https://github.com/bitnami/charts/blob/main/bitnami/common/templates/_resources.tpl#L15) 中查看这些预设。但是，在生产工作负载中不建议使用 `resourcesPreset`，因为它可能无法完全适应您的特定需求。

### 配置 URL 重映射规则

remap.config 文件控制 Apache Traffic Server 如何处理传入请求。您可以通过 `remapConfig` 值配置它：

```yaml
remapConfig: |
  # Ubuntu 镜像
  map http://ubuntu.mirrors.example.local/ http://jp.archive.ubuntu.com/ubuntu/
  
  # Debian 镜像
  map http://debian.mirrors.example.local/ http://deb.debian.org/debian/
  
  # CentOS 镜像
  map http://centos.mirrors.example.local/ http://mirror.centos.org/centos/
```

### 配置缓存存储

使用 `storageConfig` 值配置缓存存储：

```yaml
storageConfig: |
  /opt/var/cache/trafficserver 2G
```

### 配置 IP 访问控制

使用 `ipAllowConfig` 值配置 IP 访问控制：

```yaml
ipAllowConfig: |
  ip_allow:
    - apply: in
      ip_addrs: 127.0.0.1
      action: allow
      methods: ALL
    - apply: in
      ip_addrs: 10.0.0.0/8
      action: allow
      methods:
        - GET
        - HEAD
        - POST
    - apply: in
      ip_addrs: 0/0
      action: deny
      methods:
        - PURGE
        - PUSH
        - DELETE
```

### 配置日志格式

使用 `loggingConfig` 值配置日志格式：

```yaml
loggingConfig: |
  logging:
    formats:
      - name: squid
        format: '%<cqtq> %<ttms> %<chi> %<crc>/%<pssc> %<psql> %<cqhm> %<pquc> %<caun> %<phr>/%<shn> %<psct>'
      - name: combined
        format: '%<chi> - %<caun> [%<cqtn>] "%<cqhm> %<pqu> %<cqpv>" %<pssc> %<pscl> "%<{Referer}cqh>" "%<{User-Agent}cqh>"'
    logs:
      - filename: access
        format: combined
        mode: ascii
```

### 配置 SNI/TLS

使用 `sniConfig` 值配置基于 SNI 的 TLS 设置：

```yaml
sniConfig: |
  sni:
    - fqdn: api.example.com
      http2: on
      verify_server_policy: ENFORCED
      verify_client: MODERATE
    - fqdn: legacy.example.com
      http2: off
      valid_tls_version_min_in: TLSv1_2
    - fqdn: tunnel.example.com
      tunnel_route: backend.example.com:443
      ip_allow: '10.0.0.0/8'
```

### 配置缓存策略

使用 `cacheConfig` 值配置细粒度的缓存策略：

```yaml
cacheConfig: |
  # 静态资源长期缓存
  dest_domain=static.example.com ttl-in-cache=30d
  
  # API 响应短期缓存
  dest_domain=api.example.com revalidate=60
  
  # 图片资源缓存
  url_regex=\.(jpg|jpeg|png|gif|webp)$ ttl-in-cache=7d
  
  # 禁止缓存敏感路径
  url_regex=/admin/.* action=never-cache
```

### 配置父代理

使用 `parentConfig` 值配置上游父代理：

```yaml
parentConfig: |
  # 所有请求通过父代理集群，轮询负载均衡
  dest_domain=. parent="proxy1.example.com:8080; proxy2.example.com:8080" round_robin=strict
  
  # 特定域名直连
  dest_domain=internal.example.com go_direct=true
```

### 配置上游路由策略

使用 `strategiesConfig` 值配置高级上游路由策略：

```yaml
strategiesConfig: |
  hosts:
    - &upstream1
      host: upstream1.example.com
      protocol:
        - scheme: http
          port: 80
          health_check_url: http://upstream1.example.com/health
    - &upstream2
      host: upstream2.example.com
      protocol:
        - scheme: http
          port: 80
          health_check_url: http://upstream2.example.com/health
  groups:
    - &primary
      - <<: *upstream1
        weight: 1.0
      - <<: *upstream2
        weight: 1.0
  strategies:
    - strategy: 'default-strategy'
      policy: consistent_hash
      hash_key: url
      go_direct: false
      groups:
        - *primary
      failover:
        max_simple_retries: 2
        ring_mode: exhaust_ring
        response_codes:
          - 502
          - 503
        health_check:
          - passive
```

### 配置 SSL 多证书

使用 `sslMulticertConfig` 值配置多个 SSL 证书：

```yaml
sslMulticertConfig: |
  # 默认证书
  dest_ip=* ssl_cert_name=default.pem ssl_key_name=default.key
  
  # 特定域名证书
  ssl_cert_name=api.example.com.pem ssl_key_name=api.example.com.key
  ssl_cert_name=www.example.com.pem ssl_key_name=www.example.com.key
```

### 配置自定义错误页面

使用 `bodyFactory` 值配置自定义错误页面：

```yaml
bodyFactory:
  enabled: true
  templates:
    default: |
      <!DOCTYPE html>
      <html>
      <head><title>Error</title></head>
      <body>
        <h1>Service Unavailable</h1>
        <p>Please try again later.</p>
      </body>
      </html>
    "connect#dns_failed": |
      <!DOCTYPE html>
      <html>
      <head><title>DNS Error</title></head>
      <body>
        <h1>Unable to resolve hostname</h1>
        <p>The requested server could not be found.</p>
      </body>
      </html>
```

### 使用现有 ConfigMap

如果您有预先存在的配置，可以使用现有的 ConfigMap：

```yaml
existingRecordsConfigmap: my-records-config
existingRemapConfigmap: my-remap-config
existingPluginConfigmap: my-plugin-config
existingStorageConfigmap: my-storage-config
existingIpAllowConfigmap: my-ip-allow-config
existingSniConfigmap: my-sni-config
existingLoggingConfigmap: my-logging-config
existingCacheConfigmap: my-cache-config
existingParentConfigmap: my-parent-config
existingStrategiesConfigmap: my-strategies-config
existingSslMulticertConfigmap: my-ssl-multicert-config
existingHostingConfigmap: my-hosting-config
existingVolumeConfigmap: my-volume-config
existingSplitdnsConfigmap: my-splitdns-config
existingSocksConfigmap: my-socks-config
existingJsonrpcConfigmap: my-jsonrpc-config
```

### 启用持久化

使用 `persistence` 值启用缓存数据持久化：

```yaml
persistence:
  enabled: true
  storageClass: "general-fs"
  accessModes:
    - ReadWriteMany
  size: 2Ti
```

### 高可用部署

要部署高可用配置：

```yaml
replicaCount: 3

autoscaling:
  hpa:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPU: 70
    targetMemory: 80

podAntiAffinityPreset: hard

persistence:
  enabled: true
  accessModes:
    - ReadWriteMany
```

### 垂直自动伸缩 (VPA)

启用 Vertical Pod Autoscaler 自动调整资源：

```yaml
autoscaling:
  vpa:
    enabled: true
    minAllowed:
      cpu: 100m
      memory: 128Mi
    maxAllowed:
      cpu: 4
      memory: 8Gi
    controlledResources:
      - cpu
      - memory
    controlledValues: RequestsAndLimits
    updatePolicy:
      updateMode: Auto
```

> **注意**: VPA 需要在集群中预先安装 [Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)。`controlledResources` 默认为 `["cpu", "memory"]`，如果设置为空数组会显示验证警告。

### Prometheus 监控

启用 Prometheus 监控：

```yaml
metrics:
  enabled: true
  serviceMonitor:
    enabled: true
```

## 参数

### 全局参数

| 名称                                                    | 描述                                                                                                                                                                                                          | 值      |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `global.imageRegistry`                                  | 全局 Docker 镜像注册表                                                                                                                                                                                        | `""`    |
| `global.imagePullSecrets`                               | 全局 Docker 注册表密钥名称数组                                                                                                                                                                                | `[]`    |
| `global.security.allowInsecureImages`                   | 允许跳过镜像验证                                                                                                                                                                                              | `false` |
| `global.compatibility.openshift.adaptSecurityContext`   | 调整 securityContext 以兼容 Openshift restricted-v2 SCC                                                                                                                                                       | `auto`  |

### 通用参数

| 名称                    | 描述                                                                                   | 值              |
| ----------------------- | -------------------------------------------------------------------------------------- | --------------- |
| `nameOverride`          | 部分覆盖 trafficserver.fullname 模板的字符串                                           | `""`            |
| `fullnameOverride`      | 完全覆盖 trafficserver.fullname 模板的字符串                                           | `""`            |
| `namespaceOverride`     | 完全覆盖 common.names.namespace 的字符串                                               | `""`            |
| `kubeVersion`           | 强制目标 Kubernetes 版本                                                               | `""`            |
| `clusterDomain`         | Kubernetes 集群域                                                                      | `cluster.local` |
| `extraDeploy`           | 额外要部署的对象（值作为模板评估）                                                     | `[]`            |
| `commonLabels`          | 添加到所有部署资源的标签                                                               | `{}`            |
| `commonAnnotations`     | 添加到所有部署资源的注释                                                               | `{}`            |
| `diagnosticMode.enabled`| 启用诊断模式（所有探针将被禁用，命令将被覆盖）                                         | `false`         |
| `diagnosticMode.command`| 覆盖部署中所有容器的命令                                                               | `["sleep"]`     |
| `diagnosticMode.args`   | 覆盖部署中所有容器的参数                                                               | `["infinity"]`  |

### Apache Traffic Server 参数

| 名称                    | 描述                                                                                   | 值                                 |
| ----------------------- | -------------------------------------------------------------------------------------- | ---------------------------------- |
| `image.registry`        | Apache Traffic Server 镜像注册表                                                       | `docker.io`                        |
| `image.repository`      | Apache Traffic Server 镜像仓库                                                         | `trafficserver/trafficserver`      |
| `image.tag`             | Apache Traffic Server 镜像标签                                                         | `latest`                           |
| `image.digest`          | Apache Traffic Server 镜像摘要                                                         | `""`                               |
| `image.pullPolicy`      | Apache Traffic Server 镜像拉取策略                                                     | `IfNotPresent`                     |
| `image.pullSecrets`     | Docker 注册表密钥名称数组                                                              | `[]`                               |
| `image.debug`           | 设置为 true 以在日志中查看额外信息                                                     | `false`                            |

### Apache Traffic Server 配置参数

| 名称                    | 描述                                                                                   | 值                                 |
| ----------------------- | -------------------------------------------------------------------------------------- | ---------------------------------- |
| `recordsConfig`         | records.yaml 核心配置（YAML格式）                                                      | 见 values.yaml                     |
| `remapConfig`           | remap.config URL重映射规则                                                             | `""`                               |
| `pluginConfig`          | plugin.config 插件配置                                                                 | `stats_over_http.so`               |
| `storageConfig`         | storage.config 缓存存储配置                                                            | `/opt/var/cache/trafficserver 256M`|
| `ipAllowConfig`         | ip_allow.yaml IP访问控制                                                               | 见 values.yaml                     |
| `sniConfig`             | sni.yaml SNI/TLS配置                                                                   | `""`                               |
| `loggingConfig`         | logging.yaml 日志配置                                                                  | 见 values.yaml                     |
| `cacheConfig`           | cache.config 缓存策略                                                                  | `""`                               |
| `parentConfig`          | parent.config 父代理配置                                                               | `""`                               |
| `strategiesConfig`      | strategies.yaml 上游路由策略                                                           | `""`                               |
| `sslMulticertConfig`    | ssl_multicert.config SSL多证书                                                         | `""`                               |
| `hostingConfig`         | hosting.config 卷分配配置                                                              | `""`                               |
| `volumeConfig`          | volume.config 缓存卷定义                                                               | `""`                               |
| `splitdnsConfig`        | splitdns.config DNS分离配置                                                            | `""`                               |
| `socksConfig`           | socks.config SOCKS代理配置                                                             | `""`                               |
| `jsonrpcConfig`         | jsonrpc.yaml JSON-RPC接口配置                                                          | 见 values.yaml                     |
| `bodyFactory.enabled`   | 启用自定义错误页面                                                                     | `false`                            |
| `bodyFactory.templates` | 错误页面模板                                                                           | 见 values.yaml                     |

### 使用现有 ConfigMap 参数

| 名称                            | 描述                                                                           | 值               |
| ------------------------------- | ------------------------------------------------------------------------------ | ---------------- |
| `existingRecordsConfigmap`      | 使用现有 ConfigMap 替代 records.yaml                                           | `""`             |
| `existingRemapConfigmap`        | 使用现有 ConfigMap 替代 remap.config                                           | `""`             |
| `existingPluginConfigmap`       | 使用现有 ConfigMap 替代 plugin.config                                          | `""`             |
| `existingStorageConfigmap`      | 使用现有 ConfigMap 替代 storage.config                                         | `""`             |
| `existingIpAllowConfigmap`      | 使用现有 ConfigMap 替代 ip_allow.yaml                                          | `""`             |
| `existingSniConfigmap`          | 使用现有 ConfigMap 替代 sni.yaml                                               | `""`             |
| `existingLoggingConfigmap`      | 使用现有 ConfigMap 替代 logging.yaml                                           | `""`             |
| `existingCacheConfigmap`        | 使用现有 ConfigMap 替代 cache.config                                           | `""`             |
| `existingParentConfigmap`       | 使用现有 ConfigMap 替代 parent.config                                          | `""`             |
| `existingStrategiesConfigmap`   | 使用现有 ConfigMap 替代 strategies.yaml                                        | `""`             |
| `existingSslMulticertConfigmap` | 使用现有 ConfigMap 替代 ssl_multicert.config                                   | `""`             |
| `existingHostingConfigmap`      | 使用现有 ConfigMap 替代 hosting.config                                         | `""`             |
| `existingVolumeConfigmap`       | 使用现有 ConfigMap 替代 volume.config                                          | `""`             |
| `existingSplitdnsConfigmap`     | 使用现有 ConfigMap 替代 splitdns.config                                        | `""`             |
| `existingSocksConfigmap`        | 使用现有 ConfigMap 替代 socks.config                                           | `""`             |
| `existingJsonrpcConfigmap`      | 使用现有 ConfigMap 替代 jsonrpc.yaml                                           | `""`             |

### 部署参数

| 名称                              | 描述                                                                                   | 值               |
| --------------------------------- | -------------------------------------------------------------------------------------- | ---------------- |
| `replicaCount`                    | Apache Traffic Server 副本数量                                                         | `1`              |
| `revisionHistoryLimit`            | 保留的旧历史记录数量以允许回滚                                                         | `10`             |
| `updateStrategy.type`             | Apache Traffic Server 部署策略类型                                                     | `RollingUpdate`  |
| `updateStrategy.rollingUpdate`    | Apache Traffic Server 滚动更新配置                                                     | `{}`             |
| `hostAliases`                     | 添加到 pod 主机文件的主机别名                                                          | `[]`             |
| `command`                         | 覆盖默认容器命令                                                                       | `[]`             |
| `args`                            | 覆盖默认容器参数                                                                       | `[]`             |
| `extraEnvVars`                    | 添加到容器的额外环境变量                                                               | `[]`             |
| `extraEnvVarsCM`                  | 包含额外环境变量的 ConfigMap 名称                                                      | `""`             |
| `extraEnvVarsSecret`              | 包含额外环境变量的 Secret 名称                                                         | `""`             |
| `podLabels`                       | Apache Traffic Server pods 的附加标签                                                  | `{}`             |
| `podAnnotations`                  | Apache Traffic Server pods 的注释                                                      | `{}`             |
| `podAffinityPreset`               | Pod 亲和性预设 (soft, hard)                                                            | `""`             |
| `podAntiAffinityPreset`           | Pod 反亲和性预设 (soft, hard)                                                          | `soft`           |
| `nodeAffinityPreset.type`         | 节点亲和性预设类型 (soft, hard)                                                        | `""`             |
| `nodeAffinityPreset.key`          | 要匹配的节点标签键                                                                     | `""`             |
| `nodeAffinityPreset.values`       | 要匹配的节点标签值                                                                     | `[]`             |
| `affinity`                        | Pod 分配的亲和性规则                                                                   | `{}`             |
| `nodeSelector`                    | Pod 分配的节点选择器                                                                   | `{}`             |
| `tolerations`                     | Pod 分配的容忍度                                                                       | `[]`             |
| `topologySpreadConstraints`       | Pod 的拓扑分布约束                                                                     | `[]`             |
| `priorityClassName`               | Pod 优先级类名称                                                                       | `""`             |
| `schedulerName`                   | 使用的调度器名称                                                                       | `""`             |
| `terminationGracePeriodSeconds`   | Pod 终止宽限期秒数                                                                     | `""`             |
| `hostNetwork`                     | 是否使用主机网络                                                                       | `false`          |
| `hostIPC`                         | 是否使用主机 IPC                                                                       | `false`          |
| `dnsPolicy`                       | Pod DNS 策略                                                                           | `""`             |
| `dnsConfig`                       | Pod DNS 配置                                                                           | `{}`             |
| `lifecycleHooks`                  | 容器生命周期钩子                                                                       | `{}`             |
| `sidecars`                        | 添加到 pod 的 sidecar 容器                                                             | `[]`             |
| `sidecarSingleProcessNamespace`   | 启用与 sidecars 共享进程命名空间                                                       | `false`          |
| `initContainers`                  | 添加到 pod 的初始化容器                                                                | `[]`             |
| `extraVolumes`                    | 添加到 pod 的额外卷                                                                    | `[]`             |
| `extraVolumeMounts`               | 添加到容器的额外卷挂载                                                                 | `[]`             |

### 容器资源参数

| 名称                                      | 描述                                                                                   | 值               |
| ----------------------------------------- | -------------------------------------------------------------------------------------- | ---------------- |
| `resourcesPreset`                         | 资源预设 (none, nano, micro, small, medium, large, xlarge, 2xlarge)                    | `small`          |
| `resources`                               | 容器资源请求和限制                                                                     | `{}`             |
| `containerPorts.http`                     | HTTP 容器端口                                                                          | `8080`           |
| `containerPorts.https`                    | HTTPS 容器端口                                                                         | `8443`           |
| `extraContainerPorts`                     | 额外的容器端口                                                                         | `[]`             |

### 安全上下文参数

| 名称                                              | 描述                                                                           | 值                |
| ------------------------------------------------- | ------------------------------------------------------------------------------ | ----------------- |
| `podSecurityContext.enabled`                      | 启用 Pod 安全上下文                                                            | `true`            |
| `podSecurityContext.fsGroup`                      | Pod 的 fsGroup                                                                 | `1001`            |
| `podSecurityContext.fsGroupChangePolicy`          | fsGroup 变更策略                                                               | `Always`          |
| `podSecurityContext.supplementalGroups`           | 补充组                                                                         | `[]`              |
| `podSecurityContext.sysctls`                      | sysctl 设置                                                                    | `[]`              |
| `containerSecurityContext.enabled`                | 启用容器安全上下文                                                             | `true`            |
| `containerSecurityContext.runAsUser`              | 容器运行用户 ID                                                                | `1001`            |
| `containerSecurityContext.runAsGroup`             | 容器运行组 ID                                                                  | `1001`            |
| `containerSecurityContext.runAsNonRoot`           | 以非 root 用户运行                                                             | `true`            |
| `containerSecurityContext.privileged`             | 特权模式                                                                       | `false`           |
| `containerSecurityContext.allowPrivilegeEscalation` | 允许提权                                                                     | `false`           |
| `containerSecurityContext.readOnlyRootFilesystem` | 只读根文件系统                                                                 | `false`           |
| `containerSecurityContext.capabilities.drop`      | 删除的 Linux 能力                                                              | `["ALL"]`         |
| `containerSecurityContext.seccompProfile.type`    | Seccomp profile 类型                                                           | `RuntimeDefault`  |

### 健康检查参数

| 名称                                  | 描述                                                                                   | 值               |
| ------------------------------------- | -------------------------------------------------------------------------------------- | ---------------- |
| `startupProbe.enabled`                | 启用启动探针                                                                           | `false`          |
| `startupProbe.initialDelaySeconds`    | 启动探针初始延迟秒数                                                                   | `30`             |
| `startupProbe.periodSeconds`          | 启动探针周期秒数                                                                       | `10`             |
| `startupProbe.timeoutSeconds`         | 启动探针超时秒数                                                                       | `5`              |
| `startupProbe.failureThreshold`       | 启动探针失败阈值                                                                       | `6`              |
| `startupProbe.successThreshold`       | 启动探针成功阈值                                                                       | `1`              |
| `livenessProbe.enabled`               | 启用存活探针                                                                           | `true`           |
| `livenessProbe.initialDelaySeconds`   | 存活探针初始延迟秒数                                                                   | `30`             |
| `livenessProbe.periodSeconds`         | 存活探针周期秒数                                                                       | `10`             |
| `livenessProbe.timeoutSeconds`        | 存活探针超时秒数                                                                       | `5`              |
| `livenessProbe.failureThreshold`      | 存活探针失败阈值                                                                       | `6`              |
| `livenessProbe.successThreshold`      | 存活探针成功阈值                                                                       | `1`              |
| `readinessProbe.enabled`              | 启用就绪探针                                                                           | `true`           |
| `readinessProbe.initialDelaySeconds`  | 就绪探针初始延迟秒数                                                                   | `5`              |
| `readinessProbe.periodSeconds`        | 就绪探针周期秒数                                                                       | `5`              |
| `readinessProbe.timeoutSeconds`       | 就绪探针超时秒数                                                                       | `3`              |
| `readinessProbe.failureThreshold`     | 就绪探针失败阈值                                                                       | `3`              |
| `readinessProbe.successThreshold`     | 就绪探针成功阈值                                                                       | `1`              |
| `customStartupProbe`                  | 自定义启动探针                                                                         | `{}`             |
| `customLivenessProbe`                 | 自定义存活探针                                                                         | `{}`             |
| `customReadinessProbe`                | 自定义就绪探针                                                                         | `{}`             |

### 自动伸缩参数

| 名称                                      | 描述                                                                                   | 值               |
| ----------------------------------------- | -------------------------------------------------------------------------------------- | ---------------- |
| `autoscaling.hpa.enabled`                 | 启用 HPA 水平自动伸缩                                                                  | `false`          |
| `autoscaling.hpa.minReplicas`             | HPA 最小副本数                                                                         | `3`              |
| `autoscaling.hpa.maxReplicas`             | HPA 最大副本数                                                                         | `10`             |
| `autoscaling.hpa.targetCPU`               | HPA 目标 CPU 使用率百分比                                                              | `70`             |
| `autoscaling.hpa.targetMemory`            | HPA 目标内存使用率百分比                                                               | `80`             |
| `autoscaling.vpa.enabled`                 | 启用 VPA 垂直自动伸缩                                                                  | `false`          |
| `autoscaling.vpa.annotations`             | VPA 资源注解                                                                           | `{}`             |
| `autoscaling.vpa.controlledResources`     | VPA 控制的资源类型 (cpu, memory)                                                       | `["cpu", "memory"]` |
| `autoscaling.vpa.maxAllowed`              | VPA 最大资源限制                                                                       | `{}`             |
| `autoscaling.vpa.minAllowed`              | VPA 最小资源限制                                                                       | `{}`             |
| `autoscaling.vpa.controlledValues`        | VPA 控制值类型 (RequestsAndLimits, RequestsOnly)                                       | `""`             |
| `autoscaling.vpa.updatePolicy.updateMode` | VPA 更新策略 (Off, Initial, Recreate, Auto)                                            | `Auto`           |

### 服务参数

| 名称                                  | 描述                                                                                   | 值               |
| ------------------------------------- | -------------------------------------------------------------------------------------- | ---------------- |
| `service.type`                        | 服务类型                                                                               | `LoadBalancer`   |
| `service.ports.http`                  | 服务 HTTP 端口                                                                         | `80`             |
| `service.ports.https`                 | 服务 HTTPS 端口                                                                        | `443`            |
| `service.clusterIP`                   | Apache Traffic Server 服务 Cluster IP                                                  | `""`             |
| `service.loadBalancerIP`              | LoadBalancer 服务 IP 地址                                                              | `""`             |
| `service.loadBalancerSourceRanges`    | Apache Traffic Server 服务 Load Balancer 源                                            | `[]`             |
| `service.externalTrafficPolicy`       | Apache Traffic Server 服务外部流量策略                                                 | `Cluster`        |
| `service.annotations`                 | Apache Traffic Server 服务的附加自定义注释                                             | `{}`             |
| `service.extraPorts`                  | 要在 Apache Traffic Server 服务上暴露的额外端口                                        | `[]`             |
| `service.sessionAffinity`             | 服务的会话亲和性                                                                       | `None`           |

### Ingress 参数

| 名称                                  | 描述                                                                                   | 值               |
| ------------------------------------- | -------------------------------------------------------------------------------------- | ---------------- |
| `ingress.enabled`                     | 启用 ingress 记录生成                                                                  | `false`          |
| `ingress.pathType`                    | Ingress 路径类型                                                                       | `ImplementationSpecific` |
| `ingress.apiVersion`                  | 强制 Ingress API 版本                                                                  | `""`             |
| `ingress.hostname`                    | Ingress 资源的默认主机                                                                 | `trafficserver.local` |
| `ingress.path`                        | 默认主机的路径                                                                         | `/`              |
| `ingress.annotations`                 | Ingress 资源的附加注释                                                                 | `{}`             |
| `ingress.ingressClassName`            | 在 k8s 1.18+ 的 ingress 记录上设置 ingressClassName                                    | `""`             |
| `ingress.tls`                         | 创建 TLS Secret                                                                        | `false`          |
| `ingress.extraHosts`                  | 要覆盖的附加主机名列表                                                                 | `[]`             |
| `ingress.extraPaths`                  | 可能需要添加到主主机下 ingress 的任何附加任意路径                                      | `[]`             |
| `ingress.extraTls`                    | 附加主机名的 tls 配置                                                                  | `[]`             |
| `ingress.secrets`                     | 如果您提供自己的证书，请使用此添加证书作为 secrets                                     | `[]`             |
| `ingress.extraRules`                  | 要添加到此 ingress 记录的附加规则列表                                                  | `[]`             |

### 持久化参数

| 名称                         | 描述                                                                                   | 值               |
| ---------------------------- | -------------------------------------------------------------------------------------- | ---------------- |
| `persistence.enabled`        | 使用 PVC 启用 Apache Traffic Server 数据持久化                                         | `true`           |
| `persistence.storageClass`   | Apache Traffic Server 数据卷的 PVC 存储类                                              | `""`             |
| `persistence.accessModes`    | Apache Traffic Server 数据卷的 PVC 访问模式                                            | `["ReadWriteMany"]` |
| `persistence.size`           | Apache Traffic Server 数据卷的 PVC 存储请求                                            | `100Gi`          |
| `persistence.annotations`    | PVC 的注释                                                                             | `{}`             |
| `persistence.selector`       | 匹配现有持久卷的选择器                                                                 | `{}`             |
| `persistence.existingClaim`  | 要使用的现有 PVC 的名称                                                                | `""`             |

### 日志持久化参数

| 名称                              | 描述                                                                           | 值               |
| --------------------------------- | ------------------------------------------------------------------------------ | ---------------- |
| `logsPersistence.enabled`         | 使用 PVC 启用日志持久化                                                        | `false`          |
| `logsPersistence.toStdout`        | 将日志转发到 stdout，便于 K8s 日志采集（Fluentd、Loki 等）                     | `true`           |
| `logsPersistence.storageClass`    | 日志卷的 PVC 存储类                                                            | `""`             |
| `logsPersistence.accessModes`     | 日志卷的 PVC 访问模式                                                          | `["ReadWriteOnce"]` |
| `logsPersistence.size`            | 日志卷的 PVC 存储请求                                                          | `10Gi`           |
| `logsPersistence.annotations`     | 日志 PVC 的注释                                                                | `{}`             |
| `logsPersistence.existingClaim`   | 要使用的现有日志 PVC 的名称                                                    | `""`             |

### RBAC 参数

| 名称          | 描述                              | 值      |
| ------------- | --------------------------------- | ------- |
| `rbac.create` | 是否创建和使用 RBAC 资源          | `false` |
| `rbac.rules`  | 自定义 RBAC 规则                  | `[]`    |

> **注意**: 启用 RBAC 后，默认会创建 Role 和 RoleBinding，授予对 ConfigMap 和 Secret 的读取权限。可通过 `rbac.rules` 自定义规则。

### ServiceAccount 参数

| 名称                                      | 描述                                                                           | 值               |
| ----------------------------------------- | ------------------------------------------------------------------------------ | ---------------- |
| `serviceAccount.create`                   | 是否创建 ServiceAccount                                                        | `true`           |
| `serviceAccount.name`                     | ServiceAccount 名称（不设置则自动生成）                                        | `""`             |
| `serviceAccount.annotations`              | ServiceAccount 注解                                                            | `{}`             |
| `serviceAccount.automountServiceAccountToken` | 是否自动挂载 ServiceAccount token                                          | `false`          |

### PodDisruptionBudget 参数

| 名称                  | 描述                                                                           | 值               |
| --------------------- | ------------------------------------------------------------------------------ | ---------------- |
| `pdb.create`          | 是否创建 PodDisruptionBudget                                                   | `true`           |
| `pdb.minAvailable`    | 最小可用 Pod 数量（数字或百分比）                                              | `""`             |
| `pdb.maxUnavailable`  | 最大不可用 Pod 数量（数字或百分比）                                            | `1`              |

### NetworkPolicy 参数

| 名称                                      | 描述                                                                           | 值               |
| ----------------------------------------- | ------------------------------------------------------------------------------ | ---------------- |
| `networkPolicy.enabled`                   | 是否启用 NetworkPolicy                                                         | `true`           |
| `networkPolicy.allowExternal`             | 允许外部连接                                                                   | `true`           |
| `networkPolicy.allowExternalEgress`       | 允许外部出口流量                                                               | `true`           |
| `networkPolicy.extraIngress`              | 额外的入口规则                                                                 | `[]`             |
| `networkPolicy.extraEgress`               | 额外的出口规则                                                                 | `[]`             |
| `networkPolicy.ingressNSMatchLabels`      | 允许入口的命名空间标签                                                         | `{}`             |
| `networkPolicy.ingressNSPodMatchLabels`   | 允许入口的 Pod 标签                                                            | `{}`             |

### 指标参数

| 名称                                          | 描述                                                                                   | 值        |
| --------------------------------------------- | -------------------------------------------------------------------------------------- | --------- |
| `metrics.enabled`                             | 启动 Prometheus exporter sidecar 容器                                                  | `false`   |
| `metrics.port`                                | Prometheus 指标端口                                                                    | `8083`    |
| `metrics.path`                                | Prometheus 指标路径                                                                    | `/_stats` |
| `metrics.podAnnotations`                      | 指标 exporter pod 的附加注释                                                           | `{}`      |
| `metrics.serviceMonitor.enabled`              | 创建 Prometheus Operator ServiceMonitor（也需要 `metrics.enabled` 为 `true`）          | `false`   |
| `metrics.serviceMonitor.namespace`            | Prometheus 运行的命名空间                                                              | `""`      |
| `metrics.serviceMonitor.jobLabel`             | 目标服务上用作 prometheus 中 job 名称的标签名称                                        | `""`      |
| `metrics.serviceMonitor.interval`             | 抓取指标的间隔                                                                         | `""`      |
| `metrics.serviceMonitor.scrapeTimeout`        | 抓取结束后的超时时间                                                                   | `""`      |
| `metrics.serviceMonitor.selector`             | Prometheus 实例选择器标签                                                              | `{}`      |
| `metrics.serviceMonitor.labels`               | 可用于 PodMonitor 被 Prometheus 发现的附加标签                                         | `{}`      |
| `metrics.serviceMonitor.relabelings`          | 抓取前应用于样本的 RelabelConfigs                                                      | `[]`      |
| `metrics.serviceMonitor.metricRelabelings`    | 摄取前应用于样本的 MetricRelabelConfigs                                                | `[]`      |
| `metrics.serviceMonitor.honorLabels`          | honorLabels 在与目标标签冲突时选择指标的标签                                           | `false`   |
| `metrics.prometheusRule.enabled`              | 如果为 `true`，创建 Prometheus Operator PrometheusRule                                 | `false`   |
| `metrics.prometheusRule.namespace`            | PrometheusRule 资源的命名空间                                                          | `""`      |
| `metrics.prometheusRule.additionalLabels`     | 可用于 PrometheusRule 被 Prometheus 发现的附加标签                                     | `{}`      |
| `metrics.prometheusRule.rules`                | Prometheus Rule 定义                                                                   | `[]`      |

## 配置示例

### 镜像服务配置

```yaml
remapConfig: |
  # Ubuntu 镜像
  map http://ubuntu.mirrors.example.local/ http://jp.archive.ubuntu.com/ubuntu/
  map https://ubuntu.mirrors.example.local/ http://jp.archive.ubuntu.com/ubuntu/
  
  # Ubuntu 安全更新镜像
  map http://security.ubuntu.mirrors.example.local/ http://security.ubuntu.com/ubuntu/
  map https://security.ubuntu.mirrors.example.local/ http://security.ubuntu.com/ubuntu/
  
  # Debian 镜像
  map http://debian.mirrors.example.local/ http://deb.debian.org/debian/
  map https://debian.mirrors.example.local/ http://deb.debian.org/debian/
  
  # CentOS 镜像
  map http://centos.mirrors.example.local/ http://mirror.centos.org/centos/
  map https://centos.mirrors.example.local/ http://mirror.centos.org/centos/
  
  # OpenDev Tarballs 镜像
  map http://tarballs.mirrors.example.local/ https://tarballs.opendev.org/
  map https://tarballs.mirrors.example.local/ https://tarballs.opendev.org/
```

### 高可用生产配置

```yaml
replicaCount: 3

autoscaling:
  hpa:
    enabled: true
    minReplicas: 3
    maxReplicas: 10
    targetCPU: 70
    targetMemory: 80

podAntiAffinityPreset: hard

persistence:
  enabled: true
  storageClass: "general-fs"
  accessModes:
    - ReadWriteMany
  size: 2Ti

resources:
  requests:
    cpu: 2
    memory: 4Gi
  limits:
    cpu: 4
    memory: 8Gi

recordsConfig:
  records:
    accept_threads: 2
    exec_thread:
      autoconfig:
        enabled: 1
      limit: 8
    cache:
      ram_cache:
        size: 4294967296
    net:
      connections_throttle: 100000
```

### 企业级完整配置

```yaml
# 核心配置
recordsConfig:
  records:
    accept_threads: 4
    exec_thread:
      limit: 16
    cache:
      ram_cache:
        size: 8589934592
    http:
      server_ports: "8080 8080:ipv6 8443:ssl 8443:ssl:ipv6"
    net:
      connections_throttle: 200000

# IP 访问控制
ipAllowConfig: |
  ip_allow:
    - apply: in
      ip_addrs: 10.0.0.0/8
      action: allow
      methods: ALL
    - apply: in
      ip_addrs: 0/0
      action: deny
      methods:
        - PURGE
        - PUSH

# 缓存策略
cacheConfig: |
  dest_domain=static.example.com ttl-in-cache=30d
  url_regex=\.(css|js)$ ttl-in-cache=7d

# 父代理配置
parentConfig: |
  dest_domain=. parent="proxy1:8080; proxy2:8080" round_robin=strict

# 日志配置
loggingConfig: |
  logging:
    formats:
      - name: combined
        format: '%<chi> - %<caun> [%<cqtn>] "%<cqhm> %<pqu> %<cqpv>" %<pssc> %<pscl> "%<{Referer}cqh>" "%<{User-Agent}cqh>"'
    logs:
      - filename: access
        format: combined
        mode: ascii
```

## 故障排除

### Pod 无法启动

```bash
kubectl describe pod <pod-name> -n <namespace>
```

检查事件信息，常见问题包括：持久卷挂载失败、资源不足、配置错误。

### 检查日志

```bash
kubectl logs <pod-name> -n <namespace>
```

### 进入容器调试

```bash
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash

# 检查 ATS 状态
/opt/bin/traffic_ctl status

# 检查配置
cat /opt/etc/trafficserver/records.yaml
cat /opt/etc/trafficserver/remap.config

# 重载配置
/opt/bin/traffic_ctl config reload

# 清除缓存
/opt/bin/traffic_ctl cache clear
```

## 升级

### 升级到新版本

```bash
helm upgrade my-release oci://REGISTRY_NAME/REPOSITORY_NAME/trafficserver
```

## 许可证

版权所有 &copy; 2025 Broadcom。术语 "Broadcom" 指 Broadcom Inc. 及/或其子公司。

根据 Apache 许可证 2.0 版（"许可证"）授权；除非符合许可证，否则您不得使用此文件。您可以在以下位置获取许可证副本：

<http://www.apache.org/licenses/LICENSE-2.0>

除非适用法律要求或书面同意，根据许可证分发的软件是按"原样"分发的，不附带任何明示或暗示的担保或条件。请参阅许可证以了解许可证下特定语言的权限和限制。
