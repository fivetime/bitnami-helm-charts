<!--- app-name: daemonclaim -->

# daemonclaim packaged by Broadcom

Gives DaemonSets the per-node PersistentVolumeClaims that StatefulSets get from `volumeClaimTemplates`.

## TL;DR

```console
helm install my-release oci://REGISTRY_NAME/REPOSITORY_NAME/daemonclaim \
  --set webhook.certificate.certManager.enabled=true
```

Then, for any DaemonSet, add one label and one placeholder to its pod template and create a `DaemonClaim`:

```yaml
# in the DaemonSet
spec:
  template:
    metadata:
      labels:
        daemonclaim.fivetime.io/enabled: "true"
    spec:
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: data          # replaced per node when the pod is created
---
apiVersion: daemonclaim.fivetime.io/v1alpha1
kind: DaemonClaim
metadata:
  name: fluent-bit-data
spec:
  daemonSetRef:
    name: fluent-bit
  volumeClaimTemplates:
    - metadata:
        name: data                   # the volume above
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: local-path-daemon
        resources:
          requests:
            storage: 10Gi
  persistentVolumeClaimRetentionPolicy:
    whenDeleted: Retain
    whenUnscheduled: Retain
```

## Introduction

A DaemonSet that needs node-local storage which outlives its pod — a log buffer, a build cache, a local time-series database — has exactly one option today: `hostPath`. That means no capacity limit, nothing Kubernetes can see, nothing that gets cleaned up, and no say in what filesystem the data lands on. `StatefulSet` solved all of this with `volumeClaimTemplates`; `DaemonSet` never got them ([kubernetes/kubernetes#78902](https://github.com/kubernetes/kubernetes/issues/78902)).

This chart deploys [daemonclaim](https://github.com/fivetime/daemonclaim), which closes the gap out of tree:

```
  DaemonSet controller ──► Pod (pinned to node N)
                              │
                     mutating webhook: claimName: data ──► <daemonset>-data-N
                              │
                     controller: makes sure PVC <daemonset>-data-N exists
                              │
                 StorageClass (WaitForFirstConsumer) binds it on node N
```

- One PVC per (DaemonSet, node, claim template), named `<daemonset>-<template>-<node>`. The pod on that node is pointed at it at admission time, so a pod restart or a rollout finds the same claim and the same data.
- A `persistentVolumeClaimRetentionPolicy` shaped like StatefulSet's: `whenDeleted` (the DaemonSet is gone) and `whenUnscheduled` (a node stopped being one the DaemonSet runs on). Both default to `Retain`. `Delete` on `whenUnscheduled` only acts after a grace period **and** once the node no longer matches the DaemonSet's selection, so a rollout or an eviction is never mistaken for a node leaving.
- Storage-agnostic. Any CSI driver, any `StorageClass` with `volumeBindingMode: WaitForFirstConsumer`.

What it deliberately does not do: provision storage, or mount a volume at a caller-chosen host path. Workloads whose data is read by a node process at a fixed absolute path stay on `hostPath`.

## Prerequisites

- Kubernetes 1.25+
- Helm 3.8.0+
- A `StorageClass` with `volumeBindingMode: WaitForFirstConsumer` for the claims. The [daemonclaim repository](https://github.com/fivetime/daemonclaim/tree/main/contrib/local-path) ships one served by an unmodified [local-path-provisioner](https://github.com/rancher/local-path-provisioner).
- For `webhook.certificate.certManager.enabled=true`: [cert-manager](https://cert-manager.io/) installed.

## Installing the Chart

```console
helm install my-release oci://REGISTRY_NAME/REPOSITORY_NAME/daemonclaim
```

> Note: You need to substitute the placeholders `REGISTRY_NAME` and `REPOSITORY_NAME` with a reference to your Helm chart registry and repository. For example, in the case of Bitnami, you need to use `REGISTRY_NAME=registry-1.docker.io` and `REPOSITORY_NAME=bitnamicharts`.

The chart installs the `DaemonClaim` CRD from its `crds/` directory. Helm installs CRDs but never upgrades them; when a chart upgrade changes the CRD, apply it by hand first:

```console
kubectl apply -f https://raw.githubusercontent.com/fivetime/daemonclaim/main/config/crd/bases/daemonclaim.fivetime.io_daemonclaims.yaml
```

## Configuration and installation details

### The webhook certificate

Two admission webhooks do the work, and the API server has to trust their serving certificate. Three ways to get one, tried in this order:

| Setting | What happens |
|---|---|
| `webhook.certificate.existingSecret` | You provide a TLS Secret with `tls.crt`, `tls.key` and `ca.crt`. The `ca.crt` is what the API server is told to trust. |
| `webhook.certificate.certManager.enabled=true` | cert-manager issues and rotates the certificate and injects the CA into the webhook configurations. With no `issuerRef`, a self-signed `Issuer` is created for the release. **Use this wherever cert-manager is available.** |
| neither (default) | Helm generates a CA and certificate at install time, stores them in a Secret, and reuses them on every upgrade. Nothing rotates them, so they are valid for `webhook.certificate.autoGenerated.validityDays` (ten years). |

### `failurePolicy` is `Fail`, and should stay that way

The mutating webhook has an `objectSelector` for the label `daemonclaim.fivetime.io/enabled=true`, so only pods that opted in reach it. When the webhook is unreachable, `Fail` refuses those pods and nothing else — loud, scoped, and safe. `Ignore` would admit them with the placeholder `claimName` they were written with, and every node's pod would then share one claim or all sit Pending on a name that does not exist. `webhook.failurePolicy` exists for completeness; the chart warns on install if it is set to `Ignore`.

Because the webhook sits in the admission path of every opted-in DaemonSet, give the controller a `priorityClassName` on clusters where eviction under pressure is a real possibility, and consider `replicaCount: 2` — leader election keeps reconciliation single-writer while every replica serves the webhooks.

### What the controller is allowed to do

`rbac.create` grants a ClusterRole that mirrors the one generated from the controller's source: read nodes, pods, DaemonSets and StorageClasses; create, patch and delete PersistentVolumeClaims in every namespace; delete pods. The PVC grant is the one that matters: anyone who can create a `DaemonClaim` can cause claims to appear in their own namespace, subject to that namespace's `ResourceQuota`, which the controller does not bypass. The pod grant is used for exactly one thing — deleting a Pending pod that was admitted before its DaemonClaim existed, so the DaemonSet recreates it through the webhook.

### Ordering does not matter

If the DaemonSet is created before its DaemonClaim, its first pods are admitted with the placeholder `claimName`. The controller deletes those pods (only Pending ones) and the DaemonSet replaces them through the webhook. Create the two objects in whichever order is convenient.

### Metrics

With `metrics.enabled`, the controller serves Prometheus metrics on `metrics.port`, without TLS: controller-runtime's own, plus

- `daemonclaim_claims{namespace,daemonclaim,state}` — claims per DaemonClaim, by `bound`, `unbound`, `unscheduled`
- `daemonclaim_webhook_rewrites_total{result,reason}` — pod admissions by outcome. Alert on `result="passthrough"` with any `reason` other than `not_opted_in`: those pods will sit Pending.
- `daemonclaim_retention_decisions_total{decision}` — what happened to claims on nodes with no pod

`metrics.serviceMonitor.enabled` creates a ServiceMonitor for the Prometheus Operator.

### Resource requests and limits

Bitnami charts allow setting resource requests and limits for all containers inside the chart deployment. These are inside the `resources` value (check parameter table). Setting requests is essential for production workloads and these should be adapted to your specific use case.

To make this process easier, the chart contains the `resourcesPreset` values, which automatically sets the `resources` section according to different presets. Check these presets in [the bitnami/common chart](https://github.com/bitnami/charts/blob/main/bitnami/common/templates/_resources.tpl#L15). However, in production workloads using `resourcesPreset` is discouraged as it may not fully adapt to your specific needs. Find more information on container resource management in the [official Kubernetes documentation](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/).

### Additional environment variables

In case you want to add extra environment variables (useful for advanced operations like custom init scripts), you can use the `extraEnvVars` property.

```yaml
extraEnvVars:
  - name: LOG_LEVEL
    value: debug
```

Alternatively, you can use a ConfigMap or a Secret with the environment variables. To do so, use the `extraEnvVarsCM` or the `extraEnvVarsSecret` values.

### Sidecars and init containers

If additional containers are needed in the same pod as the controller (such as additional metrics or logging exporters), they can be defined using the `sidecars` parameter. Similarly, you can add extra init containers using the `initContainers` parameter.

### Deploying extra resources

There are cases where you may want to deploy extra objects, such as the `DaemonClaim` objects themselves or a `StorageClass`. For covering this case, the chart allows adding the full specification of other objects using the `extraDeploy` parameter.

## Parameters

### Global parameters

| Name                                                  | Description                                                                                                                                                                                                                                                                                                                                                         | Value  |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| `global.imageRegistry`                                | Global Docker image registry                                                                                                                                                                                                                                                                                                                                        | `""`   |
| `global.imagePullSecrets`                             | Global Docker registry secret names as an array                                                                                                                                                                                                                                                                                                                     | `[]`   |
| `global.compatibility.openshift.adaptSecurityContext` | Adapt the securityContext sections of the deployment to make them compatible with Openshift restricted-v2 SCC: remove runAsUser, runAsGroup and fsGroup and let the platform use their allowed default IDs. Possible values: auto (apply if the detected running cluster is Openshift), force (perform the adaptation always), disabled (do not perform adaptation) | `auto` |

### Common parameters

| Name                     | Description                                                                             | Value           |
| ------------------------ | --------------------------------------------------------------------------------------- | --------------- |
| `kubeVersion`            | Override Kubernetes version                                                             | `""`            |
| `nameOverride`           | String to partially override common.names.fullname                                      | `""`            |
| `fullnameOverride`       | String to fully override common.names.fullname                                          | `""`            |
| `namespaceOverride`      | String to fully override common.names.namespace                                         | `""`            |
| `commonLabels`           | Labels to add to all deployed objects                                                   | `{}`            |
| `commonAnnotations`      | Annotations to add to all deployed objects                                              | `{}`            |
| `extraDeploy`            | Array of extra objects to deploy with the release                                       | `[]`            |
| `diagnosticMode.enabled` | Enable diagnostic mode (all probes will be disabled and the command will be overridden) | `false`         |
| `diagnosticMode.command` | Command to override all containers in the deployment                                    | `["sleep"]`     |
| `diagnosticMode.args`    | Args to override all containers in the deployment                                       | `["infinity"]`  |

### Controller parameters

| Name                 | Description                                                                                                                       | Value                  |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------- | ---------------------- |
| `image.registry`     | daemonclaim image registry                                                                                                        | `ghcr.io`              |
| `image.repository`   | daemonclaim image repository                                                                                                      | `fivetime/daemonclaim` |
| `image.digest`       | daemonclaim image digest in the way sha256:aa.... Please note this parameter, if set, will override the tag                       | `""`                   |
| `image.pullPolicy`   | daemonclaim image pull policy                                                                                                     | `IfNotPresent`         |
| `image.pullSecrets`  | daemonclaim image pull secrets                                                                                                    | `[]`                   |
| `replicaCount`       | Number of controller replicas. Leader election makes more than one safe; only the leader reconciles, every replica serves the webhooks | `1`               |
| `leaderElection`     | Enable leader election. Required for replicaCount > 1, harmless at 1                                                              | `true`                 |
| `logLevel`           | Log verbosity: `info` or `debug`                                                                                                  | `info`                 |
| `extraArgs`          | Extra arguments for the controller binary                                                                                         | `[]`                   |
| `command`            | Override the container command                                                                                                    | `[]`                   |
| `args`               | Override the container args                                                                                                       | `[]`                   |
| `extraEnvVars`       | Extra environment variables for the controller container                                                                          | `[]`                   |
| `extraEnvVarsCM`     | Name of an existing ConfigMap with extra environment variables                                                                    | `""`                   |
| `extraEnvVarsSecret` | Name of an existing Secret with extra environment variables                                                                       | `""`                   |

### Webhook parameters

| Name                                                | Description                                                                                                                                                                                                                                                | Value   |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `webhook.port`                                      | Port the webhook server listens on inside the pod                                                                                                                                                                                                          | `9443`  |
| `webhook.timeoutSeconds`                            | Admission timeout the API server allows each webhook                                                                                                                                                                                                       | `10`    |
| `webhook.certificate.existingSecret`                | Name of an existing TLS Secret with `tls.crt`, `tls.key` and `ca.crt`. The CA is what the API server is told to trust                                                                                                                                       | `""`    |
| `webhook.certificate.certManager.enabled`           | Issue the certificate with cert-manager                                                                                                                                                                                                                    | `false` |
| `webhook.certificate.certManager.issuerRef`         | Reference to an existing Issuer or ClusterIssuer. Empty means a self-signed Issuer is created for this release                                                                                                                                             | `{}`    |
| `webhook.certificate.certManager.duration`          | Validity of the issued certificate                                                                                                                                                                                                                         | `2160h` |
| `webhook.certificate.certManager.renewBefore`       | How long before expiry cert-manager renews it                                                                                                                                                                                                              | `360h`  |
| `webhook.certificate.autoGenerated.validityDays`    | Validity, in days, of the generated CA and certificate                                                                                                                                                                                                     | `3650`  |
| `webhook.failurePolicy`                             | What the API server does when the webhook cannot be reached. `Fail` refuses opted-in pods, which is loud and safe; `Ignore` admits them with a placeholder claimName that every node's pod would then share                                                | `Fail`  |

### RBAC and ServiceAccount parameters

| Name                                          | Description                                                                                                                | Value  |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | ------ |
| `rbac.create`                                 | Create the ClusterRole, Role and bindings the controller needs                                                             | `true` |
| `serviceAccount.create`                       | Specifies whether a ServiceAccount should be created                                                                       | `true` |
| `serviceAccount.name`                         | The name of the ServiceAccount to use. If not set and create is true, a name is generated using the common.names.fullname template | `""`   |
| `serviceAccount.annotations`                  | Additional Service Account annotations (evaluated as a template)                                                          | `{}`   |
| `serviceAccount.automountServiceAccountToken` | Automount service account token for the server service account                                                             | `true` |

### Metrics parameters

| Name                                       | Description                                                                                                                                       | Value       |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- |
| `metrics.enabled`                          | Serve Prometheus metrics: controller-runtime's own plus `daemonclaim_claims`, `daemonclaim_webhook_rewrites_total` and `daemonclaim_retention_decisions_total` | `true` |
| `metrics.port`                             | Port the metrics endpoint listens on inside the pod                                                                                               | `8080`      |
| `metrics.service.enabled`                  | Create a Service for the metrics endpoint                                                                                                         | `true`      |
| `metrics.service.type`                     | Metrics Service type                                                                                                                              | `ClusterIP` |
| `metrics.service.port`                     | Metrics Service port                                                                                                                              | `8080`      |
| `metrics.service.annotations`              | Annotations for the metrics Service                                                                                                               | `{}`        |
| `metrics.serviceMonitor.enabled`           | Create a ServiceMonitor (requires the Prometheus Operator CRDs)                                                                                   | `false`     |
| `metrics.serviceMonitor.namespace`         | Namespace for the ServiceMonitor. Defaults to the release namespace                                                                               | `""`        |
| `metrics.serviceMonitor.interval`          | Scrape interval                                                                                                                                   | `""`        |
| `metrics.serviceMonitor.scrapeTimeout`     | Scrape timeout                                                                                                                                    | `""`        |
| `metrics.serviceMonitor.labels`            | Additional labels, e.g. for the Prometheus instance's serviceMonitorSelector                                                                      | `{}`        |
| `metrics.serviceMonitor.relabelings`       | RelabelConfigs to apply to samples before scraping                                                                                                | `[]`        |
| `metrics.serviceMonitor.metricRelabelings` | MetricRelabelConfigs to apply to samples before ingestion                                                                                         | `[]`        |
| `metrics.serviceMonitor.honorLabels`       | Honor metrics labels                                                                                                                              | `false`     |
| `metrics.serviceMonitor.jobLabel`          | The name of the label on the target service to use as the job name in Prometheus                                                                  | `""`        |

### Deployment parameters

| Name                                                | Description                                                                                                                                                      | Value            |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| `updateStrategy.type`                               | Deployment strategy type                                                                                                                                         | `RollingUpdate`  |
| `updateStrategy.rollingUpdate`                      | Deployment rolling update configuration parameters                                                                                                               | `{}`             |
| `revisionHistoryLimit`                              | Number of old ReplicaSets to retain                                                                                                                              | `10`             |
| `podLabels`                                         | Extra labels for controller pods                                                                                                                                 | `{}`             |
| `podAnnotations`                                    | Annotations for controller pods                                                                                                                                  | `{}`             |
| `automountServiceAccountToken`                      | Mount the ServiceAccount token in the pod. The controller talks to the API server, so it needs one                                                               | `true`           |
| `hostAliases`                                       | Deployment pod host aliases                                                                                                                                      | `[]`             |
| `priorityClassName`                                 | Priority class for the controller pods. The webhook sits in the admission path of every opted-in DaemonSet, so it should not be the first thing evicted          | `""`             |
| `schedulerName`                                     | Name of the Kubernetes scheduler to use                                                                                                                          | `""`             |
| `topologySpreadConstraints`                         | Topology spread constraints for the controller pods                                                                                                              | `[]`             |
| `podAffinityPreset`                                 | Pod affinity preset. Ignored if `affinity` is set. Allowed values: `soft` or `hard`                                                                              | `""`             |
| `podAntiAffinityPreset`                             | Pod anti-affinity preset. Ignored if `affinity` is set. Allowed values: `soft` or `hard`                                                                         | `soft`           |
| `nodeAffinityPreset.type`                           | Node affinity preset type. Ignored if `affinity` is set. Allowed values: `soft` or `hard`                                                                        | `""`             |
| `nodeAffinityPreset.key`                            | Node label key to match. Ignored if `affinity` is set                                                                                                            | `""`             |
| `nodeAffinityPreset.values`                         | Node label values to match. Ignored if `affinity` is set                                                                                                         | `[]`             |
| `affinity`                                          | Affinity for pod assignment. Evaluated as a template                                                                                                             | `{}`             |
| `nodeSelector`                                      | Node labels for pod assignment. Evaluated as a template                                                                                                          | `{}`             |
| `tolerations`                                       | Tolerations for pod assignment. Evaluated as a template                                                                                                          | `[]`             |
| `terminationGracePeriodSeconds`                     | Seconds the controller pod is given to stop                                                                                                                      | `10`             |
| `podSecurityContext.enabled`                        | Enable pod security context                                                                                                                                      | `true`           |
| `podSecurityContext.fsGroupChangePolicy`            | Set filesystem group change policy                                                                                                                               | `Always`         |
| `podSecurityContext.sysctls`                        | Set kernel settings using the sysctl interface                                                                                                                   | `[]`             |
| `podSecurityContext.supplementalGroups`             | Set filesystem extra groups                                                                                                                                      | `[]`             |
| `podSecurityContext.fsGroup`                        | Group ID for the pod's volumes                                                                                                                                   | `65532`          |
| `containerSecurityContext.enabled`                  | Enable container security context                                                                                                                                | `true`           |
| `containerSecurityContext.seLinuxOptions`           | Set SELinux options in container                                                                                                                                 | `{}`             |
| `containerSecurityContext.runAsUser`                | User ID for the container                                                                                                                                        | `65532`          |
| `containerSecurityContext.runAsGroup`               | Group ID for the container                                                                                                                                       | `65532`          |
| `containerSecurityContext.runAsNonRoot`             | Run container as non-root                                                                                                                                        | `true`           |
| `containerSecurityContext.privileged`               | Run container as privileged                                                                                                                                      | `false`          |
| `containerSecurityContext.readOnlyRootFilesystem`   | Mount the container root filesystem read-only                                                                                                                    | `true`           |
| `containerSecurityContext.allowPrivilegeEscalation` | Allow privilege escalation                                                                                                                                       | `false`          |
| `containerSecurityContext.capabilities.drop`        | Linux capabilities to drop                                                                                                                                       | `["ALL"]`        |
| `containerSecurityContext.seccompProfile.type`      | Seccomp profile type                                                                                                                                             | `RuntimeDefault` |
| `resourcesPreset`                                   | Set container resources according to one common preset (allowed values: none, nano, micro, small, medium, large, xlarge, 2xlarge). This is ignored if resources is set (resources is recommended for production). | `nano` |
| `resources`                                         | Set container requests and limits for different resources like CPU or memory (essential for production workloads)                                                | `{}`             |
| `livenessProbe.enabled`                             | Enable livenessProbe                                                                                                                                             | `true`           |
| `livenessProbe.initialDelaySeconds`                 | Initial delay seconds for livenessProbe                                                                                                                          | `10`             |
| `livenessProbe.periodSeconds`                       | Period seconds for livenessProbe                                                                                                                                 | `20`             |
| `livenessProbe.timeoutSeconds`                      | Timeout seconds for livenessProbe                                                                                                                                | `5`              |
| `livenessProbe.failureThreshold`                    | Failure threshold for livenessProbe                                                                                                                              | `3`              |
| `livenessProbe.successThreshold`                    | Success threshold for livenessProbe                                                                                                                              | `1`              |
| `readinessProbe.enabled`                            | Enable readinessProbe                                                                                                                                            | `true`           |
| `readinessProbe.initialDelaySeconds`                | Initial delay seconds for readinessProbe                                                                                                                         | `5`              |
| `readinessProbe.periodSeconds`                      | Period seconds for readinessProbe                                                                                                                                | `10`             |
| `readinessProbe.timeoutSeconds`                     | Timeout seconds for readinessProbe                                                                                                                               | `5`              |
| `readinessProbe.failureThreshold`                   | Failure threshold for readinessProbe                                                                                                                             | `3`              |
| `readinessProbe.successThreshold`                   | Success threshold for readinessProbe                                                                                                                             | `1`              |
| `startupProbe.enabled`                              | Enable startupProbe                                                                                                                                              | `false`          |
| `startupProbe.initialDelaySeconds`                  | Initial delay seconds for startupProbe                                                                                                                           | `5`              |
| `startupProbe.periodSeconds`                        | Period seconds for startupProbe                                                                                                                                  | `5`              |
| `startupProbe.timeoutSeconds`                       | Timeout seconds for startupProbe                                                                                                                                 | `5`              |
| `startupProbe.failureThreshold`                     | Failure threshold for startupProbe                                                                                                                               | `12`             |
| `startupProbe.successThreshold`                     | Success threshold for startupProbe                                                                                                                               | `1`              |
| `customLivenessProbe`                               | Custom livenessProbe that overrides the default one                                                                                                              | `{}`             |
| `customReadinessProbe`                              | Custom readinessProbe that overrides the default one                                                                                                             | `{}`             |
| `customStartupProbe`                                | Custom startupProbe that overrides the default one                                                                                                               | `{}`             |
| `lifecycleHooks`                                    | Lifecycle hooks for the controller container                                                                                                                     | `{}`             |
| `extraVolumes`                                      | Extra volumes for the controller pod                                                                                                                             | `[]`             |
| `extraVolumeMounts`                                 | Extra volume mounts for the controller container                                                                                                                 | `[]`             |
| `sidecars`                                          | Extra sidecar containers for the controller pod                                                                                                                  | `[]`             |
| `initContainers`                                    | Extra init containers for the controller pod                                                                                                                     | `[]`             |
| `pdb.create`                                        | Create a PodDisruptionBudget. Only meaningful with replicaCount > 1                                                                                              | `true`           |
| `pdb.minAvailable`                                  | Minimum number/percentage of pods that must remain available                                                                                                     | `""`             |
| `pdb.maxUnavailable`                                | Maximum number/percentage of pods that may be made unavailable. Defaults to `1` if both this and `pdb.minAvailable` are empty                                    | `""`             |

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

```console
helm install my-release --set webhook.certificate.certManager.enabled=true oci://REGISTRY_NAME/REPOSITORY_NAME/daemonclaim
```

Alternatively, a YAML file that specifies the values for the parameters can be provided while installing the chart. For example,

```console
helm install my-release -f values.yaml oci://REGISTRY_NAME/REPOSITORY_NAME/daemonclaim
```

## Troubleshooting

### Opted-in pods stay Pending on a claim named after the placeholder

The pod was admitted without the webhook rewriting it. Either the webhook was unreachable while `webhook.failurePolicy` was `Ignore`, or no `DaemonClaim` referenced the DaemonSet at the time. The controller deletes such pods once a DaemonClaim exists; if they persist, check `daemonclaim_webhook_rewrites_total{result="passthrough"}` and the controller logs for the reason.

### Claims never bind

The StorageClass must have `volumeBindingMode: WaitForFirstConsumer`. With `Immediate`, the volume is provisioned on an arbitrary node while the pod is pinned to another and never schedules. The validating webhook rejects DaemonClaims that name such a StorageClass; a default StorageClass is only warned about.

### A claim was not deleted after a node left

Under `whenUnscheduled: Delete`, both gates must open: the grace period (`unscheduledGracePeriod`, default 30m) has passed **and** the node no longer matches the DaemonSet's `nodeSelector` and node affinity, or the Node object is gone. A node that is merely tainted or `NotReady` keeps its claim on purpose. `kubectl describe daemonclaim` shows the decisions as events.

Find more information about how to deal with common errors related to Bitnami's Helm charts in [this troubleshooting guide](https://docs.bitnami.com/general/how-to/troubleshoot-helm-chart-issues).

## License

Copyright &copy; 2026 Broadcom. The term "Broadcom" refers to Broadcom Inc. and/or its subsidiaries.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.

<http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
