# JuiceFS S3 Gateway 实际部署指南

本文档记录本 chart 的**真实生产部署场景**(取代 Ceph RGW 对租户提供 S3),含关键参数、`kubectl` 验证方法、以及用 S3 / WebDAV / HDFS 三种客户端验证部署是否成功。

> 敏感值(密码、token、镜像仓库等)已用 `<...>` 占位,实际部署请替换。

## 一、架构与前置条件

```
租户 → Cilium Ingress (host: s3.example.com) → juicefs-s3-gateway (3 副本, HA)
                                                    │
                          TiKV (元数据 + 去重索引)   +   Ceph RADOS (多池分层)
```

- **元数据引擎**：独立的 TiKV/PD 集群，连接串 `tikv://<pd-service>:2379/<volume>`
- **对象存储**：Ceph，三个 EC 成本池：
  - `juicefs-nvme-ec42`（热，tier 1）
  - `juicefs-ssd-ec42`（温，tier 2）
  - `juicefs-hdd-ec42`（冷，tier 0 默认）
- **镜像**：本 fork 的 ceph+TiKV 构建（`<registry>/juicefs:<tag>`）
- **卷**：部署前必须已 format（见第三节）

## 二、前置准备

### 2.1 Ceph 池与 cephx 用户（一次性，在 Ceph 侧执行）

```bash
# 三个 EC4+2 成本池（照集群实际的 ec profile / crush rule）
for m in nvme ssd hdd; do
  ceph osd pool create juicefs-$m-ec42 32 32 erasure ${m}-ec42-rbd-pool_ecprofile ${m}-ec42-rbd-pool-host
  ceph osd pool application enable juicefs-$m-ec42 juicefs
  ceph osd pool set juicefs-$m-ec42 pg_autoscale_mode on
done

# 专用 cephx 用户，权限收敛到三个池
ceph auth get-or-create client.juicefs \
  mon 'allow r' mgr 'allow r' \
  osd 'allow rwx pool=juicefs-nvme-ec42, allow rwx pool=juicefs-ssd-ec42, allow rwx pool=juicefs-hdd-ec42'
```

### 2.2 创建命名空间与 Ceph 配置 Secret

chart 不创建 ceph secret（keyring 敏感），需自行创建：

```bash
kubectl create namespace juicefs

# ceph.conf（含 mon_host）
cat > ceph.conf <<EOF
[global]
fsid = <ceph-fsid>
mon_host = v2:<mon1>:3300,v2:<mon2>:3300,v2:<mon3>:3300
EOF

# keyring（从 ceph auth get client.juicefs 获取）
cat > ceph.client.juicefs.keyring <<EOF
[client.juicefs]
	key = <cephx-key>
EOF

kubectl -n juicefs create secret generic ceph-client-conf \
  --from-file=ceph.conf \
  --from-file=ceph.client.juicefs.keyring
rm -f ceph.conf ceph.client.juicefs.keyring
```

## 三、格式化卷（部署前，一次性）

在能连到 TiKV + Ceph 的环境跑一个 Job（复用上面的 ceph secret）。默认桶落冷池、开去重、配热/温 tier、开 changelog：

```bash
kubectl -n juicefs apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata: {name: jfs-format, namespace: juicefs}
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: format
        image: <registry>/juicefs:<tag>
        command: ["/bin/sh","-c"]
        args:
        - |
          set -e
          META="tikv://<pd-service>:2379/prodjfs"
          juicefs format \
            --storage ceph --bucket ceph://juicefs-hdd-ec42 \
            --access-key ceph --secret-key client.juicefs \
            --dedup-tikv <pd-service>:2379 \
            "$META" prodjfs
          juicefs config "$META" --tier 1 --storage-class juicefs-nvme-ec42 --yes
          juicefs config "$META" --tier 2 --storage-class juicefs-ssd-ec42 --yes
          juicefs config "$META" --changelog --changelog-max-age 2h --yes
          juicefs status "$META" | grep -A22 Tiers
        volumeMounts: [{name: ceph, mountPath: /etc/ceph, readOnly: true}]
      volumes: [{name: ceph, secret: {secretName: ceph-client-conf}}]
EOF

# 看结果
kubectl -n juicefs logs job/jfs-format | grep -A22 Tiers
kubectl -n juicefs delete job jfs-format
```

## 四、部署 Gateway（Helm）

### 4.1 实际使用的 values（脱敏）

```yaml
# values-prod.yaml
image:
  registry: <registry>          # 例：ghcr.io
  repository: <org>/juicefs
  tag: <tag>                     # 生产建议钉不可变 tag，非 main
  pullPolicy: Always

replicaCount: 3
volumeName: prodjfs
multiBuckets: true
atimeMode: relatime              # tier aging 必须非 noatime

auth:
  rootUser: admin
  rootPassword: <STRONG_PASSWORD>          # 或改用 existingSecret
  metaUrl: "tikv://<pd-service>:2379/prodjfs"

ceph:
  enabled: true
  existingSecret: ceph-client-conf
  mountPath: /etc/ceph

tierAging:
  enabled: true
  demoteAfter: 720h              # 30 天未访问降冷
  scanInterval: 1h
  coldTier: 0                    # 冷 = tier0 (hdd)
  promote: true                  # 读时升热
  scanRate: 3000

bucketAdmin:
  enabled: true
  token: <BSS_ADMIN_TOKEN>       # 仅内网，给 BSS 控制面

service:
  type: ClusterIP

ingress:
  enabled: true
  ingressClassName: cilium
  hostname: s3.example.com
  path: /
  pathType: Prefix
  annotations:
    ingress.cilium.io/loadbalancer-mode: shared   # 复用共享 LB
```

### 4.2 安装

```bash
# common 是声明式依赖，先拉取
helm dependency build

helm upgrade --install juicefs-gw . \
  -n juicefs -f values-prod.yaml
```

> **注意**：`common` 未 vendored，务必先 `helm dependency build`，否则渲染报缺 `common.*` 模板。

## 五、用 kubectl 验证部署

```bash
# 1) 3 副本全 Ready
kubectl -n juicefs get pods -l app.kubernetes.io/name=juicefs-s3-gateway
# 预期：3 个 1/1 Running

# 2) 启动日志确认去重 / 分层 / changelog 已启用
POD=$(kubectl -n juicefs get pods -l app.kubernetes.io/name=juicefs-s3-gateway -o jsonpath='{.items[0].metadata.name}')
kubectl -n juicefs logs $POD | grep -iE "Data use|dedup|aging started|admin API"
# 预期看到：
#   Data use dedup://ceph://juicefs-hdd-ec42/prodjfs/
#   tier aging started (incremental): ... cold-tier=0 promote=true
#   gateway admin API listening on 0.0.0.0:9568

# 3) Service / Ingress
kubectl -n juicefs get svc,ingress
# S3 api service (9000) + admin service (9568) + ingress 拿到 LB 地址

# 4) 凭证 secret 正确（应是明文，非双重编码）
kubectl -n juicefs get secret juicefs-gw-juicefs-s3-gateway -o jsonpath='{.data.root-user}' | base64 -d; echo
# 预期：admin

# 5) HA 设施
kubectl -n juicefs get pdb juicefs-gw-juicefs-s3-gateway
```

## 六、用客户端测试是否成功

以下测试的「桶」在文件系统层面就是顶层目录，S3 / WebDAV / HDFS 三协议访问同一份数据、互相可见。

### 6.1 建桶（BSS admin API）

```bash
kubectl -n juicefs port-forward svc/juicefs-gw-juicefs-s3-gateway-admin 19568:9568 &

# 建三档桶：热(tier1)/温(tier2)/冷(tier0)
for spec in bkt-hot:1 bkt-warm:2 bkt-cold:0; do
  curl -s -X POST -H "Authorization: Bearer <BSS_ADMIN_TOKEN>" \
    --data "{\"name\":\"${spec%%:*}\",\"tier\":${spec##*:}}" \
    http://127.0.0.1:19568/buckets; echo
done
```

### 6.2 S3 客户端（boto3）

```bash
kubectl -n juicefs port-forward svc/juicefs-gw-juicefs-s3-gateway 19000:9000 &

python3 - <<'PY'
import boto3, os, hashlib
from botocore.config import Config
s3=boto3.client("s3", endpoint_url="http://127.0.0.1:19000",
    aws_access_key_id="admin", aws_secret_access_key="<STRONG_PASSWORD>",
    config=Config(s3={'addressing_style':'path'}))
# 写/读/校验
data=os.urandom(4*1024*1024)
s3.put_object(Bucket="bkt-hot", Key="test.bin", Body=data)
got=s3.get_object(Bucket="bkt-hot", Key="test.bin")["Body"].read()
print("S3 PUT/GET md5 match:", hashlib.md5(got).hexdigest()==hashlib.md5(data).hexdigest())
# 去重：相同内容写多个 key
for k in ("a.bin","b.bin","c.bin"): s3.put_object(Bucket="bkt-hot",Key=k,Body=data)
print("objects:", [o["Key"] for o in s3.list_objects_v2(Bucket="bkt-hot").get("Contents",[])])
PY
```

**验证落池**（相同内容多 key 只占一份物理对象）：

```bash
# 在 Ceph 侧看物理对象数
rados -p juicefs-nvme-ec42 ls | grep -c dedup   # 热桶数据落 nvme 池
# 3 个相同的 4MB 对象 → 只 +1 个 dedup 物理块（4MB/4MB=1），非 3
```

### 6.3 WebDAV 客户端

启动内置 WebDAV server（直连 TiKV+Ceph，无需 FUSE）：

```bash
kubectl -n juicefs apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: jfs-webdav, namespace: juicefs}
spec:
  replicas: 1
  selector: {matchLabels: {app: jfs-webdav}}
  template:
    metadata: {labels: {app: jfs-webdav}}
    spec:
      containers:
      - name: webdav
        image: <registry>/juicefs:<tag>
        command: ["/bin/sh","-c","juicefs webdav tikv://<pd-service>:2379/prodjfs 0.0.0.0:8080"]
        volumeMounts: [{name: ceph, mountPath: /etc/ceph, readOnly: true}]
      volumes: [{name: ceph, secret: {secretName: ceph-client-conf}}]
---
apiVersion: v1
kind: Service
metadata: {name: jfs-webdav, namespace: juicefs}
spec:
  selector: {app: jfs-webdav}
  ports: [{port: 8080, targetPort: 8080}]
EOF

kubectl -n juicefs port-forward svc/jfs-webdav 18080:8080 &
B=http://127.0.0.1:18080

# 列目录（S3 桶=目录）
curl -s -X PROPFIND -H "Depth: 1" $B/ | grep -oE "<D:href>[^<]*</D:href>" | sed 's/<[^>]*>//g'
# WebDAV 写/读
echo "via-webdav" | curl -s -T - $B/bkt-warm/from-webdav.txt -w "PUT: %{http_code}\n" -o /dev/null
curl -s $B/bkt-warm/from-webdav.txt
# 跨协议：读 S3 写的对象
curl -s $B/bkt-hot/test.bin -w "GET S3 对象: %{http_code}\n" -o /dev/null

# 清理
kubectl -n juicefs delete deploy,svc jfs-webdav
```

### 6.4 HDFS 客户端（Hadoop SDK）

JuiceFS 的 HDFS 兼容是 **Hadoop SDK（JAR）**，不是网关进程。需从源码构建 `juicefs-hadoop.jar`（`make -C sdk/java ceph`）。

> **重要 — glibc 依赖**：SDK 的 native 库 `libjfs.so` 是 glibc 编译的，**必须在 glibc 环境（Debian/Ubuntu + librados2）运行，不能用 Alpine/musl**，否则报 `initial-exec TLS resolves to dynamic definition`。

Hadoop 配置：

```xml
<property><name>fs.jfs.impl</name><value>io.juicefs.JuiceFileSystem</value></property>
<property><name>juicefs.meta</name><value>tikv://<pd-service>:2379/prodjfs</value></property>
```

访问路径 `jfs://prodjfs/bkt-hot/...`。SDK 会看到与 S3/WebDAV 相同的目录树（S3 桶=顶层目录），可跨协议读写。

> **权限提示**：网关以固定 UID（默认 1001）创建桶目录（0755）。用其他 UID（如 root）经 HDFS 写这些目录会被 POSIX 权限拒绝；生产用 Hadoop 访问时统一 UID 或调整目录权限。

## 七、外部暴露（Cilium Ingress）

本部署用 cilium ingress 的 **shared 模式**（`ingress.cilium.io/loadbalancer-mode: shared`），复用集群已有的 `cilium-ingress` 共享 LoadBalancer，按 host 路由，无需为每个 ingress 单独分配 LB IP：

```bash
kubectl -n juicefs get ingress juicefs-gw-juicefs-s3-gateway
# ADDRESS 列即共享 LB 的地址

# 从能路由到 LB 的位置测试（Host 头 + LB 地址）
curl -s -H "Host: s3.example.com" http://<LB-ADDRESS>/minio/health/live
# 预期：200
```

**DNS**：把 `s3.example.com` 解析到 LB 地址（或经 Cloudflare/边界网关转发）。租户用标准 S3 SDK 指向该域名即可。

## 八、生产前检查清单

- [ ] `image.tag` 钉不可变 tag（非 `main` 滚动 tag）
- [ ] `auth.rootPassword` / `bucketAdmin.token` 用强密码，或改 `existingSecret`
- [ ] 租户 IAM policy 排除 `s3:CreateBucket`/`s3:DeleteBucket`，建桶只走 admin API
- [ ] admin service（9568）仅内网可达，不经 ingress 暴露
- [ ] `atimeMode: relatime`（tier aging 生效前提）
- [ ] 多副本部署时 tier aging 参数一致（分片锁自动协调，无需选主）
- [ ] DNS 指向 ingress LB，确认边界可路由到 LB 地址段
- [ ] 已用真实数据样本评估去重命中率（压缩/加密格式命中低）
