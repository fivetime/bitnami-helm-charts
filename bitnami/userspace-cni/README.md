<!--- app-name: Userspace CNI -->

# Userspace CNI packaged by Bitnami

Userspace CNI is a Kubernetes CNI plugin that provisions high-performance userspace dataplane interfaces (memif / vhost-user) on host-side OVS-DPDK or VPP switches for DPDK-based workloads. This chart ships the single CNI binary via a DaemonSet that installs it into each node's CNI binary directory.

[Overview of Userspace CNI](https://github.com/fivetime/userspace-cni)

## TL;DR

```console
helm install my-release oci://REGISTRY_NAME/REPOSITORY_NAME/userspace-cni
```

> Note: You need to substitute the placeholders `REGISTRY_NAME` and `REPOSITORY_NAME` with a reference to your Helm chart registry and repository.

## Introduction

This chart bootstraps a [Userspace CNI](https://github.com/fivetime/userspace-cni) DaemonSet on a [Kubernetes](https://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

Unlike kernel-network CNIs, Userspace CNI does not run a control-plane daemon and does not manipulate host network namespaces from a running container. Each Pod simply copies the `userspace` CNI binary onto the host (`/opt/cni/bin`) with an init container and then idles. The node runtime (kubelet) invokes the binary per-Pod; the binary talks to the local OVS-DPDK (`ovsdb-server`) or VPP instance to create the memif / vhost-user socket.

Bitnami charts consistently use the [Bitnami common chart](https://github.com/bitnami/charts/tree/main/bitnami/common) for shared templating (image, labels, affinities, network policy, etc.).

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8.0+
- A userspace switch (OVS-DPDK or VPP) installed and running on every target node. This chart does NOT deploy or manage OVS/VPP.
- [Multus CNI](https://github.com/k8snetworkplumbingwg/multus-cni) (or another meta-plugin) to invoke the `userspace` binary as a secondary network attachment. Userspace CNI is not a primary cluster CNI.

## Installing the Chart

To install the chart with the release name `my-release`:

```console
helm install my-release oci://REGISTRY_NAME/REPOSITORY_NAME/userspace-cni
```

These commands deploy Userspace CNI on the Kubernetes cluster in the default configuration. The [Parameters](#parameters) section lists the parameters that can be configured during installation.

> **Tip**: List all releases using `helm list`

## Uninstalling the Chart

To uninstall/delete the `my-release` deployment:

```console
helm uninstall my-release
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

> Note: uninstalling the chart removes the DaemonSet but does NOT remove the `userspace` binary that was copied to `/opt/cni/bin` on each node. Remove it manually if required.

## Parameters

### Global parameters

| Name                                                  | Description                                                                                                                                                                                                                                                                                                                                                                  | Value  |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| `global.imageRegistry`                                | Global Docker image registry                                                                                                                                                                                                                                                                                                                                                | `""`   |
| `global.imagePullSecrets`                             | Global Docker registry secret names as an array                                                                                                                                                                                                                                                                                                                            | `[]`   |
| `global.defaultStorageClass`                          | Global default StorageClass for Persistent Volume(s)                                                                                                                                                                                                                                                                                                                        | `""`   |
| `global.storageClass`                                 | DEPRECATED: use global.defaultStorageClass instead                                                                                                                                                                                                                                                                                                                          | `""`   |
| `global.compatibility.openshift.adaptSecurityContext` | Adapt the securityContext sections of the deployment to make them compatible with Openshift restricted-v2 SCC: remove runAsUser, runAsGroup and fsGroup and let the platform use their allowed default IDs. Possible values: auto (apply if the detected running cluster is Openshift), force (perform the adaptation always), disabled (do not perform adaptation) | `auto` |

### Common parameters

| Name                     | Description                                                                                          | Value   |
| ------------------------ | --------------------------------------------------------------------------------------------------- | ------- |
| `kubeVersion`            | Force target Kubernetes version (using Helm capabilities if not set)                                 | `""`    |
| `nameOverride`           | String to partially override userspace-cni.fullname template (will maintain the release name)        | `""`    |
| `fullnameOverride`       | String to fully override userspace-cni.fullname template                                             | `""`    |
| `namespaceOverride`      | String to fully override common.names.namespace                                                      | `""`    |
| `commonAnnotations`      | Common annotations to add to all userspace-cni resources (sub-charts are not considered). Evaluated as a template | `{}`    |
| `commonLabels`           | Common labels to add to all userspace-cni resources (sub-charts are not considered). Evaluated as a template | `{}`    |
| `extraDeploy`            | Array of extra objects to deploy with the release (evaluated as a template).                         | `[]`    |
| `diagnosticMode.enabled` | Enable diagnostic mode (the command will be overridden)                                              | `false` |
| `diagnosticMode.command` | Command to override all containers in the deployment                                                 | `["sleep"]` |
| `diagnosticMode.args`    | Args to override all containers in the deployment                                                    | `["infinity"]` |

### userspace-cni parameters

| Name                              | Description                                                                                            | Value                     |
| --------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------- |
| `image.registry`                  | userspace-cni image registry                                                                          | `ghcr.io`                 |
| `image.repository`                | userspace-cni Image name                                                                              | `fivetime/userspace-cni`  |
| `image.digest`                    | userspace-cni image digest in the way sha256:aa.... Please note this parameter, if set, will override the tag | `""`            |
| `image.pullPolicy`                | userspace-cni image pull policy                                                                       | `IfNotPresent`            |
| `image.pullSecrets`               | Specify docker-registry secret names as an array                                                     | `[]`                      |
| `hostCNIBinDir`                   | CNI binary dir in the host machine                                                                    | `/opt/cni/bin`            |
| `CNIMountPath`                    | Path inside the container to mount the host CNI bin dir under                                         | `/host`                   |
| `updateStrategy.type`             | userspace-cni DaemonSet update strategy                                                               | `RollingUpdate`           |
| `priorityClassName`               | userspace-cni pods' priorityClassName                                                                 | `system-node-critical`    |
| `schedulerName`                   | Name of the k8s scheduler (other than default)                                                        | `""`                      |
| `topologySpreadConstraints`       | Topology Spread Constraints for pod assignment                                                        | `[]`                      |
| `automountServiceAccountToken`    | Mount Service Account token in pod                                                                    | `false`                   |
| `hostAliases`                     | Add deployment host aliases                                                                           | `[]`                      |
| `command`                         | Override default steady-state container command (useful when using custom images)                    | `[]`                      |
| `args`                            | Override default steady-state container args (useful when using custom images)                       | `[]`                      |
| `extraEnvVars`                    | Extra environment variables to add to the steady-state container                                     | `[]`                      |
| `extraEnvVarsCM`                  | ConfigMap containing extra env vars                                                                   | `""`                      |
| `extraEnvVarsSecret`              | Secret containing extra env vars (in case of sensitive data)                                          | `""`                      |
| `extraVolumes`                    | Array of extra volumes to be added to the deployment (evaluated as template). Requires setting `extraVolumeMounts` | `[]`         |
| `extraVolumeMounts`               | Array of extra volume mounts to be added to the container (evaluated as template).                   | `[]`                      |
| `initContainers`                  | Add additional init containers to the pod (evaluated as a template)                                  | `[]`                      |
| `sidecars`                        | Attach additional containers to the pod (evaluated as a template)                                    | `[]`                      |
| `tolerations`                     | Tolerations for pod assignment                                                                       | `[Exists/NoSchedule, Exists/NoExecute]` |
| `podAffinityPreset`               | Pod affinity preset. Ignored if `affinity` is set. Allowed values: `soft` or `hard`                  | `""`                      |
| `podAntiAffinityPreset`           | Pod anti-affinity preset. Ignored if `affinity` is set. Allowed values: `soft` or `hard`             | `soft`                    |
| `nodeAffinityPreset.type`         | Node affinity preset type. Ignored if `affinity` is set. Allowed values: `soft` or `hard`            | `""`                      |
| `nodeAffinityPreset.key`          | Node label key to match Ignored if `affinity` is set.                                                | `""`                      |
| `nodeAffinityPreset.values`       | Node label values to match. Ignored if `affinity` is set.                                            | `[]`                      |
| `affinity`                        | Affinity for pod assignment                                                                          | `{}`                      |
| `nodeSelector`                    | Node labels for pod assignment. Evaluated as a template.                                             | `{kubernetes.io/os: linux}` |
| `resourcesPreset`                 | Set container resources according to one common preset (allowed values: none, nano, micro, small, medium, large, xlarge, 2xlarge). Ignored if `resources` is set. | `nano` |
| `resources`                       | Set container requests and limits for different resources like CPU or memory (essential for production workloads) | `{}`         |
| `podSecurityContext.enabled`      | Enable userspace-cni pods' Security Context                                                           | `true`                    |
| `podSecurityContext.fsGroupChangePolicy` | Set filesystem group change policy                                                             | `Always`                  |
| `podSecurityContext.sysctls`      | Set kernel settings using the sysctl interface                                                       | `[]`                      |
| `podSecurityContext.supplementalGroups` | Set filesystem extra groups                                                                    | `[]`                      |
| `podSecurityContext.fsGroup`      | userspace-cni pods' group ID                                                                         | `0`                       |
| `containerSecurityContext.enabled`               | Enable userspace-cni containers' Security Context                                      | `true`                    |
| `containerSecurityContext.seLinuxOptions`        | Set SELinux options in container                                                      | `{}`                      |
| `containerSecurityContext.runAsUser`             | userspace-cni containers' Security Context                                             | `0`                       |
| `containerSecurityContext.runAsGroup`            | userspace-cni containers' Security Context                                             | `0`                       |
| `containerSecurityContext.runAsNonRoot`          | Set userspace-cni container's Security Context runAsNonRoot                            | `false`                   |
| `containerSecurityContext.privileged`            | Set userspace-cni container's Security Context privileged                              | `false`                   |
| `containerSecurityContext.allowPrivilegeEscalation` | Set container's Security Context allowPrivilegeEscalation                           | `false`                   |
| `containerSecurityContext.readOnlyRootFilesystem` | Set container's Security Context readOnlyRootFilesystem                               | `true`                    |
| `containerSecurityContext.capabilities.drop`     | List of capabilities to be dropped                                                    | `["ALL"]`                 |
| `containerSecurityContext.seccompProfile.type`   | Set container's Security Context seccomp profile                                       | `RuntimeDefault`          |
| `lifecycleHooks`                  | LifecycleHook to set additional configuration at startup. Evaluated as a template                    | `{}`                      |
| `podAnnotations`                  | Pod annotations                                                                                      | `{}`                      |
| `podLabels`                       | Add additional labels to the pod (evaluated as a template)                                           | `{}`                      |

### Network Policy parameters

| Name                                    | Description                                                                              | Value             |
| --------------------------------------- | ---------------------------------------------------------------------------------------- | ----------------- |
| `networkPolicy.enabled`                 | Specifies whether a NetworkPolicy should be created                                       | `true`            |
| `networkPolicy.kubeAPIServerPorts`      | List of possible endpoints to kube-apiserver                                              | `[443,6443,8443]` |
| `networkPolicy.allowExternal`           | Don't require server label for connections                                               | `true`            |
| `networkPolicy.allowExternalEgress`     | Allow the pod to access any range of port and all destinations.                          | `true`            |
| `networkPolicy.extraIngress`            | Add extra ingress rules to the NetworkPolicy                                              | `[]`              |
| `networkPolicy.extraEgress`             | Add extra egress rules to the NetworkPolicy                                               | `[]`              |
| `networkPolicy.ingressNSMatchLabels`    | Labels to match to allow traffic from other namespaces                                    | `{}`              |
| `networkPolicy.ingressNSPodMatchLabels` | Pod labels to match to allow traffic from other namespaces                                | `{}`              |

### Other Parameters

| Name                                          | Description                                                       | Value   |
| --------------------------------------------- | ----------------------------------------------------------------- | ------- |
| `serviceAccount.create`                       | Enable creation of ServiceAccount for userspace-cni pod           | `true`  |
| `serviceAccount.name`                         | The name of the ServiceAccount to use.                            | `""`    |
| `serviceAccount.automountServiceAccountToken` | Allows auto mount of ServiceAccountToken on the serviceAccount created | `false` |
| `serviceAccount.annotations`                  | Additional custom annotations for the ServiceAccount              | `{}`    |

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

```console
helm install my-release \
  --set image.tag=main \
  oci://REGISTRY_NAME/REPOSITORY_NAME/userspace-cni
```

Alternatively, a YAML file that specifies the values for the parameters can be provided while installing the chart. For example,

```console
helm install my-release -f values.yaml oci://REGISTRY_NAME/REPOSITORY_NAME/userspace-cni
```

> **Tip**: You can use the default [values.yaml](https://github.com/bitnami/charts/tree/main/bitnami/userspace-cni/values.yaml)

## Configuration and installation details

### Image

The default image is `ghcr.io/fivetime/userspace-cni:main`. The `main` tag is a rolling tag (HEAD of `main`); the fork also publishes per-commit `<8-char-sha>` tags. For reproducible production deployments, pin a sha tag or set `image.digest`:

```console
helm install my-release \
  --set image.digest=sha256:... \
  oci://REGISTRY_NAME/REPOSITORY_NAME/userspace-cni
```

### Security context

Userspace CNI does not need a privileged container — it only copies a binary onto the host CNI directory and then idles. It therefore runs with `privileged: false`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true` and all Linux capabilities dropped. It runs as root (`runAsUser: 0`) only so the init container can write to `/opt/cni/bin`.

### Using the CNI from a Pod

After the chart is deployed and the binary is installed, define a `NetworkAttachmentDefinition` that references this CNI (`"type": "userspace"`) and attach it to Pods via the `k8s.v1.cni.cncf.io/networks` annotation. See the upstream examples, including OVS-DPDK / VPP memif & vhost-user, VLAN/MTU tuning, and OVN `OvnPort` binding: <https://github.com/fivetime/userspace-cni/tree/main/examples>.

### Setting Pod's affinity

This chart allows you to set your custom affinity using the `affinity` parameter. Find more information about Pod's affinity in the [Kubernetes documentation](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/#affinity-and-anti-affinity).

As an alternative, use one of the preset configurations for pod affinity, pod anti-affinity, and node affinity available at the [bitnami/common](https://github.com/bitnami/charts/tree/main/bitnami/common#affinities) chart. To do so, set the `podAffinityPreset`, `podAntiAffinityPreset`, or `nodeAffinityPreset` parameters.

## License

Copyright &copy; Broadcom, Inc. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

<http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
