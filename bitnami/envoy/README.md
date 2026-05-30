<!--- app-name: Envoy -->

# Envoy (data plane) Helm chart

Envoy is a high-performance L7 proxy and communication bus. This chart deploys a **bare Envoy data plane** whose dynamic configuration (LDS/CDS/RDS/EDS/SDS) is served by an **external xDS control plane** over gRPC ADS — for example a [`java-control-plane`](https://github.com/envoyproxy/java-control-plane) based control plane. It is built on the Bitnami `common` library following Bitnami chart conventions, but uses the **official upstream `envoyproxy/envoy`** image.

[Overview of Envoy](https://www.envoyproxy.io)

> **This is not Envoy Gateway.** There is no bundled control plane and no Kubernetes Gateway API. Envoy connects out to the control plane you point it at and applies whatever xDS that control plane pushes.

Trademarks: This software listing was originally packaged by Bitnami. The respective trademarks mentioned in the offering are owned by the respective companies, and use of them does not imply any affiliation or endorsement.

## TL;DR

```console
helm dependency build ./bitnami/envoy
helm install my-envoy ./bitnami/envoy \
  --set controlPlane.host=xds-control-plane.my-ns.svc.cluster.local \
  --set controlPlane.port=18000
```

## Introduction

This chart bootstraps an [Envoy](https://www.envoyproxy.io) data-plane deployment on a [Kubernetes](https://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager. The Envoy pods start from a generated **bootstrap** config and then receive all listeners, routes, clusters and secrets dynamically from your external xDS control plane.

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8.0+
- An external xDS control plane reachable over gRPC ADS (this chart does **not** ship one)

## Installing the Chart

To install the chart with the release name `my-envoy`:

```console
helm dependency build ./bitnami/envoy
helm install my-envoy ./bitnami/envoy \
  --set controlPlane.host=xds-control-plane.my-ns.svc.cluster.local \
  --set controlPlane.port=18000
```

The command deploys Envoy on the Kubernetes cluster in the default configuration. The [Parameters](#parameters) section lists the parameters that can be configured during installation.

> **Tip**: List all releases using `helm list`

## How it works

The chart renders an Envoy **bootstrap** (a ConfigMap, key `envoy.yaml`) containing:

- `admin` (bound to `127.0.0.1` unless `exposeAdmin=true`);
- `node` (`id`/`cluster`, defaults derived from the release; per-pod `--service-node $(POD_NAME)` is also set);
- `dynamic_resources.ads_config` → gRPC ADS to a static `xds_cluster` (HTTP/2), plus `cds_config`/`lds_config` via ADS;
- `static_resources.clusters[xds_cluster]` → `controlPlane.host:controlPlane.port`.

Everything else (listeners, routes, clusters, secrets) comes from your control plane at runtime.

## Configuration and installation details

### Ports

Because listeners are delivered dynamically via LDS, the container/Service ports must match the ports your control plane's listeners bind. The default exposes one listener on `containerPorts.http` (10000) mapped to `service.ports.http` (80). For an HTTPS listener add an entry to `extraContainerPorts` and `service.extraPorts`.

To bind privileged ports (80/443) directly inside the pod, add the capability:

```yaml
containerSecurityContext:
  capabilities:
    add: ["NET_BIND_SERVICE"]
```

### Custom bootstrap

The generated bootstrap covers the common ADS case. Two escape hatches are provided:

- `overrideConfiguration` — an object that is **deep-merged on top of** the generated bootstrap (add static listeners, tracing, stats sinks, …).
- `existingConfigMap` — point at your own full bootstrap (key `envoy.yaml`) to bypass the generated one entirely.

### Resource requests and limits

Bitnami charts allow setting resource requests and limits for all containers inside the chart deployment. These are inside the `resources` value (check parameter table). Setting requests is essential for production workloads and these should be adapted to your specific use case.

To make this process easier, the chart contains the `resourcesPreset` values, which automatically sets the `resources` section according to different presets. Check these presets in [the bitnami/common chart](https://github.com/bitnami/charts/blob/main/bitnami/common/templates/_resources.tpl#L15). However, in production workloads using `resourcesPreset` is discouraged as it may not fully adapt to your specific needs. Find more information on container resource management in the [official Kubernetes documentation](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/).

### Image

The `image` parameter allows specifying which image will be pulled for the chart. Recommended tags for v1.38.0:

- `distroless-v1.38.0` — standard extensions + distroless (slimmest, production) — **default**
- `v1.38.0` — standard extensions + Ubuntu base (has a shell)
- `contrib-distroless-v1.38.0` — all (contrib) extensions + distroless
- `contrib-v1.38.0` — all (contrib) extensions + Ubuntu base

#### Private registry

If you configure the `image` value to one in a private registry, you will need to [specify an image pull secret](https://kubernetes.io/docs/concepts/containers/images/#specifying-imagepullsecrets-on-a-pod).

1. Manually create image pull secret(s) in the namespace. See [this YAML example reference](https://kubernetes.io/docs/concepts/containers/images/#creating-a-secret-with-a-docker-config).
2. Note that the `imagePullSecrets` configuration value cannot currently be passed to helm using the `--set` parameter, so you must supply these using a `values.yaml` file, such as:

    ```yaml
    imagePullSecrets:
      - name: SECRET_NAME
    ```

3. Install the chart

### Setting Pod's affinity

This chart allows you to set your custom affinity using the `affinity` parameter. Find more information about Pod's affinity in the [kubernetes documentation](https://kubernetes.io/docs/concepts/configuration/assign-pod-node/#affinity-and-anti-affinity).

As an alternative, you can use the preset configurations for pod affinity, pod anti-affinity, and node affinity available at the [bitnami/common](https://github.com/bitnami/charts/tree/main/bitnami/common#affinities) chart. To do so, set the `podAffinityPreset`, `podAntiAffinityPreset`, or `nodeAffinityPreset` parameters.

### Verifying

```console
kubectl port-forward svc/my-envoy 9901:9901   # if exposeAdmin=true, else port-forward the pod
curl localhost:9901/ready
curl localhost:9901/config_dump   # what the control plane has pushed
```

## Parameters

### Global parameters

| Name                                                  | Description                                                                                                                                                                                                                                                                                                                                                             | Value  |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| `global.imageRegistry`                                | Global Docker image registry                                                                                                                                                                                                                                                                                                                                            | `""`   |
| `global.imagePullSecrets`                             | Global Docker registry secret names as an array                                                                                                                                                                                                                                                                                                                         | `[]`   |
| `global.defaultStorageClass`                          | Global default StorageClass for Persistent Volume(s)                                                                                                                                                                                                                                                                                                                    | `""`   |
| `global.compatibility.openshift.adaptSecurityContext` | Adapt the securityContext sections of the deployment to make them compatible with Openshift restricted-v2 SCC: remove runAsUser, runAsGroup and fsGroup and let the platform use their allowed default IDs. Possible values: auto (apply if the detected running cluster is Openshift), force (perform the adaptation always), disabled (do not perform adaptation) | `auto` |

### Common parameters

| Name                     | Description                                                                              | Value           |
| ------------------------ | --------------------------------------------------------------------------------------- | --------------- |
| `kubeVersion`            | Override Kubernetes version                                                              | `""`            |
| `nameOverride`           | String to partially override common.names.fullname                                      | `""`            |
| `fullnameOverride`       | String to fully override common.names.fullname                                          | `""`            |
| `namespaceOverride`      | String to fully override common.names.namespace                                         | `""`            |
| `commonLabels`           | Labels to add to all deployed objects                                                   | `{}`            |
| `commonAnnotations`      | Annotations to add to all deployed objects                                              | `{}`            |
| `clusterDomain`          | Kubernetes cluster domain name                                                          | `cluster.local` |
| `extraDeploy`            | Array of extra objects to deploy with the release                                       | `[]`            |
| `diagnosticMode.enabled` | Enable diagnostic mode (all probes will be disabled and the command will be overridden) | `false`         |
| `diagnosticMode.command` | Command to override all containers in the deployment                                     | `["sleep"]`     |
| `diagnosticMode.args`    | Args to override all containers in the deployment                                        | `["infinity"]`  |

### Envoy data-plane parameters

| Name                            | Description                                                                                                            | Value               |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------- | ------------------- |
| `image.registry`                | Envoy image registry                                                                                                 | `docker.io`         |
| `image.repository`              | Envoy image repository                                                                                               | `envoyproxy/envoy`  |
| `image.tag`                     | Envoy image tag                                                                                                      | `distroless-v1.38.0`|
| `image.digest`                  | Envoy image digest in the way sha256:aa.... Please note this parameter, if set, will override the tag                | `""`                |
| `image.pullPolicy`              | Envoy image pull policy                                                                                              | `IfNotPresent`      |
| `image.pullSecrets`             | Envoy image pull secrets                                                                                            | `[]`                |
| `image.debug`                   | Enable Envoy image debug mode                                                                                        | `false`             |
| `controlPlane.host`             | Hostname/Service of the xDS control plane gRPC endpoint (required)                                                   | `xds-control-plane` |
| `controlPlane.port`             | Port of the xDS control plane gRPC endpoint                                                                          | `18000`             |
| `controlPlane.apiType`          | ADS transport. One of GRPC (SOTW) or DELTA_GRPC (incremental, recommended)                                           | `DELTA_GRPC`        |
| `controlPlane.clusterType`      | DNS discovery type for the control plane cluster. STRICT_DNS or LOGICAL_DNS                                          | `STRICT_DNS`        |
| `controlPlane.connectTimeout`   | Connect timeout to the control plane cluster                                                                         | `5s`                |
| `controlPlane.keepalive.interval` | HTTP/2 keepalive ping interval to the control plane                                                                | `30s`               |
| `controlPlane.keepalive.timeout`  | HTTP/2 keepalive timeout before the connection is considered dead                                                  | `5s`                |
| `controlPlane.tcpKeepalive`     | Also enable L4 TCP keepalive on the xDS connection (redundant when HTTP/2 keepalive is enabled)                      | `false`             |
| `node.id`                       | Envoy node id. Defaults to the release fullname when empty                                                           | `""`                |
| `node.cluster`                  | Envoy node cluster. Defaults to the release name when empty                                                          | `""`                |
| `logLevel`                      | Envoy log level (trace, debug, info, warning, error, critical, off)                                                 | `info`              |
| `drainTimeSeconds`              | Envoy drain time on shutdown (passed as --drain-time-s); should be < terminationGracePeriodSeconds                   | `30`                |
| `existingConfigMap`             | Name of an existing ConfigMap with an `envoy.yaml` bootstrap key. Disables the generated bootstrap                   | `""`                |
| `overrideConfiguration`         | Deep-merged on top of the generated bootstrap (e.g. add static listeners, tracing, stats sinks)                      | `{}`                |
| `replicaCount`                  | Number of Envoy replicas to deploy                                                                                  | `2`                 |
| `revisionHistoryLimit`          | The number of old history to retain to allow rollback                                                               | `10`                |
| `updateStrategy.type`           | Envoy deployment strategy type                                                                                      | `RollingUpdate`     |
| `updateStrategy.rollingUpdate`  | Envoy deployment rolling update configuration parameters                                                            | `{}`                |
| `containerPorts.http`           | Envoy main proxy listener container port. MUST match the port the LDS listener binds                                | `10000`             |
| `containerPorts.admin`          | Envoy admin interface container port                                                                               | `9901`              |
| `extraContainerPorts`           | Optional extra listener ports (e.g. an https listener). Must match LDS-bound ports                                   | `[]`                |
| `exposeAdmin`                   | Publish the admin interface on the Service. Keep false in production                                                | `false`             |
| `command`                       | Override default container command (useful when using custom images)                                                | `[]`                |
| `args`                          | Override default container args (useful when using custom images)                                                   | `[]`                |
| `automountServiceAccountToken`  | Mount Service Account token in pod                                                                                  | `false`             |
| `hostAliases`                   | Envoy pods host aliases                                                                                             | `[]`                |
| `extraEnvVars`                  | Array with extra environment variables to add to Envoy nodes                                                        | `[]`                |
| `extraEnvVarsCM`                | Name of existing ConfigMap containing extra env vars for Envoy nodes                                                | `""`                |
| `extraEnvVarsSecret`            | Name of existing Secret containing extra env vars for Envoy nodes                                                   | `""`                |
| `extraVolumes`                  | Optionally specify extra list of additional volumes for the Envoy pod(s)                                            | `[]`                |
| `extraVolumeMounts`             | Optionally specify extra list of additional volumeMounts for the Envoy container(s)                                 | `[]`                |
| `sidecars`                      | Add additional sidecar containers to the Envoy pod(s)                                                               | `[]`                |
| `initContainers`                | Add additional init containers to the Envoy pod(s)                                                                  | `[]`                |
| `resourcesPreset`               | Set container resources according to one common preset (allowed values: none, nano, micro, small, medium, large, xlarge, 2xlarge). This is ignored if resources is set | `small`             |
| `resources`                     | Set container requests and limits for different resources like CPU or memory (essential for production workloads)    | `{}`                |

### Security parameters

| Name                                                | Description                                                       | Value            |
| --------------------------------------------------- | ---------------------------------------------------------------- | ---------------- |
| `podSecurityContext.enabled`                        | Enabled Envoy pods' Security Context                             | `true`           |
| `podSecurityContext.fsGroupChangePolicy`            | Set filesystem group change policy                               | `Always`         |
| `podSecurityContext.supplementalGroups`             | Set filesystem extra groups                                      | `[]`             |
| `podSecurityContext.fsGroup`                        | Set Envoy pod's Security Context fsGroup                         | `101`            |
| `containerSecurityContext.enabled`                  | Enabled containers' Security Context                             | `true`           |
| `containerSecurityContext.seLinuxOptions`           | Set SELinux options in container                                 | `{}`             |
| `containerSecurityContext.runAsUser`                | Set containers' Security Context runAsUser                       | `101`            |
| `containerSecurityContext.runAsGroup`               | Set containers' Security Context runAsGroup                      | `101`            |
| `containerSecurityContext.runAsNonRoot`             | Set container's Security Context runAsNonRoot                    | `true`           |
| `containerSecurityContext.privileged`               | Set container's Security Context privileged                      | `false`          |
| `containerSecurityContext.readOnlyRootFilesystem`   | Set container's Security Context readOnlyRootFilesystem          | `true`           |
| `containerSecurityContext.allowPrivilegeEscalation` | Set container's Security Context allowPrivilegeEscalation        | `false`          |
| `containerSecurityContext.capabilities.drop`        | List of capabilities to be dropped                               | `["ALL"]`        |
| `containerSecurityContext.capabilities.add`         | List of capabilities to be added (e.g. NET_BIND_SERVICE for ports 80/443) | `[]`    |
| `containerSecurityContext.seccompProfile.type`      | Set container's Security Context seccomp profile                 | `RuntimeDefault` |

### Probes parameters

| Name                                 | Description                                          | Value   |
| ------------------------------------ | --------------------------------------------------- | ------- |
| `livenessProbe.enabled`              | Enable livenessProbe on Envoy containers            | `true`  |
| `livenessProbe.initialDelaySeconds`  | Initial delay seconds for livenessProbe             | `10`    |
| `livenessProbe.periodSeconds`        | Period seconds for livenessProbe                    | `10`    |
| `livenessProbe.timeoutSeconds`       | Timeout seconds for livenessProbe                   | `5`     |
| `livenessProbe.failureThreshold`     | Failure threshold for livenessProbe                 | `6`     |
| `livenessProbe.successThreshold`     | Success threshold for livenessProbe                 | `1`     |
| `readinessProbe.enabled`             | Enable readinessProbe on Envoy containers           | `true`  |
| `readinessProbe.initialDelaySeconds` | Initial delay seconds for readinessProbe            | `5`     |
| `readinessProbe.periodSeconds`       | Period seconds for readinessProbe                   | `10`    |
| `readinessProbe.timeoutSeconds`      | Timeout seconds for readinessProbe                  | `5`     |
| `readinessProbe.failureThreshold`    | Failure threshold for readinessProbe                | `6`     |
| `readinessProbe.successThreshold`    | Success threshold for readinessProbe                | `1`     |
| `startupProbe.enabled`               | Enable startupProbe on Envoy containers             | `false` |
| `startupProbe.initialDelaySeconds`   | Initial delay seconds for startupProbe              | `5`     |
| `startupProbe.periodSeconds`         | Period seconds for startupProbe                     | `10`    |
| `startupProbe.timeoutSeconds`        | Timeout seconds for startupProbe                    | `5`     |
| `startupProbe.failureThreshold`      | Failure threshold for startupProbe                  | `30`    |
| `startupProbe.successThreshold`      | Success threshold for startupProbe                  | `1`     |
| `customLivenessProbe`                | Custom livenessProbe that overrides the default one | `{}`    |
| `customReadinessProbe`               | Custom readinessProbe that overrides the default one| `{}`    |
| `customStartupProbe`                 | Custom startupProbe that overrides the default one  | `{}`    |
| `lifecycleHooks`                     | lifecycleHooks for the Envoy container(s) to automate configuration before or after startup | `{}` |

### Scheduling parameters

| Name                             | Description                                                                               | Value  |
| -------------------------------- | ----------------------------------------------------------------------------------------- | ------ |
| `podLabels`                      | Extra labels for Envoy pods                                                                | `{}`   |
| `podAnnotations`                 | Annotations for Envoy pods                                                                 | `{}`   |
| `podAffinityPreset`              | Pod affinity preset. Ignored if `affinity` is set. Allowed values: `soft` or `hard`       | `""`   |
| `podAntiAffinityPreset`          | Pod anti-affinity preset. Ignored if `affinity` is set. Allowed values: `soft` or `hard`  | `soft` |
| `nodeAffinityPreset.type`        | Node affinity preset type. Ignored if `affinity` is set. Allowed values: `soft` or `hard` | `""`   |
| `nodeAffinityPreset.key`         | Node label key to match. Ignored if `affinity` is set                                     | `""`   |
| `nodeAffinityPreset.values`      | Node label values to match. Ignored if `affinity` is set                                  | `[]`   |
| `affinity`                       | Affinity for Envoy pods assignment                                                        | `{}`   |
| `nodeSelector`                   | Node labels for Envoy pods assignment                                                      | `{}`   |
| `tolerations`                    | Tolerations for Envoy pods assignment                                                      | `[]`   |
| `topologySpreadConstraints`      | Topology Spread Constraints for Envoy pod assignment spread across your cluster among failure-domains | `[]` |
| `priorityClassName`              | Envoy pods' priorityClassName                                                             | `""`   |
| `schedulerName`                  | Name of the k8s scheduler (other than default)                                            | `""`   |
| `terminationGracePeriodSeconds`  | Seconds Envoy pod needs to terminate gracefully                                           | `60`   |

### Traffic Exposure parameters

| Name                                | Description                                                              | Value       |
| ----------------------------------- | ----------------------------------------------------------------------- | ----------- |
| `service.type`                      | Envoy service type                                                      | `ClusterIP` |
| `service.ports.http`                | Envoy service HTTP port (data-plane listener)                          | `80`        |
| `service.ports.admin`               | Envoy service admin port (only published when exposeAdmin=true)        | `9901`      |
| `service.nodePorts.http`            | Node port for HTTP                                                       | `""`        |
| `service.nodePorts.admin`           | Node port for admin                                                      | `""`        |
| `service.clusterIP`                 | Envoy service Cluster IP                                                | `""`        |
| `service.loadBalancerIP`            | Envoy service Load Balancer IP                                          | `""`        |
| `service.loadBalancerClass`         | Envoy service Load Balancer class (if type is LoadBalancer)            | `""`        |
| `service.loadBalancerSourceRanges`  | Envoy service Load Balancer sources                                     | `[]`        |
| `service.externalTrafficPolicy`     | Envoy service external traffic policy                                   | `Cluster`   |
| `service.sessionAffinity`           | Control where client requests go, to the same pod or round-robin        | `None`      |
| `service.sessionAffinityConfig`     | Additional settings for the sessionAffinity                             | `{}`        |
| `service.annotations`               | Additional custom annotations for Envoy service                        | `{}`        |
| `service.labels`                    | Additional custom labels for Envoy service                             | `{}`        |
| `service.extraPorts`                | Extra ports to expose in the Envoy service (normally used with extraContainerPorts) | `[]` |

### ServiceAccount parameters

| Name                                          | Description                                                              | Value  |
| --------------------------------------------- | ----------------------------------------------------------------------- | ------ |
| `serviceAccount.create`                       | Specifies whether a ServiceAccount should be created                    | `true` |
| `serviceAccount.name`                         | The name of the ServiceAccount to use                                   | `""`   |
| `serviceAccount.annotations`                  | Additional Service Account annotations                                  | `{}`   |
| `serviceAccount.automountServiceAccountToken` | Automount service account token for the server service account          | `false`|

### Autoscaling and disruption parameters

| Name                            | Description                                                                                                | Value   |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------- | ------- |
| `autoscaling.hpa.enabled`       | Enable HPA for Envoy                                                                                       | `false` |
| `autoscaling.hpa.minReplicas`   | Minimum number of Envoy replicas                                                                          | `2`     |
| `autoscaling.hpa.maxReplicas`   | Maximum number of Envoy replicas                                                                          | `10`    |
| `autoscaling.hpa.targetCPU`     | Target CPU utilization percentage                                                                         | `80`    |
| `autoscaling.hpa.targetMemory`  | Target Memory utilization percentage                                                                      | `""`    |
| `pdb.create`                    | Enable/disable a Pod Disruption Budget creation                                                           | `true`  |
| `pdb.minAvailable`              | Minimum number/percentage of pods that should remain scheduled                                           | `""`    |
| `pdb.maxUnavailable`            | Maximum number/percentage of pods that may be made unavailable. Defaults to `1` if both `pdb.minAvailable` and `pdb.maxUnavailable` are empty | `""` |

### NetworkPolicy parameters

| Name                                    | Description                                                       | Value  |
| --------------------------------------- | ---------------------------------------------------------------- | ------ |
| `networkPolicy.enabled`                 | Specifies whether a NetworkPolicy should be created              | `true` |
| `networkPolicy.allowExternal`           | Don't require server label for connections                       | `true` |
| `networkPolicy.allowExternalEgress`     | Allow the pod to access any range of port and all destinations   | `true` |
| `networkPolicy.extraIngress`            | Add extra ingress rules to the NetworkPolicy                     | `[]`   |
| `networkPolicy.extraEgress`             | Add extra egress rules to the NetworkPolicy                      | `[]`   |
| `networkPolicy.ingressNSMatchLabels`    | Labels to match to allow traffic from other namespaces           | `{}`   |
| `networkPolicy.ingressNSPodMatchLabels` | Pod labels to match to allow traffic from other namespaces       | `{}`   |

### Metrics parameters

| Name                                     | Description                                                                | Value               |
| ---------------------------------------- | -------------------------------------------------------------------------- | ------------------- |
| `metrics.enabled`                        | Enable scraping of Envoy admin Prometheus stats (/stats/prometheus on the admin port) | `false`  |
| `metrics.annotations`                    | Annotations for the Prometheus pod/service scrape                          | `{}`                |
| `metrics.serviceMonitor.enabled`         | Create a ServiceMonitor for Envoy admin stats                             | `false`             |
| `metrics.serviceMonitor.namespace`       | Namespace in which the ServiceMonitor is created                          | `""`                |
| `metrics.serviceMonitor.path`            | Stats path to scrape                                                       | `/stats/prometheus` |
| `metrics.serviceMonitor.interval`        | Scrape interval                                                            | `""`                |
| `metrics.serviceMonitor.scrapeTimeout`   | Scrape timeout                                                             | `""`                |
| `metrics.serviceMonitor.labels`          | Extra labels for the ServiceMonitor                                       | `{}`                |
| `metrics.serviceMonitor.relabelings`     | RelabelConfigs to apply to samples before scraping                        | `[]`                |
| `metrics.serviceMonitor.metricRelabelings`| MetricRelabelConfigs to apply to samples before ingestion                | `[]`                |

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

```console
helm install my-envoy \
  --set controlPlane.host=xds-control-plane.my-ns.svc.cluster.local \
  --set replicaCount=3 \
  ./bitnami/envoy
```

Alternatively, a YAML file that specifies the values for the above parameters can be provided while installing the chart. For example,

```console
helm install my-envoy -f values.yaml ./bitnami/envoy
```

> **Tip**: You can use the default [values.yaml](https://github.com/bitnami/charts/tree/main/bitnami/envoy/values.yaml)

## Troubleshooting

Find more information about how to deal with common errors related to Bitnami's Helm charts in [this troubleshooting guide](https://docs.bitnami.com/general/how-to/troubleshoot-helm-chart-issues).

A few Envoy-specific checks:

- **Pods stay `NotReady`** — Envoy's `/ready` only returns 200 once it has received an initial LDS update. Confirm the control plane is reachable (`controlPlane.host`/`controlPlane.port`) and is actually serving config for this `node.id`/`node.cluster`.
- **Inspect what was pushed** — port-forward the admin port and hit `/config_dump` and `/clusters` (see [Verifying](#verifying)).
- **Listener port mismatch** — `containerPorts.http` (and any `extraContainerPorts`) must match the ports your LDS listeners bind, otherwise traffic to the Service is not served.

## Upgrading

### To 1.0.0

Initial release of the Envoy data-plane chart.

## License

Copyright &copy; 2026 Broadcom. The term "Broadcom" refers to Broadcom Inc. and/or its subsidiaries.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

<http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
