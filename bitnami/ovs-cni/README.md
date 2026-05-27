# ovs-cni Helm Chart

ovs-cni 是一个 Kubernetes CNI 插件，把 Pod / KubeVirt 虚机的网卡**挂到宿主机的 Open vSwitch 桥**上。常见用途：

- 多租户网络（与裸 OVN 配合，由外部控制面创建 logical switch / port）
- 物理 VLAN 接入（OVS bridge 直挂物理网卡或 bond，trunk/access port）
- KubeVirt 虚机的二级网卡（搭配 multus）

本 Helm Chart 使用[官方上游镜像](https://github.com/k8snetworkplumbingwg/ovs-cni)，一个镜像里同时打包了 4 个二进制（`ovs`、`ovs-mirror-producer`、`ovs-mirror-consumer`、`marker`），通过一个 DaemonSet 部署：**initContainer 拷贝 CNI 二进制到宿主机 `/opt/cni/bin/`，主容器跑 marker daemon**（把 OVS 桥暴露为 K8s Node 资源 `ovs-cni.network.kubevirt.io/<bridge>`，供调度器使用）。

## 快速开始

```bash
# 1. 宿主机先装好 Open vSwitch 并启动（举例 Ubuntu）
apt-get install -y openvswitch-switch
systemctl enable --now openvswitch-switch

# 2. 在每个 worker 上建好需要暴露给 K8s 的桥（举例）
ovs-vsctl add-br br-tenant
ovs-vsctl add-port br-tenant eth1   # 物理 trunk 网卡

# 3. 安装 chart
helm install ovs-cni ./ovs-cni -n kube-system

# 4. 看 marker 是否把桥注册成 K8s 资源
kubectl get node -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.capacity}{"\n"}{end}' | grep ovs-cni
```

> **前置条件**：
> 1. 集群必须已装 **multus-cni**（或其它 CNI meta-plugin），ovs-cni 不是主 CNI，只能作为 NetworkAttachmentDefinition 的下游驱动被调用。
> 2. 每个目标节点必须已经安装并运行 **Open vSwitch**（`/var/run/openvswitch/db.sock` 可用），并已建好待暴露的 bridge。

## 特性

- 使用官方 `ghcr.io/k8snetworkplumbingwg/ovs-cni-plugin` 镜像
- **3 个 CNI 二进制可单独开关**（`plugins.ovs` / `plugins.mirrorProducer` / `plugins.mirrorConsumer`），不需要的就不装
- **marker 可选**（`marker.enabled=false` 时只装 CNI 二进制，不暴露 bridge 资源 —— 罕见但保留）
- OVSDB socket 支持 unix（默认）和 tcp 两种模式
- 默认容忍所有节点 taint（NoSchedule + NoExecute），DaemonSet 跑遍全集群
- 默认 `nodeSelector.kubernetes.io/os=linux`（OVS 仅支持 Linux 内核模块）
- `priorityClassName=system-node-critical`，避免被驱逐

## CNI 二进制说明

| 二进制 | 作用 | 关闭方式 |
|---|---|---|
| `/opt/cni/bin/ovs` | 主 CNI 插件，把 pod veth 挂到 OVS bridge | `plugins.ovs=false` |
| `/opt/cni/bin/ovs-mirror-producer` | 把 pod 接口流量**镜像出去**（喂给 IDS / 抓包） | `plugins.mirrorProducer=false` |
| `/opt/cni/bin/ovs-mirror-consumer` | 把镜像流量**收进来**（流量分析器 pod 用） | `plugins.mirrorConsumer=false` |

## marker 工作原理

marker 守护进程在主容器里跑，定期：

1. 通过 OVSDB socket 读宿主机上的所有 OVS bridge
2. 与缓存对比，JSON-Patch `Node.status.capacity`：
   ```
   ovs-cni.network.kubevirt.io/br-tenant:  "1000"
   ovs-cni.network.kubevirt.io/br-int:     "1000"
   ```
3. Pod 通过 `resources.requests` 声明要哪个桥，调度器据此选节点：
   ```yaml
   resources:
     requests:
       ovs-cni.network.kubevirt.io/br-tenant: "1"
   ```

参数：

| 参数 | 描述 | 默认值 |
|---|---|---|
| `marker.enabled` | 是否运行 marker（关闭则只装 CNI 二进制） | `true` |
| `marker.updateInterval` | Node status 更新间隔（秒） | `60` |
| `marker.reconcileInterval` | 缓存 vs 实际全量 reconcile 间隔（分钟） | `10` |
| `marker.healthCheckInterval` | 健康检查文件触摸 + 探针间隔（秒） | `60` |
| `marker.verbosity` | glog `-v` 级别 | `3` |

## OVSDB Socket 配置

| 参数 | 描述 | 默认值 |
|---|---|---|
| `ovsSocket.type` | `unix` 或 `tcp` | `unix` |
| `ovsSocket.path` | unix socket 路径（宿主机） | `/var/run/openvswitch/db.sock` |
| `ovsSocket.host` | tcp 模式：OVSDB host | `""` |
| `ovsSocket.port` | tcp 模式：OVSDB port | `6640` |

## 镜像配置

| 参数 | 描述 | 默认值 |
|---|---|---|
| `image.registry` | 镜像仓库 | `ghcr.io` |
| `image.repository` | 镜像名 | `k8snetworkplumbingwg/ovs-cni-plugin` |
| `image.tag` | 镜像标签 | `latest` |
| `image.digest` | 镜像 digest（覆盖 tag） | `""` |
| `image.pullPolicy` | 拉取策略 | `IfNotPresent` |
| `image.debug` | 调试日志 | `false` |

## 路径配置

| 参数 | 描述 | 默认值 |
|---|---|---|
| `hostCNIBinDir` | 宿主机 CNI 插件目录 | `/opt/cni/bin` |
| `CNIMountPath` | 容器内挂载宿主机 CNI 目录的前缀 | `/host` |

## 资源 / 调度

| 参数 | 描述 | 默认值 |
|---|---|---|
| `resourcesPreset` | bitnami 预设档位（none/nano/micro/small/...） | `nano` |
| `resources` | 直接指定 requests/limits | `{}` |
| `nodeSelector` | 默认 `kubernetes.io/os: linux` | (Linux) |
| `tolerations` | 默认全部 Exists（覆盖所有 taint） | (所有) |
| `priorityClassName` | 优先级类 | `system-node-critical` |

## RBAC

marker 需要 `nodes.get/list/watch` 和 `nodes/status.patch` 权限来更新 capacity。

| 参数 | 描述 | 默认值 |
|---|---|---|
| `rbac.create` | 创建 ClusterRole + ClusterRoleBinding | `true` |
| `serviceAccount.create` | 创建 ServiceAccount | `true` |
| `serviceAccount.automountServiceAccountToken` | 挂载 SA token（marker 调 K8s API 必须） | `true` |

## NetworkAttachmentDefinition 示例

### 接入物理 VLAN

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: ovs-tenant-vlan100
  namespace: my-app
spec:
  config: |
    {
      "cniVersion": "0.4.0",
      "type": "ovs",
      "bridge": "br-tenant",
      "vlan": 100,
      "ipam": {
        "type": "whereabouts",
        "range": "10.100.0.0/24"
      }
    }
```

Pod 引用：

```yaml
metadata:
  annotations:
    k8s.v1.cni.cncf.io/networks: my-app/ovs-tenant-vlan100
spec:
  containers:
  - name: app
    resources:
      requests:
        ovs-cni.network.kubevirt.io/br-tenant: "1"   # 让调度器只调到有此桥的节点
```

### 接入 OVN tenant logical switch（裸 OVN，非 OVN-K8s 自管）

```yaml
spec:
  config: |
    {
      "cniVersion": "0.4.0",
      "type": "ovs",
      "bridge": "br-int"
    }
```

Pod 加 annotation 指定逻辑端口名（外部控制器预先在 OVN NB 创建好 port）：

```yaml
metadata:
  annotations:
    k8s.v1.cni.cncf.io/networks: '[{"name":"<NAD>","cni-args":{"ovnPort":"tenant-a-pod-001"}}]'
```

> **注意**：如果你用的是 **OVN-Kubernetes**，租户网络应该用 `UserDefinedNetwork` / `ClusterUserDefinedNetwork` CR + `ovn-k8s-cni-overlay` CNI，**不要**用 ovs-cni 去抢 br-int 的端口管理权。

## Uninstall

```bash
helm uninstall ovs-cni -n kube-system
```

> ⚠️ **不会**自动清理：
> - 宿主机 `/opt/cni/bin/ovs*` 二进制（initContainer 拷贝的副本）
> - 各节点上已存在的 OVS bridge / port
> - 已下发的 NetworkAttachmentDefinition
>
> 需要彻底清理时手动执行：
> ```bash
> for n in $(kubectl get node -o name); do
>   ssh ${n#node/} 'rm -f /opt/cni/bin/ovs /opt/cni/bin/ovs-mirror-producer /opt/cni/bin/ovs-mirror-consumer'
> done
> ```

## Upgrading

### To 1.0.0

第一个 release，无升级路径。
