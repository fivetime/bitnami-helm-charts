# Multus CNI Helm Chart

Multus CNI 是一个 Kubernetes CNI 插件，允许 Pod 附加多个网络接口。

本 Helm Chart 使用 [官方 Multus CNI 镜像](https://github.com/k8snetworkplumbingwg/multus-cni)，**同时支持 thin 和 thick 两种部署模式**。

## 快速开始

```bash
# 默认（thin 模式）
helm install multus ./multus-cni -n kube-system

# thick 模式（推荐生产环境，有 Prometheus 指标）
helm install multus ./multus-cni -n kube-system \
  --set mode=thick \
  --set image.tag=v4.2.4   # chart 会自动追加 -thick 后缀
```

## 特性

- 使用官方 `ghcr.io/k8snetworkplumbingwg/multus-cni` 镜像
- **支持 thin 和 thick 两种插件模式**（通过 `mode` 切换）
  - **thin**：每次 CNI 调用 fork 一个 multus 进程，简单可靠，无常驻 daemon
  - **thick**：节点常驻 `multus-daemon` + 小客户端 `multus-shim`，支持 Prometheus 指标、daemon 模式 hot-reload
- `mode=thick` 时自动给 `image.tag` 追加 `-thick` 后缀（除非已含 "thick" 或设置了 `image.digest`）
- 默认容忍所有节点 taint（NoSchedule + NoExecute），CNI daemon 跑遍全集群
- 可选 Prometheus 指标端口 + Service + ServiceMonitor

## CNI 目录

containerd 和 CRI-O 现在都统一使用 `/opt/cni/bin` 作为默认的 CNI 插件目录。

## 模式对比

| 维度 | thin (默认) | thick |
|---|---|---|
| 形态 | 每次 CNI 调用 fork 一个 `multus` | 节点常驻 `multus-daemon` + `multus-shim` 走 Unix socket |
| apiserver 压力 | 每次 ADD/DEL 查询 NAD | informer 长连接，watch 一次共享 |
| 常驻内存 | 0 | ~50 MiB / 节点 |
| Prometheus metrics | ✗ | ✓ |
| 故障域 | 单 pod 影响 | daemon 死则整节点新 pod 卡住 |
| 启动延迟 / pod | ~50-100 ms | μs 级（socket + 缓存） |
| 推荐场景 | 中小集群、简单部署 | 大集群、需要观测、frequent NAD CRUD |

## 参数配置

### 镜像配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `image.registry` | 镜像仓库 | `ghcr.io` |
| `image.repository` | 镜像名称 | `k8snetworkplumbingwg/multus-cni` |
| `image.tag` | 镜像标签（`mode=thick` 时自动加 `-thick` 后缀） | `stable` |
| `image.digest` | 镜像 digest（覆盖 tag，关闭自动后缀逻辑） | `""` |
| `image.pullPolicy` | 镜像拉取策略 | `IfNotPresent` |
| `image.debug` | 开启调试日志 | `false` |

### 模式配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `mode` | 部署模式：`thin` 或 `thick` | `thin` |
| `thick.daemonConfig.chrootDir` | 容器内挂载宿主机 root 的路径（执行 delegate CNI 时 chroot 到这里） | `/hostroot` |
| `thick.daemonConfig.cniVersion` | 生成 conflist 的 CNI 版本 | `0.3.1` |
| `thick.daemonConfig.logLevel` | `multus-daemon` 日志级别 | `verbose` |
| `thick.daemonConfig.logToStderr` | 日志同时输出到 stderr | `true` |
| `thick.daemonConfig.cniConfigDir` | daemon 容器内的 CNI 配置目录 | `/host/etc/cni/net.d` |
| `thick.daemonConfig.multusAutoconfigDir` | daemon 监听的自动配置目录 | `/host/etc/cni/net.d` |
| `thick.daemonConfig.multusConfigFile` | `auto` 自动生成 conflist，或指定路径 | `auto` |
| `thick.daemonConfig.socketDir` | `multus-daemon` 监听 Unix socket 的目录 | `/host/run/multus/` |

### Metrics 配置（`mode=thick` 专属）

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `metrics.enabled` | 启用 Prometheus 指标端口 | `false` |
| `metrics.port` | 指标端口 | `9091` |
| `metrics.service.enabled` | 创建 metrics Service（headless ClusterIP） | `true` |
| `metrics.service.type` | Service 类型 | `ClusterIP` |
| `metrics.service.annotations` | Service annotations | `{}` |
| `metrics.serviceMonitor.enabled` | 创建 prometheus-operator ServiceMonitor | `false` |
| `metrics.serviceMonitor.namespace` | ServiceMonitor 所在命名空间（空 = release ns） | `""` |
| `metrics.serviceMonitor.labels` | 给 ServiceMonitor 加额外标签（Prometheus 选择器用） | `{}` |
| `metrics.serviceMonitor.interval` | 抓取间隔 | `""` |
| `metrics.serviceMonitor.scrapeTimeout` | 抓取超时 | `""` |

### 路径配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `hostCNIBinDir` | 宿主机 CNI 插件目录 | `/opt/cni/bin` |
| `hostCNINetDir` | 宿主机 CNI 配置目录 | `/etc/cni/net.d` |
| `CNIMountPath` | 容器内挂载路径前缀 | `/host` |

### 资源配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `resourcesPreset` | bitnami 预设资源档位（none/nano/micro/small/...） | `nano` |
| `resources` | 直接指定 requests/limits（覆盖 preset，**生产推荐**） | `{}` |

### 调度配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `tolerations` | Pod 容忍度 | 全容忍 `NoSchedule` 和 `NoExecute`（CNI daemon 应跑所有节点） |
| `nodeSelector` | 节点选择器 | `{}` |
| `affinity` | 亲和性配置 | `{}` |
| `topologySpreadConstraints` | 拓扑分布约束 | `[]` |
| `priorityClassName` | 优先级类 | `""` |

### 安全配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `containerSecurityContext.privileged` | 特权模式（CNI daemon 必需） | `true` |
| `containerSecurityContext.runAsUser` | 运行用户 | `0` |
| `containerSecurityContext.readOnlyRootFilesystem` | rootfs 只读 | `true` |
| `containerSecurityContext.seccompProfile.type` | seccomp profile | `RuntimeDefault` |

### Probes 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `livenessProbe.enabled` | 启用 liveness probe（`pgrep` 检测主进程） | `false` |
| `readinessProbe.enabled` | 启用 readiness probe | `false` |
| `startupProbe.enabled` | 启用 startup probe | `false` |

> probe 内部用 `pgrep thin_entrypoint`（thin 模式）或 `pgrep multus-daemon`（thick 模式）—— 自动按 mode 切换。

### RBAC 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `rbac.create` | 创建 ClusterRole / ClusterRoleBinding | `true` |
| `serviceAccount.create` | 创建 ServiceAccount | `true` |
| `serviceAccount.name` | ServiceAccount 名称 | `""` |

> ClusterRole 权限按 mode 自动调整：thin 只需 `pods.get/update`，thick 额外加 `pods.list/watch`（informer 需要）。

## 使用示例

### thin 模式（默认）

```bash
helm install multus ./multus-cni -n kube-system
```

### thick 模式 + Prometheus 指标

```bash
helm install multus ./multus-cni -n kube-system \
  --set mode=thick \
  --set image.tag=v4.2.4 \
  --set metrics.enabled=true \
  --set metrics.serviceMonitor.enabled=true   # 如果跑 Prometheus Operator
```

### 自定义 CNI 目录

```bash
helm install multus ./multus-cni -n kube-system \
  --set hostCNIBinDir=/custom/cni/bin \
  --set hostCNINetDir=/custom/cni/net.d
```

### 开启调试日志

```bash
helm install multus ./multus-cni -n kube-system --set image.debug=true
```

## 创建 NetworkAttachmentDefinition

安装 Multus 后，可以创建 NetworkAttachmentDefinition 来定义额外的网络接口：

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: macvlan-conf
spec:
  config: '{
    "cniVersion": "0.3.1",
    "type": "macvlan",
    "master": "eth0",
    "mode": "bridge",
    "ipam": {
      "type": "host-local",
      "subnet": "192.168.1.0/24",
      "rangeStart": "192.168.1.200",
      "rangeEnd": "192.168.1.250",
      "gateway": "192.168.1.1"
    }
  }'
```

然后在 Pod 中使用：

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sample-pod
  annotations:
    k8s.v1.cni.cncf.io/networks: macvlan-conf
spec:
  containers:
  - name: sample
    image: nginx
```

## 卸载

```bash
helm uninstall multus -n kube-system
```

> Multus CRD（`network-attachment-definitions.k8s.cni.cncf.io`）是 chart 的 `crds/` 目录管理，helm 默认不会自动删除。如要彻底清理：
> ```bash
> kubectl delete crd network-attachment-definitions.k8s.cni.cncf.io
> ```

## 故障排查

### 检查 Multus Pod 状态

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=multus-cni
```

### 查看日志

```bash
# thin 模式：thin_entrypoint 的 stdout
kubectl logs -n kube-system -l app.kubernetes.io/name=multus-cni

# thick 模式：multus-daemon 的 stdout（含 metrics endpoint 启动日志、informer cache sync）
kubectl logs -n kube-system -l app.kubernetes.io/name=multus-cni --tail=50
```

### 验证 CNI 配置

```bash
# 在节点上检查
ls -la /etc/cni/net.d/
cat /etc/cni/net.d/00-multus.conflist          # 列表中第一个 = kubelet 调用入口
```

### 验证 Multus 二进制（按 mode 区分）

```bash
# thin 模式：完整 ~66 MiB 二进制
ls -la /opt/cni/bin/multus

# thick 模式：小客户端 multus-shim，通过 socket 调 daemon
ls -la /opt/cni/bin/multus-shim
ls -la /run/multus/multus.sock                  # daemon socket
```

### 验证 metrics（thick + metrics.enabled）

```bash
POD_IP=$(kubectl -n kube-system get pod -l app.kubernetes.io/name=multus-cni -o jsonpath='{.items[0].status.podIP}')
kubectl -n kube-system run -i --rm curl-test --image=curlimages/curl --restart=Never -- \
  curl -s http://$POD_IP:9091/metrics | head -20
```

## 参考链接

- [Multus CNI 官方文档](https://github.com/k8snetworkplumbingwg/multus-cni)
- [Multus Thick Plugin 文档](https://github.com/k8snetworkplumbingwg/multus-cni/blob/master/docs/thick-plugin.md)
- [NetworkAttachmentDefinition 规范](https://github.com/k8snetworkplumbingwg/multi-net-spec)

## 升级历史（fork 改动）

- **2.3.2**：metrics endpoint + Service + ServiceMonitor；默认 tolerations 改为全容忍；`mode=thick` 自动 `-thick` tag 后缀。
- **2.3.1**：`mode=thick` 时 ClusterRole 补 `pods.list/watch`（informer 需要），消除 `pods is forbidden` 错误。
- **2.3.0**：新增 `mode` 开关，支持 thick 部署模式（ConfigMap、hostPID、所有上游 thick 卷挂载）。

## License

Apache License 2.0
