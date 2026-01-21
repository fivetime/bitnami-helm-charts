# Multus CNI Helm Chart

Multus CNI 是一个 Kubernetes CNI 插件，允许 Pod 附加多个网络接口。

本 Helm Chart 使用 [官方 Multus CNI 镜像](https://github.com/k8snetworkplumbingwg/multus-cni)，支持 containerd 和 CRI-O 容器运行时的自动检测。

## 快速开始

```bash
# 默认安装（自动检测容器运行时）
helm install multus ./multus-cni -n kube-system

# 或者显式指定容器运行时
helm install multus ./multus-cni -n kube-system --set containerRuntime=containerd
helm install multus ./multus-cni -n kube-system --set containerRuntime=crio
```

## 特性

- 使用官方 `ghcr.io/k8snetworkplumbingwg/multus-cni:stable` 镜像
- 支持 thin plugin 模式（轻量级）
- 自动检测容器运行时（containerd / CRI-O）
- 支持所有节点调度（包括 master 节点）

## 容器运行时支持

| 运行时 | CNI Bin 目录 | 配置方式 |
|--------|--------------|----------|
| containerd | `/opt/cni/bin` | `containerRuntime=containerd` |
| CRI-O | `/usr/libexec/cni` | `containerRuntime=crio` |
| 自动检测 | 两者都挂载 | `containerRuntime=auto` (默认) |

### 自动检测模式

默认的 `containerRuntime=auto` 模式会同时挂载两个 CNI bin 目录：
- `/opt/cni/bin` (containerd)
- `/usr/libexec/cni` (CRI-O)

Multus 的 `/thin_entrypoint` 会自动检测哪个目录有实际的 CNI 插件并使用它。

## 参数配置

### 镜像配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `image.registry` | 镜像仓库 | `ghcr.io` |
| `image.repository` | 镜像名称 | `k8snetworkplumbingwg/multus-cni` |
| `image.tag` | 镜像标签 | `stable` |
| `image.pullPolicy` | 镜像拉取策略 | `IfNotPresent` |
| `image.debug` | 开启调试日志 | `false` |

### 运行时配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `containerRuntime` | 容器运行时类型：`auto`, `containerd`, `crio` | `auto` |
| `hostCNIBinDir` | 自定义 CNI bin 目录（覆盖 containerRuntime） | `""` |
| `hostCNINetDir` | CNI 配置目录 | `/etc/cni/net.d` |
| `CNIMountPath` | 容器内挂载路径前缀 | `/host` |

### 资源配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `resources.requests.cpu` | CPU 请求 | `100m` |
| `resources.requests.memory` | 内存请求 | `50Mi` |
| `resources.limits.cpu` | CPU 限制 | `100m` |
| `resources.limits.memory` | 内存限制 | `50Mi` |

### 调度配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `tolerations` | Pod 容忍度 | 允许 NoSchedule 和 NoExecute |
| `nodeSelector` | 节点选择器 | `{}` |
| `affinity` | 亲和性配置 | `{}` |

### 安全配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `containerSecurityContext.privileged` | 特权模式 | `true` |
| `containerSecurityContext.runAsUser` | 运行用户 | `0` |

### Probes 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `livenessProbe.enabled` | 启用存活探针 | `false` |
| `readinessProbe.enabled` | 启用就绪探针 | `false` |

> **注意**: 官方镜像基于 distroless，没有 `pgrep` 命令，因此默认禁用 probes。

### RBAC 配置

| 参数 | 描述 | 默认值 |
|------|------|--------|
| `rbac.create` | 创建 RBAC 资源 | `true` |
| `serviceAccount.create` | 创建 ServiceAccount | `true` |
| `serviceAccount.name` | ServiceAccount 名称 | `""` |

## 使用示例

### 基本安装

```bash
helm install multus ./multus-cni -n kube-system
```

### CRI-O 运行时

```bash
helm install multus ./multus-cni -n kube-system --set containerRuntime=crio
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

## 故障排查

### 检查 Multus Pod 状态

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=multus-cni
```

### 查看日志

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=multus-cni
```

### 验证 CNI 配置

```bash
# 在节点上检查
ls -la /etc/cni/net.d/
cat /etc/cni/net.d/00-multus.conf
```

### 验证 Multus 二进制

```bash
# 在节点上检查
ls -la /opt/cni/bin/multus      # containerd
ls -la /usr/libexec/cni/multus  # CRI-O
```

## 参考链接

- [Multus CNI 官方文档](https://github.com/k8snetworkplumbingwg/multus-cni)
- [NetworkAttachmentDefinition 规范](https://github.com/k8snetworkplumbingwg/multi-net-spec)
- [Kubernetes CNI 文档](https://kubernetes.io/docs/concepts/cluster-administration/networking/)

## License

Apache License 2.0
