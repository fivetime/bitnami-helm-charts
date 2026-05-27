# ovs-cni Helm Chart

ovs-cni 是一个 Kubernetes CNI 插件，把 Pod（或 KubeVirt 虚机）的网卡**挂到宿主机的 Open vSwitch 桥**上。本身**不做 IPAM 也不做控制平面** —— 它只负责"创建 veth、挂到指定 OVS 桥、可选打 VLAN tag、可选打 `external_ids:iface-id` 标签"。

> **关键认知**：ovs-cni 是**控制平面无关**的纯 dataplane 插件。它最终是 **underlay 还是 overlay**、**租户隔离与否**、**谁分 IP**、**谁管 SG/ACL**，**完全取决于上游怎么接 OVS 桥**。本 chart 把它装好，剩下的看你怎么用。

## 镜像与组件

[官方上游镜像](https://github.com/k8snetworkplumbingwg/ovs-cni)一个镜像里同时打包了 4 个二进制：

| 二进制 | 类型 | 作用 |
|---|---|---|
| `ovs` | CNI 插件 | 主 CNI 二进制，被 multus 调，建 veth、挂桥、打 tag |
| `ovs-mirror-producer` | CNI 插件 | 把 pod 接口流量**镜像出去**（喂给 IDS / 抓包） |
| `ovs-mirror-consumer` | CNI 插件 | 把镜像流量**收进来**（流量分析器 pod 用） |
| `marker` | 常驻 daemon | 把宿主机的 OVS bridge 暴露为 K8s Node 资源，供调度器使用 |

通过**单一 DaemonSet** 部署：initContainer 拷贝前 3 个 CNI 二进制到宿主机 `/opt/cni/bin/`，主容器跑 `marker`。

## 快速开始

```bash
# 1. 宿主机先装好 Open vSwitch 并启动（举例 Ubuntu）
apt-get install -y openvswitch-switch
systemctl enable --now openvswitch-switch

# 2. 在每个 worker 上建好需要暴露给 K8s 的桥（按场景，见下文"用法"）
ovs-vsctl add-br br-tenant
ovs-vsctl add-port br-tenant eth1   # 物理 trunk 网卡

# 3. 安装 chart
helm install ovs-cni ./ovs-cni -n kube-system

# 4. 看 marker 是否把桥注册成 K8s 资源
kubectl get node -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.capacity}{"\n"}{end}' | grep ovs-cni
```

> **前置条件**：
> 1. 集群必须已装 **multus-cni**（或其它 CNI meta-plugin），ovs-cni 不是主 CNI，只能作为 NetworkAttachmentDefinition 的下游驱动被调用。
> 2. 每个目标节点必须已经安装并运行 **Open vSwitch**（默认 `/var/run/openvswitch/db.sock` 可用），并已建好待暴露的 bridge。

---

## 用法场景

`ovnPort` 这个 CNI arg 决定了 ovs-cni 是否走 OVN 控制平面。组合 OVS 桥的两种形态（裸 OVS vs OVN 管控）以及"是否启用 OVN logical switch"，共 **5 类场景**：

| 场景 | OVN 控制面 | OVS 桥归属 | Data plane | 多租户隔离 | IPAM | SG/ACL |
|---|---|---|---|---|---|---|
| **A. 物理 VLAN underlay** | 无 | 你自己建的 | underlay（VLAN trunk） | VLAN | K8s IPAM | 无 / NetworkPolicy |
| **B. Neutron tenant net (Geneve)** | Neutron 管 OVN | ovn-controller 管 br-int | **overlay**（Geneve）| OVN logical switch | Neutron | Neutron SG ✓ |
| **C. Neutron provider net (VLAN)** | Neutron 管 OVN | ovn-controller 管 br-int | **underlay**（localnet）| 物理 VLAN | Neutron | Neutron SG ✓ |
| **D. 裸 OVN 自管** | 你自己 `ovn-nbctl` 管 | ovn-controller 管 br-int | overlay 或 underlay 自选 | OVN logical switch | 你自管 | 你自管 |
| **E. OVN-Kubernetes 集群** | ovnkube 独占 | ovnkube 独占 br-int | — | — | — | — |

---

### 场景 A：物理 VLAN underlay（不用 OVN）

**适用**：物理网络已规划好 VLAN，希望 pod 直接接入某个 VLAN 拿真实 IP（与裸金属机/VM 同段）。不需要多租户隔离 + Neutron 的精细控制。

**节点准备**（每节点）：
```bash
ovs-vsctl add-br br-tenant
ovs-vsctl add-port br-tenant eth1   # 物理 trunk
```

**NetworkAttachmentDefinition**：
```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: tenant-vlan100
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

**Pod**：
```yaml
metadata:
  annotations:
    k8s.v1.cni.cncf.io/networks: my-app/tenant-vlan100
spec:
  containers:
  - name: app
    image: ...
    resources:
      requests:
        ovs-cni.network.kubevirt.io/br-tenant: "1"   # 调度器只调到有此桥的节点
```

**Data plane**：pod veth → `br-tenant` 上 access port (tag=100) → 物理 trunk → 物理交换机 VLAN 100 → 其它节点/VM/物理机。**无封装**，TOR 能看到 ARP。

---

### 场景 B：Neutron-managed OVN，tenant network（overlay）

**适用**：集群本身就是 OpenStack 的一部分，希望 K8s pod 与 Nova VM **在同一张 Neutron 租户网络上互通**。这是 KubeVirt + OpenStack、Telco CNF 的典型用法。

**节点准备**（每节点必须满足）：
1. 节点本身是 **Neutron compute / OVN chassis**（跑 `ovn-controller`，已注册到 OVN SB chassis 表）
2. 节点的 `br-int` 就是 ovn-controller 管控的那个（**不要**有第二个 OVN 控制平面，不能有 ovnkube）
3. 配好 `ovn-bridge-mappings`、`ovn-encap-ip`、`ovn-encap-type=geneve` 等 chassis 配置

**外部流程**（典型用 K8s controller / operator 编排）：
```bash
# 1. 调 Neutron API 建 port（在已有的 tenant network 上）
openstack port create --network tenant-net-1 \
                      --fixed-ip ip-address=10.0.0.5 \
                      my-pod-port
# 拿到 port UUID，例如 abc-123-def-456
```

**NetworkAttachmentDefinition**（不写 `bridge` —— 让 ovs-cni 自动回退到 `br-int`）：
```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: neutron-tenant-net
  namespace: tenant-a
spec:
  config: |
    {
      "cniVersion": "0.4.0",
      "type": "ovs"
    }
```

**Pod**：
```yaml
metadata:
  annotations:
    k8s.v1.cni.cncf.io/networks: |
      [{
        "name": "neutron-tenant-net",
        "namespace": "tenant-a",
        "cni-args": {
          "ovnPort": "abc-123-def-456"
        }
      }]
spec:
  containers:
  - name: app
    image: ...
```

**Data plane**：pod veth → `br-int` → ovn-controller 见 `iface-id=abc-123-def-456` 与 SB 中某 LSP 匹配 → **Geneve 隧道**到承载这条 LSP 的对端 chassis → 解封 → 目标 pod / Nova VM。**跨节点封装**，物理网络只见 Geneve UDP。

**IP/MAC/SG 全部 Neutron 分配**：不要在 NAD 里设 `ipam`，Neutron port 已经携带 fixed-ip 和 mac，OVN 会下发 ACL。

---

### 场景 C：Neutron-managed OVN，provider network（underlay）

**适用**：Neutron 已经规划好 provider network（直接落在物理 VLAN 上），希望 pod 拿到 provider 网段的 IP，享受 Neutron 的 SG 但走 underlay。

**节点准备**：和场景 B 完全一样（chassis 注册 + bridge-mappings）。Neutron 那边 provider net 的 logical switch **已经带 localnet port**，对应 `bridge-mappings` 里的物理桥。

**外部流程 + NAD + Pod**：和场景 B **完全一样**，唯一区别是 `openstack port create` 的 `--network` 指定**provider network**（如 `flat-physnet1` 或 `vlan-physnet1-100`）。

**Data plane**：pod veth → `br-int` → ovn-controller 见 iface-id 匹配 LSP → **沿 localnet port 出 br-int** → 经 `ovn-bridge-mappings` 到 `br-provider` → 物理 trunk（带 VLAN tag） → 物理交换机。**无 Geneve 封装**，TOR 能看到 ARP，pod IP 就是物理段。

> 场景 B vs C 的差别**完全在 Neutron 那边**（network 创建时的 type），ovs-cni / NAD / Pod 写法**没区别**。

---

### 场景 D：裸 OVN 自管（不用 Neutron）

**适用**：想要 OVN 的多租户能力（logical switch / router / ACL / NAT），但不想引入 OpenStack 全套；典型是用一个自己写的 K8s controller 直接调 `ovn-nbctl` 管 NB。

**节点准备**：
1. 每个节点跑 OVS + ovn-controller，注册到 OVN SB 作为 chassis
2. 部署 OVN central（NB/SB/ovn-northd），独立于 K8s（或者作为 K8s pod 都行）
3. **绝对不要装 OVN-Kubernetes**（会和你的 controller 抢 NB）

**外部流程**（举例）：
```bash
# 1. 自己建 logical switch
ovn-nbctl ls-add tenant-a-ls

# 2. 在 ls 上建 logical port
ovn-nbctl lsp-add tenant-a-ls tenant-a-pod-001
ovn-nbctl lsp-set-addresses tenant-a-pod-001 "02:00:00:00:01:01 10.10.0.5"

# 3. (overlay) 不加 localnet → tenant-a-ls 是 Geneve overlay
#    (underlay) 加 localnet port → tenant-a-ls 落到物理 VLAN
```

**NAD + Pod**：和场景 B 完全一样（不写 bridge，`cni-args.ovnPort` 指定 lsp 名）。

**Data plane**：取决于 logical switch 类型（同场景 B/C）。

---

### 场景 E：OVN-Kubernetes 集群 —— ⛔ 不要用 ovs-cni 做租户网络

如果集群已经装了 **OVN-Kubernetes**（你这套 eks1 集群就是）：

- `br-int` 被 **ovnkube-controller 独占**，所有 LSP 由 ovnkube 自动生成
- 你手工 `ovn-nbctl lsp-add` 创建的 port 会被 ovnkube **删掉**或与它的 port 命名冲突
- **iface-id 的命名是 ovnkube 内部生成的**（如 `<namespace>_<pod>`），你无法事先获知

✅ **正确做法**：用 OVN-Kubernetes 自带的 **`UserDefinedNetwork` / `ClusterUserDefinedNetwork` CR**：

```yaml
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: tenant-a-network
spec:
  namespaceSelector:
    matchLabels:
      tenant: a
  network:
    topology: Layer3
    layer3:
      role: Primary
      subnets:
        - cidr: 10.100.0.0/16
          hostSubnet: 24
```

ovnkube 自动建 logical switch、自动管 IP/MAC/ACL、自动创建 NAD（`ovn-k8s-cni-overlay` 类型）。你只需给 namespace 打标签 + pod 加 `k8s.v1.cni.cncf.io/networks` 引用即可。**这才是 OVN-K8s 的"租户网络"标准方式**。

→ 在 OVN-K8s 集群里，**ovs-cni 只适合场景 A**（自己管的桥，与 OVN-K8s 的 `br-int` 完全隔离）。

---

## 决策树

```
你想给 pod 接什么样的网络？
│
├─ 物理 VLAN 直通（与裸金属/VM 共段）
│  └─→ 【场景 A】裸 OVS bridge + trunk
│
├─ 多租户隔离 + OpenStack 已经在场
│  └─→ 【场景 B 或 C】Neutron + ovs-cni (ovnPort)
│      - Neutron 建 tenant net → overlay
│      - Neutron 建 provider net → underlay
│
├─ 多租户隔离 + 不想要 OpenStack
│  ├─ 已有 OVN-K8s 集群 →【场景 E】用 UDN/CUDN
│  └─ 没有 OVN-K8s 想自己搞 →【场景 D】裸 OVN + ovs-cni
│
└─ KubeVirt VM 与 Nova VM 拉同一段
   └─→ 【场景 B】Neutron tenant network（overlay）
```

---

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

---

## CNI 二进制开关

| 参数 | 二进制 | 作用 | 关闭时机 |
|---|---|---|---|
| `plugins.ovs` | `/opt/cni/bin/ovs` | 主 CNI 插件 | 几乎不会关 |
| `plugins.mirrorProducer` | `/opt/cni/bin/ovs-mirror-producer` | 接口流量镜像出 | 不做流量分析时 |
| `plugins.mirrorConsumer` | `/opt/cni/bin/ovs-mirror-consumer` | 接口流量镜像入 | 不做流量分析时 |

至少要开一个，否则 chart 渲染时会 `helm: fail`。

---

## OVSDB Socket 配置

| 参数 | 描述 | 默认值 |
|---|---|---|
| `ovsSocket.type` | `unix` 或 `tcp` | `unix` |
| `ovsSocket.path` | unix socket 路径（宿主机） | `/var/run/openvswitch/db.sock` |
| `ovsSocket.host` | tcp 模式：OVSDB host | `""` |
| `ovsSocket.port` | tcp 模式：OVSDB port | `6640` |

`unix` 模式 chart 会自动 hostPath 挂载该 socket 所在目录到 `/host` 下。

---

## 镜像配置

| 参数 | 描述 | 默认值 |
|---|---|---|
| `image.registry` | 镜像仓库 | `ghcr.io` |
| `image.repository` | 镜像名 | `k8snetworkplumbingwg/ovs-cni-plugin` |
| `image.tag` | 镜像标签 | `latest` |
| `image.digest` | 镜像 digest（覆盖 tag） | `""` |
| `image.pullPolicy` | 拉取策略 | `IfNotPresent` |
| `image.debug` | 调试日志 | `false` |

---

## 路径配置

| 参数 | 描述 | 默认值 |
|---|---|---|
| `hostCNIBinDir` | 宿主机 CNI 插件目录 | `/opt/cni/bin` |
| `CNIMountPath` | 容器内挂载宿主机 CNI 目录的前缀 | `/host` |

---

## 资源 / 调度

| 参数 | 描述 | 默认值 |
|---|---|---|
| `resourcesPreset` | bitnami 预设档位（none/nano/micro/small/...） | `nano` |
| `resources` | 直接指定 requests/limits | `{}` |
| `nodeSelector` | 默认 `kubernetes.io/os: linux` | (Linux) |
| `tolerations` | 默认全部 Exists（覆盖所有 taint） | (所有) |
| `priorityClassName` | 优先级类 | `system-node-critical` |

---

## RBAC

marker 需要 `nodes.get/list/watch` 和 `nodes/status.patch` 权限来更新 capacity。

| 参数 | 描述 | 默认值 |
|---|---|---|
| `rbac.create` | 创建 ClusterRole + ClusterRoleBinding | `true` |
| `serviceAccount.create` | 创建 ServiceAccount | `true` |
| `serviceAccount.automountServiceAccountToken` | 挂载 SA token（marker 调 K8s API 必须） | `true` |

---

## 卸载

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

---

## Upgrading

### To 1.0.0

第一个 release，无升级路径。
