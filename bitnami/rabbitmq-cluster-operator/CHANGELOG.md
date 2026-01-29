# RabbitMQ Operator Helm Chart

基于 Bitnami Chart，使用 RabbitMQ 官方镜像。

## 与 Bitnami 原版的区别

仅修改了镜像源，其他配置完全保留：

| 组件 | Bitnami 镜像 | 官方镜像 |
|------|-------------|---------|
| Cluster Operator | `bitnami/rabbitmq-cluster-operator` | `rabbitmqoperator/cluster-operator:2.19.0` |
| Topology Operator | `bitnami/rmq-messaging-topology-operator` | `rabbitmqoperator/messaging-topology-operator:1.18.2` |
| RabbitMQ | `bitnami/rabbitmq` | `rabbitmq:4.1.3-management` |
| Credential Updater | `bitnami/rmq-default-credential-updater` | `rabbitmqoperator/default-user-credential-updater:1.0.8` |

## 安装

```bash
# 安装 cert-manager（如果尚未安装）
kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.14.0/cert-manager.yaml

# 更新依赖
helm dependency update

# 部署
helm upgrade --install rabbitmq-operator . \
  -n kube-operator --create-namespace \
  --set useCertManager=true
```

## 配置

所有 Bitnami 原版配置项均可使用，参考：
- [Bitnami RabbitMQ Cluster Operator Chart](https://github.com/bitnami/charts/tree/main/bitnami/rabbitmq-cluster-operator)

### 常用配置示例

```yaml
# 副本数
clusterOperator:
  replicaCount: 2
msgTopologyOperator:
  replicaCount: 2

# 仅监控指定命名空间
clusterOperator:
  watchAllNamespaces: false
  watchNamespaces:
    - production
    - staging

# 私有镜像仓库
global:
  imageRegistry: my-registry.example.com
  imagePullSecrets:
    - my-secret
```
