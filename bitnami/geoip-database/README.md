# GeoIP Database Helm Chart

GeoIP Database as a Service - 通过 RWX PVC 共享 GeoLite2/GeoIP2 数据库。

## 概述

这个 Helm chart 将 GeoIP 数据库部署为独立的基础设施服务，任何需要 IP 地理定位功能的 Pod 都可以挂载使用。

### 特性

- 📦 支持 MaxMind 直连和 GitHub Relay 两种数据源
- 🔄 自动更新（CronJob）
- 📂 RWX PVC 共享，支持多 Pod 同时访问
- 🔔 Hash ConfigMap 用于触发依赖应用的滚动更新
- 🔒 支持公开和私有仓库

## 安装

### 前置条件

- Kubernetes 1.23+
- Helm 3.8+
- 支持 ReadWriteMany 的 StorageClass（如 NFS, CephFS, EFS 等）

### 添加依赖

```bash
helm dependency build
```

### 安装（MaxMind 直连模式）

```bash
helm install geoip ./geoip-database \
  --set source.type=maxmind \
  --set source.maxmind.accountId=YOUR_ACCOUNT_ID \
  --set source.maxmind.licenseKey=YOUR_LICENSE_KEY \
  --set storage.storageClass=nfs-client
```

### 安装（GitHub Relay 模式 - 公开仓库）

```bash
helm install geoip ./geoip-database \
  --set source.type=github \
  --set source.github.owner=YOUR_USERNAME \
  --set update.image.repository=YOUR_USERNAME/geoip-update-relay \
  --set storage.storageClass=nfs-client
```

### 安装（GitHub Relay 模式 - 私有仓库）

```bash
# 1. 创建镜像拉取密钥
kubectl create secret docker-registry ghcr-pull-secret \
  --docker-server=ghcr.io \
  --docker-username=YOUR_USERNAME \
  --docker-password=ghp_xxxxx

# 2. 安装
helm install geoip ./geoip-database \
  --set source.type=github \
  --set source.github.owner=YOUR_USERNAME \
  --set source.github.token=ghp_xxxxx \
  --set update.image.repository=YOUR_USERNAME/geoip-update-relay \
  --set update.image.pullSecrets[0]=ghcr-pull-secret \
  --set storage.storageClass=nfs-client
```

## 卸载

### 默认卸载（删除所有资源包括 PVC）

```bash
helm uninstall geoip
```

**注意**: 默认情况下，卸载会删除 PVC 和其中的数据。

### 保留 PVC 数据

如果需要在卸载时保留 PVC，有两种方式：

**方式 1**: 安装时设置 `storage.resourcePolicy=keep`

```bash
helm install geoip ./geoip-database \
  --set storage.resourcePolicy=keep \
  ...
```

**方式 2**: 卸载前手动添加注解

```bash
kubectl annotate pvc geoip-data "helm.sh/resource-policy=keep"
helm uninstall geoip
```

保留的 PVC 需要手动删除：

```bash
kubectl delete pvc geoip-data
```

### 卸载时的资源清理

| 资源类型 | 卸载行为 |
|---------|---------|
| CronJob | ✅ 删除 |
| CronJob 创建的 Jobs | ✅ 级联删除 |
| Init Job (Hook) | ✅ 删除（成功/失败都会删除） |
| ConfigMap (Hash) | ✅ 删除 |
| Secret | ✅ 删除 |
| ServiceAccount | ✅ 删除 |
| RBAC (Role/RoleBinding) | ✅ 删除 |
| PVC | ⚠️ 默认删除，可通过 `resourcePolicy=keep` 保留 |

## 跨命名空间共享

Kubernetes PVC 是命名空间级别的资源，无法直接跨命名空间访问。`geoip-database` 负责数据库的更新写入，其他命名空间的应用只需要只读访问。

### 架构概述

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          底层存储 (NFS/CephFS/EFS)                       │
│                         /exports/geoip-data                             │
└─────────────────────────────────┬───────────────────────────────────────┘
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        │                         │                         │
        ▼                         ▼                         ▼
┌───────────────┐         ┌───────────────┐         ┌───────────────┐
│ namespace:    │         │ namespace:    │         │ namespace:    │
│ geoip         │         │ app-a         │         │ app-b         │
│               │         │               │         │               │
│ PVC (RWX)     │         │ PVC (ROX)     │         │ PVC (ROX)     │
│ CronJob (写入)│         │ Pod (只读)    │         │ Pod (只读)    │
└───────────────┘         └───────────────┘         └───────────────┘
```

### 方案 1: 静态 PV 共享（推荐）

创建额外的静态 PV，让其他命名空间的 PVC 绑定到相同的底层存储路径。

**步骤 1**: 正常安装 geoip-database

```bash
helm install geoip ./geoip-database \
  --namespace geoip --create-namespace \
  --set storage.storageClass=nfs-client \
  --set storage.resourcePolicy=keep
```

**步骤 2**: 获取底层存储路径

```bash
# 获取 PV 名称
PV_NAME=$(kubectl get pvc geoip-data -n geoip -o jsonpath='{.spec.volumeName}')

# 获取 NFS 路径（以 NFS 为例）
kubectl get pv $PV_NAME -o jsonpath='{.spec.nfs.server}:{.spec.nfs.path}'
# 输出示例: 10.0.0.100:/exports/pvc-xxxx-yyyy
```

**步骤 3**: 为消费者命名空间创建只读 PV 和 PVC

```yaml
# geoip-consumer-pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: geoip-readonly-pv
  labels:
    app: geoip-database
    access: readonly
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadOnlyMany
  persistentVolumeReclaimPolicy: Retain
  # NFS 示例 - 使用上一步获取的路径
  nfs:
    server: 10.0.0.100
    path: /exports/pvc-xxxx-yyyy
    readOnly: true
  # CephFS 示例
  # cephfs:
  #   monitors: ["10.0.0.1:6789"]
  #   path: /volumes/csi/pvc-xxxx-yyyy
  #   user: admin
  #   readOnly: true
  #   secretRef:
  #     name: ceph-secret
  #     namespace: geoip
---
# 消费者命名空间的 PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: geoip-data
  namespace: app-a  # 消费者命名空间
spec:
  accessModes:
    - ReadOnlyMany
  storageClassName: ""  # 必须为空字符串，使用静态绑定
  volumeName: geoip-readonly-pv  # 指定绑定的 PV
  resources:
    requests:
      storage: 1Gi
```

**步骤 4**: 在消费者 Pod 中挂载

```yaml
# 消费者 Deployment
spec:
  template:
    spec:
      volumes:
        - name: geoip
          persistentVolumeClaim:
            claimName: geoip-data
            readOnly: true
      containers:
        - name: app
          volumeMounts:
            - name: geoip
              mountPath: /usr/share/GeoIP
              readOnly: true
```

### 方案 2: 多个 PV 指向同一存储（多消费者）

如果有多个消费者命名空间，可以创建多个 PV-PVC 对：

```yaml
# 为每个消费者命名空间创建独立的 PV（都指向相同的底层路径）
{{- range $ns := list "app-a" "app-b" "app-c" }}
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: geoip-readonly-{{ $ns }}
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadOnlyMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    server: 10.0.0.100
    path: /exports/pvc-xxxx-yyyy  # 相同的底层路径
    readOnly: true
  claimRef:  # 预绑定到特定命名空间的 PVC
    name: geoip-data
    namespace: {{ $ns }}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: geoip-data
  namespace: {{ $ns }}
spec:
  accessModes:
    - ReadOnlyMany
  storageClassName: ""
  volumeName: geoip-readonly-{{ $ns }}
  resources:
    requests:
      storage: 1Gi
{{- end }}
```

### 方案 3: 直接使用 NFS Volume（无需 PVC）

如果底层是 NFS，消费者 Pod 可以直接挂载，无需创建 PVC：

```yaml
spec:
  template:
    spec:
      volumes:
        - name: geoip
          nfs:
            server: 10.0.0.100
            path: /exports/pvc-xxxx-yyyy
            readOnly: true
      containers:
        - name: app
          volumeMounts:
            - name: geoip
              mountPath: /usr/share/GeoIP
              readOnly: true
```

**优点**: 简单，无需创建额外的 PV/PVC
**缺点**: 需要 Pod 有权限挂载 NFS，配置分散在各个 Deployment 中

### 方案对比

| 方案 | 复杂度 | 适用场景 | 优点 | 缺点 |
|-----|-------|---------|------|------|
| 静态 PV 共享 | 中 | 通用 | 标准 K8s 方式，RBAC 清晰 | 需要手动创建 PV |
| 多 PV 预绑定 | 中 | 多消费者 | 隔离性好 | PV 数量多 |
| 直接 NFS Volume | 低 | NFS 环境 | 无需额外资源 | 配置分散，耦合存储细节 |

### 自动化脚本

提供一个脚本自动为新命名空间创建只读 PVC：

```bash
#!/bin/bash
# create-geoip-consumer-pvc.sh

CONSUMER_NS=$1
GEOIP_NS=${2:-geoip}
GEOIP_PVC=${3:-geoip-data}

if [ -z "$CONSUMER_NS" ]; then
  echo "Usage: $0 <consumer-namespace> [geoip-namespace] [geoip-pvc-name]"
  exit 1
fi

# 获取原始 PV 信息
PV_NAME=$(kubectl get pvc $GEOIP_PVC -n $GEOIP_NS -o jsonpath='{.spec.volumeName}')
NFS_SERVER=$(kubectl get pv $PV_NAME -o jsonpath='{.spec.nfs.server}')
NFS_PATH=$(kubectl get pv $PV_NAME -o jsonpath='{.spec.nfs.path}')

if [ -z "$NFS_SERVER" ]; then
  echo "Error: Could not get NFS server info from PV $PV_NAME"
  exit 1
fi

echo "Creating readonly PV and PVC for namespace: $CONSUMER_NS"
echo "NFS: $NFS_SERVER:$NFS_PATH"

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: geoip-readonly-${CONSUMER_NS}
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadOnlyMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    server: ${NFS_SERVER}
    path: ${NFS_PATH}
    readOnly: true
  claimRef:
    name: geoip-data
    namespace: ${CONSUMER_NS}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: geoip-data
  namespace: ${CONSUMER_NS}
spec:
  accessModes:
    - ReadOnlyMany
  storageClassName: ""
  volumeName: geoip-readonly-${CONSUMER_NS}
  resources:
    requests:
      storage: 1Gi
EOF

echo "Done! You can now mount 'geoip-data' PVC in namespace '$CONSUMER_NS'"
```

使用方法：

```bash
# 为 app-a 命名空间创建只读 PVC
./create-geoip-consumer-pvc.sh app-a

# 指定 geoip-database 所在的命名空间
./create-geoip-consumer-pvc.sh app-b infra
```

### 消费端自动滚动更新

消费端可以部署 CronJob 检测 GeoIP 数据库变化，自动触发 Deployment 滚动更新。

#### 方案 1: 基于文件修改时间

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: geoip-rollout-trigger
  namespace: app-a
spec:
  schedule: "*/30 * * * *"  # 每 30 分钟检查一次
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      ttlSecondsAfterFinished: 3600
      template:
        spec:
          serviceAccountName: geoip-rollout-trigger
          restartPolicy: OnFailure
          volumes:
            - name: geoip
              persistentVolumeClaim:
                claimName: geoip-data
                readOnly: true
          containers:
            - name: check-and-rollout
              image: bitnami/kubectl:1.31
              volumeMounts:
                - name: geoip
                  mountPath: /usr/share/GeoIP
                  readOnly: true
              env:
                - name: DEPLOYMENT_NAME
                  value: "my-app"  # 需要滚动更新的 Deployment
                - name: NAMESPACE
                  valueFrom:
                    fieldRef:
                      fieldPath: metadata.namespace
              command:
                - /bin/bash
                - -c
                - |
                  set -e
                  
                  # 获取最新的 mmdb 文件修改时间
                  LATEST_MTIME=$(find /usr/share/GeoIP -name "*.mmdb" -type f -exec stat -c %Y {} \; | sort -rn | head -1)
                  
                  if [ -z "$LATEST_MTIME" ]; then
                    echo "No .mmdb files found"
                    exit 0
                  fi
                  
                  # 获取 Deployment 当前的 geoip-mtime 注解
                  CURRENT_MTIME=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" \
                    -o jsonpath='{.spec.template.metadata.annotations.geoip-mtime}' 2>/dev/null || echo "")
                  
                  echo "Latest mtime: $LATEST_MTIME, Current annotation: $CURRENT_MTIME"
                  
                  if [ "$LATEST_MTIME" != "$CURRENT_MTIME" ]; then
                    echo "GeoIP database updated, triggering rollout..."
                    kubectl patch deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" \
                      -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"geoip-mtime\":\"$LATEST_MTIME\"}}}}}"
                    echo "Rollout triggered successfully"
                  else
                    echo "No update needed"
                  fi
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: geoip-rollout-trigger
  namespace: app-a
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: geoip-rollout-trigger
  namespace: app-a
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: geoip-rollout-trigger
  namespace: app-a
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: geoip-rollout-trigger
subjects:
  - kind: ServiceAccount
    name: geoip-rollout-trigger
    namespace: app-a
```

#### 方案 2: 基于文件 Hash 值

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: geoip-rollout-trigger
  namespace: app-a
spec:
  schedule: "*/30 * * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      ttlSecondsAfterFinished: 3600
      template:
        spec:
          serviceAccountName: geoip-rollout-trigger
          restartPolicy: OnFailure
          volumes:
            - name: geoip
              persistentVolumeClaim:
                claimName: geoip-data
                readOnly: true
          containers:
            - name: check-and-rollout
              image: bitnami/kubectl:1.31
              volumeMounts:
                - name: geoip
                  mountPath: /usr/share/GeoIP
                  readOnly: true
              env:
                - name: DEPLOYMENT_NAME
                  value: "my-app"
                - name: NAMESPACE
                  valueFrom:
                    fieldRef:
                      fieldPath: metadata.namespace
              command:
                - /bin/bash
                - -c
                - |
                  set -e
                  
                  # 计算所有 mmdb 文件的组合 hash
                  HASH=$(find /usr/share/GeoIP -name "*.mmdb" -type f -exec sha256sum {} \; \
                    | sort | sha256sum | cut -d' ' -f1 | head -c 16)
                  
                  if [ -z "$HASH" ]; then
                    echo "No .mmdb files found"
                    exit 0
                  fi
                  
                  # 获取 Deployment 当前的 hash 注解
                  CURRENT_HASH=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" \
                    -o jsonpath='{.spec.template.metadata.annotations.geoip-hash}' 2>/dev/null || echo "")
                  
                  echo "Current hash: $HASH, Stored hash: $CURRENT_HASH"
                  
                  if [ "$HASH" != "$CURRENT_HASH" ]; then
                    echo "GeoIP database updated, triggering rollout..."
                    kubectl patch deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" \
                      -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"geoip-hash\":\"$HASH\"}}}}}"
                    echo "Rollout triggered successfully"
                  else
                    echo "No update needed"
                  fi
```

#### 方案 3: 读取 geoip-database 的 Hash ConfigMap（跨命名空间）

如果允许跨命名空间读取 ConfigMap，可以直接使用 `geoip-database` 生成的 hash：

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: geoip-rollout-trigger
  namespace: app-a
spec:
  schedule: "*/30 * * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      ttlSecondsAfterFinished: 3600
      template:
        spec:
          serviceAccountName: geoip-rollout-trigger
          restartPolicy: OnFailure
          containers:
            - name: check-and-rollout
              image: bitnami/kubectl:1.31
              env:
                - name: DEPLOYMENT_NAME
                  value: "my-app"
                - name: NAMESPACE
                  valueFrom:
                    fieldRef:
                      fieldPath: metadata.namespace
                - name: GEOIP_NAMESPACE
                  value: "geoip"
                - name: GEOIP_CONFIGMAP
                  value: "geoip-hash"
              command:
                - /bin/bash
                - -c
                - |
                  set -e
                  
                  # 从 geoip-database 的 ConfigMap 获取 hash
                  HASH=$(kubectl get configmap "$GEOIP_CONFIGMAP" -n "$GEOIP_NAMESPACE" \
                    -o jsonpath='{.data.hash}' 2>/dev/null || echo "")
                  
                  if [ -z "$HASH" ] || [ "$HASH" = "initial" ]; then
                    echo "Hash not available yet"
                    exit 0
                  fi
                  
                  # 获取 Deployment 当前的 hash 注解
                  CURRENT_HASH=$(kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" \
                    -o jsonpath='{.spec.template.metadata.annotations.geoip-hash}' 2>/dev/null || echo "")
                  
                  echo "Source hash: $HASH, Current hash: $CURRENT_HASH"
                  
                  if [ "$HASH" != "$CURRENT_HASH" ]; then
                    echo "GeoIP database updated, triggering rollout..."
                    kubectl patch deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" \
                      -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"geoip-hash\":\"$HASH\"}}}}}"
                    echo "Rollout triggered successfully"
                  else
                    echo "No update needed"
                  fi
---
# 需要跨命名空间读取 ConfigMap 的 ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: geoip-configmap-reader
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["geoip-hash"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: geoip-configmap-reader-app-a
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: geoip-configmap-reader
subjects:
  - kind: ServiceAccount
    name: geoip-rollout-trigger
    namespace: app-a
```

#### 方案对比

| 方案 | 优点 | 缺点 |
|-----|------|------|
| 文件修改时间 | 简单，无需计算 | 时间精度可能不够 |
| 文件 Hash | 准确检测内容变化 | 需要读取文件计算 hash |
| 读取 ConfigMap | 无需挂载 PVC | 需要跨命名空间 RBAC |

#### 多 Deployment 滚动更新

如果需要更新多个 Deployment，修改脚本支持列表：

```yaml
env:
  - name: DEPLOYMENTS
    value: "nginx,powerdns,app1,app2"  # 逗号分隔的 Deployment 列表
command:
  - /bin/bash
  - -c
  - |
    set -e
    HASH=$(find /usr/share/GeoIP -name "*.mmdb" -type f -exec sha256sum {} \; \
      | sort | sha256sum | cut -d' ' -f1 | head -c 16)
    
    for DEPLOY in ${DEPLOYMENTS//,/ }; do
      CURRENT=$(kubectl get deployment "$DEPLOY" -n "$NAMESPACE" \
        -o jsonpath='{.spec.template.metadata.annotations.geoip-hash}' 2>/dev/null || echo "")
      
      if [ "$HASH" != "$CURRENT" ]; then
        echo "Updating $DEPLOY..."
        kubectl patch deployment "$DEPLOY" -n "$NAMESPACE" \
          -p "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"geoip-hash\":\"$HASH\"}}}}}"
      fi
    done
```

## 在其他应用中使用

### 基本用法

在你的 Pod/Deployment 中添加：

```yaml
spec:
  template:
    spec:
      volumes:
        - name: geoip-data
          persistentVolumeClaim:
            claimName: geoip-data  # 默认 PVC 名称
      containers:
        - name: your-app
          volumeMounts:
            - name: geoip-data
              mountPath: /usr/share/GeoIP
              readOnly: true
```

### 配合 PowerDNS Auth 使用

```yaml
# powerdns-auth values.yaml
geoipVolume:
  enabled: true
  type: existingClaim
  existingClaim:
    claimName: geoip-data

geoipUpdate:
  enabled: false  # 禁用内置更新，使用 geoip-database chart
```

### 配合 nginx (ngx_http_geoip2_module) 使用

```yaml
# nginx deployment
spec:
  template:
    spec:
      volumes:
        - name: geoip
          persistentVolumeClaim:
            claimName: geoip-data
      containers:
        - name: nginx
          volumeMounts:
            - name: geoip
              mountPath: /usr/share/GeoIP
              readOnly: true
```

nginx.conf:
```nginx
geoip2 /usr/share/GeoIP/GeoLite2-Country.mmdb {
    auto_reload 60m;
    $geoip2_country_code country iso_code;
}
```

### 自动重载（数据库更新时）

#### 方法 1: 使用 Reloader

```yaml
metadata:
  annotations:
    configmap.reloader.stakater.com/reload: "geoip-hash"
```

#### 方法 2: 使用 ConfigMap Hash 注解

```yaml
spec:
  template:
    metadata:
      annotations:
        checksum/geoip: {{ index (lookup "v1" "ConfigMap" .Release.Namespace "geoip-hash").data "hash" }}
```

## 配置参数

### 数据源配置

| 参数 | 描述 | 默认值 |
|-----|------|-------|
| `source.type` | 数据源类型: "maxmind" 或 "github" | `maxmind` |
| `source.maxmind.accountId` | MaxMind 账号 ID | `""` |
| `source.maxmind.licenseKey` | MaxMind 许可证密钥 | `""` |
| `source.github.owner` | GitHub 仓库所有者 | `""` |
| `source.github.repo` | GitHub 仓库名称 | `geoip-update-relay` |
| `source.github.token` | GitHub Token（私有仓库需要） | `""` |

### 存储配置

| 参数 | 描述 | 默认值 |
|-----|------|-------|
| `storage.storageClass` | StorageClass 名称（需支持 RWX） | `""` |
| `storage.size` | PVC 大小 | `1Gi` |
| `storage.existingClaim` | 使用已存在的 PVC | `""` |

### 数据库配置

| 参数 | 描述 | 默认值 |
|-----|------|-------|
| `databases.editionIds` | 要下载的数据库版本 | `[GeoLite2-City, GeoLite2-Country, GeoLite2-ASN]` |
| `databases.directory` | 数据库存储目录 | `/usr/share/GeoIP` |

### 更新任务配置

| 参数 | 描述 | 默认值 |
|-----|------|-------|
| `update.enabled` | 启用自动更新 | `true` |
| `update.schedule` | CronJob 调度表达式 | `0 3 * * *` |
| `update.runOnInstall` | 安装时运行初始化 Job | `true` |
| `update.image.repository` | 更新镜像仓库 | `maxmind/geoipupdate` |
| `update.image.tag` | 更新镜像标签 | `v7.1` |

## 架构

```
┌─────────────────────────────────────────────────────────────────┐
│                        geoip-database                           │
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   CronJob    │───▶│     PVC      │◀───│  ConfigMap   │      │
│  │  (Updater)   │    │    (RWX)     │    │   (Hash)     │      │
│  └──────────────┘    └──────┬───────┘    └──────────────┘      │
│                             │                                   │
└─────────────────────────────┼───────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
          ▼                   ▼                   ▼
    ┌──────────┐        ┌──────────┐        ┌──────────┐
    │ PowerDNS │        │  nginx   │        │ Your App │
    │   Auth   │        │ (geoip2) │        │          │
    └──────────┘        └──────────┘        └──────────┘
```

## 许可证

MIT License
