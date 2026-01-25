# Ceph Consumer Helm Chart

A Helm chart for connecting Kubernetes clusters to an external Rook-Ceph storage cluster.

## Overview

This chart deploys a sync controller that automatically:
- Synchronizes Mon endpoints and FSID from the provider cluster
- Copies CSI user secrets (credentials for RBD/CephFS access)
- Synchronizes StorageClasses (direct copy, only namespace references replaced)
- Monitors for changes and keeps consumer cluster in sync

## Architecture

```
Provider Cluster                    Consumer Cluster
┌─────────────────┐                ┌─────────────────┐
│ rook-ceph-mon   │                │ rook-ceph-mon   │
│   endpoints     │ ───(sync)────▶ │   endpoints     │
│   ConfigMap     │                │   ConfigMap     │
├─────────────────┤                ├─────────────────┤
│ rook-ceph-mon   │                │ rook-ceph-mon   │
│   Secret (FSID) │ ───(sync)────▶ │   Secret        │
├─────────────────┤                ├─────────────────┤
│ rook-csi-*      │                │ rook-csi-*      │
│   Secrets       │ ───(copy)────▶ │   Secrets       │
├─────────────────┤                ├─────────────────┤
│ StorageClass    │  (copy+replace │ StorageClass    │
│ (all params)    │ ──namespace)─▶ │ (same params)   │
└─────────────────┘                └─────────────────┘
```

## Prerequisites

- Kubernetes 1.25+
- Helm 3.0+
- A running Rook-Ceph cluster (provider cluster)
- Network connectivity between consumer and provider clusters
- Kubeconfig with **read-only** access to the provider cluster

## Installation

### Step 1: Setup Provider Cluster RBAC (Read-Only)

On the **provider** cluster, apply the RBAC configuration:

```bash
kubectl apply -f examples/provider-rbac.yaml
```

This creates:
- `ServiceAccount`: `ceph-consumer-reader` in `rook-ceph` namespace
- `Role`: Read-only access to specific Secrets and ConfigMaps
- `ClusterRole`: Read-only access to StorageClasses

<details>
<summary>View provider-rbac.yaml content</summary>

```yaml
# ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ceph-consumer-reader
  namespace: rook-ceph
---
# Role for namespace-scoped resources (read-only)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ceph-consumer-reader
  namespace: rook-ceph
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: ["rook-ceph-mon-endpoints"]
    verbs: ["get"]
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames:
      - rook-ceph-mon
      - rook-csi-rbd-node
      - rook-csi-rbd-provisioner
      - rook-csi-cephfs-node
      - rook-csi-cephfs-provisioner
    verbs: ["get"]
---
# ClusterRole for StorageClasses (read-only)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ceph-consumer-reader-storageclasses
rules:
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list"]
```

</details>

### Step 2: Generate Provider Kubeconfig

On the **provider** cluster:

```bash
# Generate kubeconfig with 1-year token
./examples/generate-provider-kubeconfig.sh provider-kubeconfig.yaml

# Or manually:
kubectl create token ceph-consumer-reader -n rook-ceph --duration=8760h
```

### Step 3: Install the Chart

On the **consumer** cluster:

```bash
# Create namespace
kubectl create namespace rook-ceph

# Install with kubeconfig from file
helm install ceph-consumer ./ceph-consumer \
  --namespace rook-ceph \
  --set-file provider.kubeconfig=provider-kubeconfig.yaml

# Or using an existing secret
kubectl create secret generic provider-kubeconfig \
  --from-file=config=provider-kubeconfig.yaml \
  -n rook-ceph

helm install ceph-consumer ./ceph-consumer \
  --namespace rook-ceph \
  --set provider.kubeconfigSecret=provider-kubeconfig
```

## Configuration

### Provider Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `provider.kubeconfig` | Kubeconfig content for provider cluster | `""` |
| `provider.kubeconfigSecret` | Existing secret name with kubeconfig | `""` |
| `provider.kubeconfigSecretKey` | Key in the secret | `"config"` |
| `provider.namespace` | Rook-Ceph namespace in provider | `"rook-ceph"` |

### Consumer Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `consumer.namespace` | Namespace for Ceph resources | `"rook-ceph"` |
| `consumer.clusterName` | Name for CephCluster CR | `"rook-ceph-external"` |

### Controller Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `controller.enabled` | Enable sync controller | `true` |
| `controller.schedule` | CronJob schedule | `"* * * * *"` |
| `controller.image.registry` | Image registry | `ghcr.io` |
| `controller.image.repository` | Image repository | `rook/ceph-consumer-controller` |
| `controller.image.tag` | Image tag | `v0.1.0` |

### StorageClass Sync Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `storageClassSync.enabled` | Enable StorageClass sync | `true` |
| `storageClassSync.defaultStorageClass` | Override default SC (empty=preserve) | `""` |
| `storageClassSync.rbd.enabled` | Enable RBD sync | `true` |
| `storageClassSync.cephfs.enabled` | Enable CephFS sync | `true` |
| `storageClassSync.filter.excludePatterns` | Regex patterns to exclude | `[]` |
| `storageClassSync.filter.includePatterns` | Regex patterns to include | `[]` |

## How It Works

### StorageClass Synchronization

StorageClasses are **directly copied** from the provider cluster. The sync controller only replaces namespace-specific references:

| Field | Transformation |
|-------|---------------|
| `provisioner` | `rook-ceph.rbd.csi.ceph.com` → `{consumer-ns}.rbd.csi.ceph.com` |
| `parameters.clusterID` | `rook-ceph` → `{consumer-ns}` |
| `parameters.*-secret-namespace` | `rook-ceph` → `{consumer-ns}` |
| **All other fields** | **Preserved exactly** (pool, imageFormat, imageFeatures, reclaimPolicy, mountOptions, etc.) |

### Managed Resources

All resources created by the controller are labeled with:
```yaml
labels:
  ceph-consumer.rook.io/managed: "true"
```

The controller will clean up orphaned resources that no longer exist in the provider.

## Troubleshooting

### Check Controller Logs

```bash
# Find the latest job
kubectl get jobs -n rook-ceph --sort-by=.metadata.creationTimestamp

# View logs
kubectl logs -n rook-ceph job/<job-name>

# Enable debug logging
helm upgrade ceph-consumer ./ceph-consumer \
  --namespace rook-ceph \
  --set logging.level=DEBUG
```

### Manual Sync

```bash
kubectl create job --from=cronjob/ceph-consumer ceph-consumer-manual -n rook-ceph
```

### Verify Sync Status

```bash
# Check Mon endpoints
kubectl get configmap rook-ceph-mon-endpoints -n rook-ceph -o yaml

# Check CSI secrets
kubectl get secrets -n rook-ceph -l ceph-consumer.rook.io/managed=true

# Check StorageClasses
kubectl get storageclasses -l ceph-consumer.rook.io/managed=true
```

## Building the Controller Image

```bash
docker build -t ghcr.io/rook/ceph-consumer-controller:v0.1.0 .
docker push ghcr.io/rook/ceph-consumer-controller:v0.1.0
```

Image size: ~60MB (Alpine + Python + kubectl)

## License

Apache License 2.0 - See [LICENSE](LICENSE) for details.
