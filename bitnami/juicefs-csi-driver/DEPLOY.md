# JuiceFS CSI Driver 实际部署指南

本文档记录本 chart 的**真实生产部署场景**(给 k8s 工作负载提供 JuiceFS 持久卷),含关键参数、`kubectl` 验证方法、StorageClass / PVC 的创建,以及 **RWO / RWX 访问模式的测试矩阵**。

> 敏感值(镜像仓库、PD 地址、cephx 等)已用 `<...>` 占位,实际部署请替换。

## 一、架构与前置条件

```
App Pod ──(bind mount)── Mount Pod【fork 镜像:ceph+TiKV】── TiKV(元数据) + Ceph RADOS(数据)
   ▲                          ▲
   │ PVC (juicefs-sc)         │ CSI node 插件按需拉起
   └──────────────────────────┘
CSI 控制面【官方镜像】:controller(StatefulSet, 2 副本) + node(DaemonSet, 每节点)
```

- **CSI 控制面镜像**:官方 `docker.io/juicedata/juicefs-csi-driver:v0.32.0`(只做编排,不碰后端)
- **Mount pod 镜像**:本 fork 的 ceph+TiKV 构建(`<registry>/juicefs:<tag>`)——**真正连存储的数据平面**
- **元数据引擎**:独立 TiKV/PD 集群,`tikv://<pd-service>:2379/<volume>`
- **对象存储**:Ceph RADOS 池(如 `juicefs-hdd-ec42`)
- **卷**:部署前必须已 format(与 S3 网关共用同一个 `prodjfs` 卷,见 juicefs-s3-gateway/DEPLOY.md 第三节)

> 说明:CSI 与 S3 网关访问的是**同一个 JuiceFS 卷**。CSI 建的 PV 子目录,在 S3 网关侧就表现为顶层「桶」/目录,同一份数据 POSIX 与 S3 两条路都能看到。

## 二、前置准备

### 2.1 命名空间与 Ceph 配置 Secret

mount pod 需要 `ceph.conf` + cephx keyring 才能连 RADOS。chart 不创建该 secret(keyring 敏感),自行创建(与 S3 网关复用同一个):

```bash
kubectl create namespace juicefs

cat > ceph.conf <<EOF
[global]
fsid = <ceph-fsid>
mon_host = v2:<mon1>:3300,v2:<mon2>:3300,v2:<mon3>:3300
EOF

cat > ceph.client.juicefs.keyring <<EOF
[client.juicefs]
	key = <cephx-key>
EOF

kubectl -n juicefs create secret generic ceph-client-conf \
  --from-file=ceph.conf \
  --from-file=ceph.client.juicefs.keyring
rm -f ceph.conf ceph.client.juicefs.keyring
```

> 该 secret 必须与 CSI 部署在**同一命名空间**(`juicefs`);它会被 node 插件注入到每个 mount pod 的 `/etc/ceph`(通过 StorageClass backend 的 `configs` 字段)。

## 三、部署 CSI(Helm)

### 3.1 实际使用的 values(脱敏)

```yaml
# csi-prod-values.yaml

# 覆盖资源名前缀,避免 <release>-<chart> 冗余(-> juicefs-csi-controller / juicefs-csi-node)
fullnameOverride: juicefs

# CSI controller/node 用官方镜像(只做编排)
image:
  registry: docker.io
  repository: juicedata/juicefs-csi-driver
  tag: v0.32.0
  pullPolicy: IfNotPresent

# mount pod 用 fork 镜像(ceph+TiKV 支持)——生产钉不可变 tag,别用 :main
defaultMountImage:
  ce: <registry>/juicefs:<immutable-tag>   # 例:ghcr.io/fivetime/juicefs:sha-xxxxxxx

mountMode: mountpod
kubeletDir: /var/lib/kubelet

controller:
  replicas: 2                       # HA + leader election(默认已开)
node:
  enabled: true
  mountPodNonPreempting: true       # 保护 mount pod 不被抢占/驱逐(推荐)

# StorageClass:连已 format 的 prodjfs 卷
storageClasses:
  - name: juicefs-sc
    enabled: true
    reclaimPolicy: Delete
    allowVolumeExpansion: true
    backend:
      name: prodjfs
      metaurl: tikv://<pd-service>:2379/prodjfs
      storage: ceph
      bucket: ceph://juicefs-hdd-ec42
      accessKey: ceph                          # cephx 用户名
      secretKey: client.juicefs                # cephx client id
      configs: "{ceph-client-conf: /etc/ceph}" # 把 ceph secret 注入 mount pod
    mountOptions: []
```

### 3.2 安装

```bash
# common 是声明式依赖,先拉取
helm dependency build

helm upgrade --install juicefs-csi . \
  -n juicefs -f csi-prod-values.yaml
```

> **注意**:`common` 未 vendored,务必先 `helm dependency build`,否则渲染报缺 `common.*` 模板。

## 四、用 kubectl 验证部署

```bash
# 1) controller 2 副本 3/3,node 每节点 3/3
kubectl -n juicefs get pods -l app.kubernetes.io/name=juicefs-csi-driver -o wide
#   juicefs-csi-controller-0 / -1     3/3 Running
#   juicefs-csi-node-xxxxx  (每个可调度节点一个)   3/3 Running

# 2) controller 能定位 node 插件(自愈/发布的前提)
kubectl -n juicefs logs juicefs-csi-controller-0 -c juicefs-plugin | \
  grep -iE "Run CSI controller|Get CSI pod successfully|Listening"
#   "Run CSI controller" / "Get CSI pod successfully" / "Listening for connection on address"

# 3) CSIDriver 与 StorageClass 就位
kubectl get csidrivers csi.juicefs.com
kubectl get sc juicefs-sc
#   PROVISIONER = csi.juicefs.com

# 4) backend secret 已生成
kubectl -n juicefs get secret juicefs-sc-secret

# 5) HA 设施
kubectl -n juicefs get pdb
```

## 五、创建 StorageClass / PVC(独立于 chart)

StorageClass 已由 3.1 的 values 创建(`juicefs-sc`)。如需**额外的** SC(比如换池/换 tier),可单独 apply——注意 provisioner 与 secret 引用:

```bash
kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: {name: juicefs-sc-ssd}
provisioner: csi.juicefs.com
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: Immediate
parameters:
  csi.storage.k8s.io/provisioner-secret-name: juicefs-sc-secret       # 复用已有 backend secret
  csi.storage.k8s.io/provisioner-secret-namespace: juicefs
  csi.storage.k8s.io/node-publish-secret-name: juicefs-sc-secret
  csi.storage.k8s.io/node-publish-secret-namespace: juicefs
EOF
```

> 生产上更推荐把 SC 都写进 chart 的 `storageClasses`(连 backend secret 一起管理),而不是手工 apply。

## 六、RWO / RWX 测试矩阵

以下测试**都在应用 pod 上设 `mountPropagation: HostToContainer`**——这是 mount pod 自愈能无缝传播回 app pod 的前提(见第七节)。

| 场景 | 访问模式 | 拓扑 | 验证点 |
| ---- | -------- | ---- | ------ |
| A | RWO (ReadWriteOnce) | 单节点单 pod | 读/写/持久化;mount pod 最多 1 个 |
| B | RWX (ReadWriteMany) | 多节点多 pod(反亲和) | 跨节点共享读写、实时可见;每节点 1 个 mount pod |

### 6.1 场景 A:RWO

```bash
kubectl -n juicefs apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: jfs-rwo, namespace: juicefs}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: juicefs-sc
  resources: {requests: {storage: 10Gi}}
---
apiVersion: v1
kind: Pod
metadata: {name: rwo-app, namespace: juicefs}
spec:
  containers:
  - name: app
    image: busybox
    command: ["sh","-c","sleep 3600"]
    volumeMounts:
    - {name: vol, mountPath: /data, mountPropagation: HostToContainer}
  volumes:
  - name: vol
    persistentVolumeClaim: {claimName: jfs-rwo}
EOF

# 等 PVC Bound + pod Running(首次会拉 fork 镜像 + 起 mount pod,稍慢)
kubectl -n juicefs wait --for=condition=Ready pod/rwo-app --timeout=180s

# 写 / 读 / 追加 / 持久化
kubectl -n juicefs exec rwo-app -- sh -c '
  echo "rwo from $(hostname)" > /data/rwo.txt
  cat /data/rwo.txt
  echo "second line" >> /data/rwo.txt
  ls -l /data/; cat /data/rwo.txt'

# 观察 mount pod(RWO 只在 app 所在节点起一个)
kubectl -n juicefs get pods -o wide | grep "juicefs-.*-pvc-"
```

### 6.2 场景 B:RWX(跨节点共享)

```bash
kubectl -n juicefs apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: jfs-rwx, namespace: juicefs}
spec:
  accessModes: [ReadWriteMany]
  storageClassName: juicefs-sc
  resources: {requests: {storage: 10Gi}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: rwx-app, namespace: juicefs}
spec:
  replicas: 2
  selector: {matchLabels: {app: rwx-app}}
  template:
    metadata: {labels: {app: rwx-app}}
    spec:
      affinity:                         # 强制两副本落不同节点
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - topologyKey: kubernetes.io/hostname
            labelSelector: {matchLabels: {app: rwx-app}}
      containers:
      - name: app
        image: busybox
        command: ["sh","-c","echo hi-from-$(hostname) > /data/$(hostname).txt; sleep 3600"]
        volumeMounts:
        - {name: vol, mountPath: /data, mountPropagation: HostToContainer}
      volumes:
      - name: vol
        persistentVolumeClaim: {claimName: jfs-rwx}
EOF

# 等两副本 Running(应在不同节点)
kubectl -n juicefs rollout status deploy/rwx-app --timeout=180s
kubectl -n juicefs get pods -l app=rwx-app -o wide     # NODE 列应不同

# 取两个 pod
PODS=($(kubectl -n juicefs get pods -l app=rwx-app -o jsonpath='{.items[*].metadata.name}'))
A=${PODS[0]}; B=${PODS[1]}

# 互相看到对方启动时写的文件
kubectl -n juicefs exec $A -- ls -l /data/

# 跨节点实时可见:A 写,B 立即读
kubectl -n juicefs exec $A -- sh -c 'echo "live-from-A $(date +%T)" > /data/cross.txt'
kubectl -n juicefs exec $B -- cat /data/cross.txt          # 应读到 A 写的

# 反向:B 追加,A 读
kubectl -n juicefs exec $B -- sh -c 'echo "append-by-B $(date +%T)" >> /data/cross.txt'
kubectl -n juicefs exec $A -- cat /data/cross.txt          # 应含两行

# 每节点一个 mount pod(RWX 用到几个节点就几个)
kubectl -n juicefs get pods -o wide | grep "juicefs-.*-pvc-"
```

> **要点**:RWX 的跨节点一致性由 TiKV(元数据)+ Ceph(数据)那一层保证,不是靠 pod 间直接通信。RWO 并非「不起 mount pod」,而是 k8s 语义限制它只能落单节点,故 mount pod 最多 1 个。

### 6.3 清理

```bash
kubectl -n juicefs delete deploy rwx-app
kubectl -n juicefs delete pod rwo-app
kubectl -n juicefs delete pvc jfs-rwo jfs-rwx      # reclaimPolicy=Delete 会一并回收 PV 子目录
```

## 七、Mount pod 自愈演示(误杀恢复)

验证「不小心把 mount pod 删了」不会导致业务永久中断:

```bash
# 选一个 RWX mount pod 及其所在节点的 app pod
MP=$(kubectl -n juicefs get pods -o wide | grep "juicefs-.*-pvc-.*" | grep <node> | awk '{print $1}')
APP=$(kubectl -n juicefs get pods -l app=rwx-app -o wide | grep <node> | awk '{print $1}')

kubectl -n juicefs exec $APP -- sh -c 'echo baseline > /data/heal.txt'

# 误杀
kubectl -n juicefs delete pod $MP

# CSI 约 10s 内自动重建一个新的 mount pod
kubectl -n juicefs get pods -o wide | grep "juicefs-.*-pvc-.*" | grep <node>

# app pod 全程不重启;约 20~30s 后 I/O 自动恢复
kubectl -n juicefs exec $APP -- sh -c 'cat /data/heal.txt && echo recovered >> /data/heal.txt'
```

**结论**:mount pod 被误删,无需人工干预、也不用重启业务 pod,约 20~30s 自动恢复,数据无损。前提两件事(本 chart / 本文档已满足):

1. 集群侧 mount pod recovery(`jfs-fuse-fd` hostPath,chart 默认已配)
2. app pod 的 volumeMount 设 `mountPropagation: HostToContainer`(第六节已设)

> 若曾对已在跑的 CSI 改过 node ServiceAccount 名(如加/改 `fullnameOverride` 引起 SA 改名),改名前存在的 mount pod 仍引用旧 SA,重建会报 `serviceaccount ... not found`。处理:重启这些卷的消费 app pod,让 CSI 用新 SA 重新拉起 mount pod。

## 八、生产前检查清单

- [ ] `defaultMountImage.ce` 钉**不可变 tag**(sha/版本),别用 `:main` 滚动 tag(`IfNotPresent` 不会重拉已缓存的可变 tag)
- [ ] `fullnameOverride` 下渲染出的 pod 名仍含 `csi-controller` / `csi-node` 子串(模式判定依赖)
- [ ] 所有消费 JuiceFS 卷的业务 pod 设 `mountPropagation: HostToContainer`(自愈无缝的前提)
- [ ] `node.mountPodNonPreempting: true`(mount pod 抗抢占)
- [ ] ceph secret 与 CSI 同命名空间,且在 StorageClass backend 的 `configs` 里引用
- [ ] `kubeletDir` 匹配发行版(k0s/microk8s 非默认路径)
- [ ] 收紧 `juicefs` 命名空间 RBAC,避免运维随手 `kubectl delete` mount pod
- [ ] mount pod 镜像含 `mount.juicefs` 软链(fork 镜像已内置;否则报 `/bin/mount.juicefs: not found`)
