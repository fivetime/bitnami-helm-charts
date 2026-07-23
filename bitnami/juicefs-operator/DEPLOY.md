# JuiceFS Operator 实际部署指南

本文档记录本 chart 的**真实部署场景**,含关键参数、`kubectl` 验证方法,以及一个**端到端 Sync 测试**(CE→CE,经我们的 TiKV+Ceph 后端)。

> 敏感值(镜像仓库、PD 地址、密码等)已用 `<...>` 占位,实际部署请替换。

## 一、这个 operator 能干什么(先看清 CE / EE 边界)

operator 本身只 reconcile CR、不碰后端;真正干活的是它拉起的 **worker pod/job**(用你在 CR 里指定的 JuiceFS 客户端镜像)。它管四种 CR:

| CR | CE(我们)可用 | 用途 |
| -- | :---: | ---- |
| **Sync / CronSync** | ✅ | `juicefs sync` 在两个存储间搬数据(一次性 / 定时) |
| **CacheGroup** | ❌ EE 专属 | 分布式缓存组(`juicefs mount --cache-group`,CE 没有此选项) |
| **WarmUp** | ❌ EE 专属 | 给缓存组预热,依赖 CacheGroup |

> **重要**:CE 的 `juicefs mount` 只有**本地缓存**(`--cache-dir/--cache-size`),没有 `--cache-group`。对 CE 卷创建 `CacheGroup`/`WarmUp` 会 reconcile 失败并报 `token is missing`(operator 在等 EE token)。所以在我们的 CE 栈里,operator 的实际价值是 **Sync/CronSync 数据搬运编排**,不是缓存加速。

## 二、架构与前置条件

```
juicefs-operator (Deployment, 2 副本, leader 选举)  ← 官方镜像,只 reconcile CR
        │ 创建
        ▼
Sync worker (Job/Pod)  ← fork 镜像(ceph+TiKV)  ──► TiKV(元数据) + Ceph RADOS(数据)
```

- **operator 镜像**:官方 `docker.io/juicedata/juicefs-operator:v0.8.4`
- **worker 镜像**:fork 的 ceph+TiKV 构建(在 CR 里按需指定)
- **卷**:已 format 的 `prodjfs`(与 CSI / S3 网关共用同一卷)
- **secret**:复用 CSI 建的 backend secret `juicefs-sc-secret` + ceph 配置 secret `ceph-client-conf`(均在 `juicefs` 命名空间)

## 三、部署 Operator(Helm)

### 3.1 实际使用的 values(脱敏)

```yaml
# operator-prod-values.yaml

# 覆盖资源名前缀,避免 <release>-<chart> 冗余(-> juicefs-operator)
fullnameOverride: juicefs-operator

# operator(controller-manager)用官方镜像 —— 只 reconcile CR,不碰后端
image:
  registry: docker.io
  repository: juicedata/juicefs-operator
  tag: v0.8.4
  pullPolicy: IfNotPresent

# HA:2 副本 + leader election(一活一备)
replicaCount: 2
leaderElection:
  enabled: true

logEncoder: console
logLevel: info
```

### 3.2 安装

```bash
# common 是声明式依赖,先拉取
helm dependency build

helm upgrade --install juicefs-operator . \
  -n juicefs -f operator-prod-values.yaml
```

> **注意**:`common` 未 vendored,务必先 `helm dependency build`。4 个 CRD 从 `crds/` 目录随首次安装装入;Helm 不会自动升级/删除 CRD,需自行管理。

## 四、用 kubectl 验证部署

```bash
# 1) 2 副本 Running
kubectl -n juicefs get pods -l app.kubernetes.io/name=juicefs-operator
# 预期:2 个 1/1 Running

# 2) 4 个 CRD 已装
kubectl get crd | grep juicefs.io
# cachegroups / cronsyncs / syncs / warmups .juicefs.io

# 3) leader 选举正常(一个 holder)
kubectl -n juicefs get lease | grep juicefs.io
# NAME 形如 xxxxxxxx.juicefs.io,HOLDER 指向其中一个 operator pod

# 4) 启动日志无报错、成为 leader
POD=$(kubectl -n juicefs get pods -l app.kubernetes.io/name=juicefs-operator -o jsonpath='{.items[0].metadata.name}')
kubectl -n juicefs logs $POD | grep -iE "starting|leader|controller"

# 5) HA 设施
kubectl -n juicefs get pdb juicefs-operator
```

## 五、端到端测试:Sync(CE→CE,经真实 TiKV+Ceph)

把卷内 `bkt-hot/` 的数据同步到新目录 `synced-from-operator/`,全程走 fork worker + TiKV + Ceph。

### 5.1 提交 Sync CR

```bash
kubectl apply -f - <<'EOF'
apiVersion: juicefs.io/v1
kind: Sync
metadata: {name: demo-sync, namespace: juicefs}
spec:
  image: <registry>/juicefs:<immutable-tag>   # fork 镜像,例:ghcr.io/fivetime/juicefs:sha-xxxxxxx
  replicas: 1
  ttlSecondsAfterFinished: 600                 # 完成后自动清理 worker
  from:
    juicefsCE:
      metaURL: tikv://<pd-service>:2379/prodjfs
      path: /bkt-hot/
      extraVolumes:                            # 注入 ceph 配置到 worker(CE Ceph 卷必须)
      - secret: {name: ceph-client-conf, mountPath: /etc/ceph}
  to:
    juicefsCE:
      metaURL: tikv://<pd-service>:2379/prodjfs
      path: /synced-from-operator/
      extraVolumes:
      - secret: {name: ceph-client-conf, mountPath: /etc/ceph}
EOF
```

> `juicefsCE.metaURL` 必填;数据在 Ceph,所以 worker 必须能读 `ceph.conf`+keyring —— 用 `extraVolumes.secret{name,mountPath}` 注入到 `/etc/ceph`。CE 卷会从 TiKV 里的卷设置自动读取 `storage=ceph`/`bucket`,无需再传 access/secret key。

### 5.2 观察与验证

```bash
# worker pod 由 operator 拉起
kubectl -n juicefs get pods | grep demo-sync
# juicefs-sync-demo-sync-manager  ...

# Sync 状态:Preparing -> Completed,progress 100%
kubectl -n juicefs get sync demo-sync -o jsonpath='{.status.phase}{" "}{.status.progress}{"\n"}'

# 完整统计 + worker 日志
kubectl -n juicefs get sync demo-sync -o jsonpath='{.status.stats}'; echo
# 预期:copied=4, copiedBytes≈25469911(24.29 MiB), failed=0
```

预期 worker 日志关键行:

```
Syncing from "jfs://prodjfs/bkt-hot/" to "jfs://prodjfs/synced-from-operator/"
Found: 4, ..., copied: 4 (24.29 MiB), ..., failed: 0
Sync finished
```

### 5.3 跨协议确认(可选)

经 S3 网关确认 operator 真的把数据写进了后端:

```bash
kubectl -n juicefs run s3v --rm -i --restart=Never --image=amazon/aws-cli \
  --env AWS_ACCESS_KEY_ID=<S3_ROOT_USER> --env AWS_SECRET_ACCESS_KEY=<S3_ROOT_PASSWORD> -- \
  --endpoint-url http://juicefs-s3:9000 s3 ls s3://synced-from-operator/
# 预期:a.bin / b.bin / c.bin / data.bin
```

### 5.4 CronSync(定时版)

`CronSync` = 带 `schedule`(cron 表达式)的 `Sync`,`spec.sync` 内嵌与上面相同的 `from`/`to`/`image`。用于周期性增量搬运,机制一致。

### 5.5 清理

```bash
kubectl -n juicefs delete sync demo-sync
# 删测试产生的目录(见下方「已知问题」——经 S3 网关删对象可能不生效,用 POSIX 直挂删)
```

## 六、已知问题 / 注意事项

- **S3 网关 DELETE 可能不生效**:实测经 S3 网关删除对象时返回成功但对象仍在;用 fork 镜像**直接 POSIX 挂载** `rm -rf` 可正常删除(数据完整性无碍)。清理 Sync 产生的目录时优先用 POSIX。这是网关删除路径的疑似 bug,建议单独排查。
- **CacheGroup/WarmUp 在 CE 不可用**:见第一节。若日后接入 EE,secret 需含 `token`,worker 镜像用 EE 客户端。
- **worker 镜像钉不可变 tag**:与 CSI 一致,别用 `:main` 滚动 tag。
- **operator 只需 API 权限**:它不连 TiKV/Ceph;后端连接只发生在 worker pod 内。

## 七、生产前检查清单

- [ ] `fullnameOverride` 设好,避免 `<release>-<chart>` 冗余名
- [ ] `replicaCount: 2` + `leaderElection.enabled: true`(HA)
- [ ] Sync CR 的 `spec.image` 钉不可变 tag(fork ceph+TiKV 构建)
- [ ] Ceph 卷的 Sync,`extraVolumes` 注入 `ceph-client-conf` 到 `/etc/ceph`
- [ ] 明确只用 `Sync`/`CronSync`(CE);不要对 CE 卷建 `CacheGroup`/`WarmUp`
- [ ] `ttlSecondsAfterFinished` 设置,避免 worker/job 堆积
- [ ] 如需 web UI,评估开启 `dashboard.enabled`(带 basic auth)
