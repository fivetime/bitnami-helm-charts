<!--- app-name: Docker daemon -->

# Docker daemon packaged by Broadcom

Delivers the Docker daemon to selected nodes as a DaemonSet, instead of installing it on each of them.

The daemon is a **control plane only**: it builds images, manages the graph and serves the Docker API, while the containerd the kubelet already runs actually starts the processes. Its socket is published at the usual host path, so anything on the node that expects Docker finds it there.

## TL;DR

```console
kubectl label node worker-1 docker.io/daemon=true
helm install my-release oci://REGISTRY_NAME/REPOSITORY_NAME/dockerd \
  --set nodeSelector."docker\.io/daemon"=true
```

Then, on that node:

```console
docker build -t myimage .
```

## Introduction

Nodes run containerd; Docker is not installed and, since the dockershim was removed in Kubernetes 1.24, has no reason to be. But plenty of things still want the Docker API — CI jobs, `docker compose`, Testcontainers, tooling nobody is going to port. The usual answer is to install Docker on those nodes with a package manager and a systemd unit, which means configuration management, drift between nodes, and a second container runtime with its own containerd competing with the kubelet's.

This chart delivers the same thing as a DaemonSet and drops the second runtime:

```
              ┌──────────────── node ────────────────┐
  kubelet ──► │  containerd (k8s.io ns) ──┐          │
              │                           ├─► runc   │
  Pod ──────► │  dockerd (moby ns) ───────┘          │
  (this chart)│      └─ /run/docker.sock ─► node users
              └──────────────────────────────────────┘
```

`dockerd --containerd=<addr>` is what makes it work, and it is Docker's own supported mode — moby's config field is documented as *"the address used to connect to containerd if we're not starting it ourselves"*. Docker's containers go into containerd's `moby` namespace and the kubelet's stay in `k8s.io`, so one containerd serves both without either seeing the other's containers.

What you get for that: one runtime per node instead of two, no Docker packages to install or upgrade, the version pinned in a values file rather than in a base image, and `helm upgrade` as the rollout mechanism.

### The client comes with it

Publishing the socket is only half of a node-level Docker install. A socket with no `docker` binary next to it is not usable from the node at all, and telling people to install docker-cli on every node would give back most of what the chart is for.

So an init container copies the client out of the daemon image into `hostCli.binDir` on the node. It is the static build from Docker's own release tarball, so it runs on any distribution whatever its libc, and it is refreshed on every pod start, which keeps the client in step with the daemon across chart upgrades. It is the same move [multus-cni](https://github.com/bitnami/charts/tree/main/bitnami/multus-cni) makes to place its CNI binary.

The `buildx` and `compose` plugins are available the same way but are **off by default**, one switch each — a node that hosts this daemon is generally somewhere builds are executed, not somewhere a person sits running `docker compose`. Turn on what you use:

```console
--set hostCli.plugins.buildx=true --set hostCli.plugins.compose=true
```

Without buildx, `docker buildx ...` and multi-platform builds are unavailable; plain `docker build` still works through the client's own build path.

Two things to know. `hostCli.binDir` defaults to `/usr/local/bin`, which is on the default PATH nearly everywhere but is read-only on Flatcar and similar images — use `/opt/bin` there. And this is the one thing the chart leaves on the node after `helm uninstall`; see [Uninstalling the Chart](#uninstalling-the-chart).

Set `hostCli.enabled=false` if the nodes already have a client you would rather not overwrite.

### Plugins registered on the node

Docker finds libnetwork and volume plugins by reading `/etc/docker/plugins`, `/usr/lib/docker/plugins` and `/usr/libexec/docker/plugins` — on the machine the daemon runs on, which here is the container. Anything registered on the node is therefore invisible: the daemon logs `Unable to locate plugin: <name>`, retries with backoff, and any network or volume using that driver fails.

Point `hostPluginDirs` at the directories the node actually uses and they are mounted read-only into the daemon. An OpenStack Kuryr install, for example, registers under `/usr/lib/docker/plugins`:

```console
--set hostPluginDirs[0]=/usr/lib/docker/plugins
```

The plugins' runtime sockets live under `/run/docker/plugins` and are already shared through `hostRunDir`; only these spec directories need adding.

### Prerequisites

- Kubernetes 1.23+ and Helm 3.8.0+
- containerd on the target nodes, with its socket reachable at `containerd.socket`
- Nodes labelled for the DaemonSet to select
- A cluster that permits privileged containers

## Installing the Chart

```console
helm install my-release oci://REGISTRY_NAME/REPOSITORY_NAME/dockerd \
  --set nodeSelector."docker\.io/daemon"=true
```

> Note: You need to substitute the placeholders `REGISTRY_NAME` and `REPOSITORY_NAME` with a reference to your Helm chart registry and repository.

## Uninstalling the Chart

```console
helm delete my-release
```

The socket disappears from the node and anything using it breaks immediately. Two things are **not** removed, because both are outside Helm's knowledge: `dataRoot` on each node, so images and build cache survive an uninstall and a reinstall; and the client binaries copied to `hostCli.binDir` and `hostCli.plugins.dir`, which are then a `docker` that points at a socket no longer there. Clean up both by hand if you mean to.

## Configuration and installation details

### Choose the nodes deliberately

An empty `nodeSelector` gives every schedulable node a privileged Docker daemon, and the chart says so at install time. A privileged container is root on the node it runs on, so this is a decision about which nodes you are willing to expose, not a convenience default. Label the ones that build images:

```console
kubectl label node worker-1 worker-2 docker.io/daemon=true
```

### The two paths that must line up

Most of what can go wrong here is a path mismatch, and both failures are quiet.

**`dataRoot` must be the same absolute path inside the pod and on the node.** With an external containerd, dockerd prepares the container rootfs under this directory and hands containerd an absolute path to it. Containerd resolves that path in the *node's* filesystem. If the two disagree, `docker run` fails with an error that mentions neither mounts nor paths. The chart mounts it at the same path on both sides with `mountPropagation: Bidirectional`, so the overlay mounts dockerd makes are visible to containerd too; keep it that way.

**`dockerSocket` must be under `hostRunDir`.** That mount is the only way the socket reaches the node. The default is `/run/docker.sock` rather than the more familiar `/var/run/docker.sock`, on purpose: on the node the two are the same file, because `/var/run` is a symlink to `/run`, so clients still find it where they expect — but writing it as `/var/run/...` in values would make the chart depend on that symlink existing *inside the container image*. If it does not, the daemon puts its socket in the container's own `/var/run`, nothing appears on the node, and the pod reports Ready the whole time. The chart refuses to render that configuration.

### Putting dataRoot on dedicated storage

The usual reason to move `dataRoot` is to keep image layers off the system disk. Do that by mounting the storage on the node at that path, not by handing the pod a PVC — see below for why a PVC cannot work here.

ZFS is a good fit, with one trap. Put `dataRoot` on a ZFS **filesystem** and Docker's overlay2 driver fails its feature detection there; the daemon then walks its priority list (`overlay2, fuse-overlayfs, btrfs, zfs, vfs`), skips the `zfs` driver because the Alpine-based image ships no `zfs` command, and silently lands on `vfs` — which copies every layer in full instead of sharing them. Builds keep working and get dramatically slower and larger.

Use a **zvol** instead, so overlay2 sees xfs or ext4 while ZFS does the work underneath:

```console
zfs create -V 200G -o compression=lz4 -o volblocksize=16k tank/docker
mkfs.xfs /dev/zvol/tank/docker
# /etc/fstab, or a systemd mount unit
/dev/zvol/tank/docker  /var/lib/docker  xfs  defaults,noatime  0 0
```

You keep compression, quotas and `zfs snapshot tank/docker@before-upgrade`, and the chart needs no change at all.

### Why not a PersistentVolumeClaim

Two independent reasons, and neither depends on the storage backend — CSI, local-path, OpenEBS ZFS-LocalPV all fail the same way.

**The path would no longer resolve.** A PVC is staged by the kubelet under `/var/lib/kubelet/pods/<uid>/volumes/...` and bind-mounted into the container at `dataRoot`. The node keeps nothing at that path. Since dockerd hands the node's containerd an absolute rootfs path that containerd resolves in the *node's* mount namespace, every `docker run` fails. This is the same constraint as the section above, seen from the other side.

**A DaemonSet cannot give each node its own claim.** There are no `volumeClaimTemplates` outside StatefulSets, so one PVC name in the pod template means one PVC for every node: `ReadWriteOnce` binds to a single node and leaves the rest Pending, and a `ReadWriteMany` volume would have several daemons writing one graph directory, which corrupts it. Generic ephemeral volumes do give a claim per pod, but they are deleted with the pod, which defeats the point of persisting a cache.

A PVC therefore requires abandoning the external containerd — moving to a nested one, where every path resolves inside the pod, which is a different chart with a different purpose.

### Images built here are not visible to the kubelet

This is the flip side of the namespace separation that lets one containerd serve both. `docker build` writes into the `moby` namespace; Pods are started from images in `k8s.io`. A Pod referring to an image you just built on that node will still try to pull it, and fail if it exists nowhere else.

Push to a registry, or move it across explicitly:

```console
docker save myimage | ctr -n k8s.io images import -
```

If your workflow is "build here, run as a Pod immediately", decide which of those two you are doing before you build a pipeline on top of it.

### daemon.json

Anything that is not one of the flags this chart owns goes in `daemonConfig`, which is rendered into a ConfigMap and mounted at `/etc/docker/daemon.json`:

```yaml
daemonConfig:
  insecure-registries:
    - registry.internal:5000
  registry-mirrors:
    - https://mirror.internal
  mtu: 1400
  log-opts:
    max-size: 100m
    max-file: "3"
```

dockerd refuses to start when a setting appears both as a flag and in that file, so the chart validates against the flags it passes (`containerd`, `containerd-namespace`, `containerd-plugins-namespace`, `data-root`, `hosts`) and tells you which key to move. Changing `daemonConfig` rolls the DaemonSet, because dockerd only reads the file at startup.

### Host networking

On by default and load-bearing. dockerd creates `docker0`, programs NAT and publishes container ports; in a pod network namespace all of that happens inside the pod, so `docker run -p 80:80` binds a port nothing on the node can reach and containers are invisible to everything outside. The chart warns rather than refuses if you turn it off, because there are niche reasons to — but a daemon that starts and behaves nothing like the node-level Docker it replaces is worse than one that does not start.

### What sharing a containerd costs

Restarting containerd on a node now disrupts both the kubelet's pods and Docker's containers. `ctr -n moby` and `ctr -n k8s.io` are separate worlds for listing and debugging, but they are one process, one set of plugins, one config file, and one blast radius. `containerd.namespace` may not be set to `k8s.io`; the chart rejects it, because the two managers would then each garbage-collect containers the other believes it owns.

### Security

The daemon container is privileged, which is root on the node — and unlike the usual privileged pod, its API is deliberately reachable: anything on the node that can open `/run/docker.sock` can start a privileged container, and from there the node's block devices and a writable `/proc/sys` are one step away. That is the same exposure a node-level Docker install has; delivering it as a pod does not add to it, but it does not reduce it either.

What that means in practice: the socket's file permissions are the access control (root-owned, `docker` group semantics if you set them up), so treat "who can reach this node's socket" the same way you would treat "who is in the `docker` group on this machine". The pod itself has no Kubernetes API access — no RBAC objects, `automountServiceAccountToken: false` — so a compromised daemon does not become a cluster-wide problem on its own.

The client install adds a second write path onto the node: `hostCli.binDir` is mounted read-write so the init container can place `docker` there, which means anything able to create pods with this chart's values can drop a binary into a directory on the node's PATH. It is not new exposure — the daemon container is already root on the node — but it is worth knowing about if `binDir` is somewhere shared. Set `hostCli.enabled=false` to remove that mount entirely.

If a privileged container is unacceptable on a node, that node should not get this chart. For image building specifically, BuildKit rootless needs no privilege at all.

### Resource requests and limits

The `resources` you set here bound the **daemon**, not the containers it starts — those are the node's containerd's children and are accounted outside this pod. So a limit here will not stop a build from eating the node; it only stops the daemon itself from misbehaving. Use `gc.cache` and node-level disk/eviction settings for the rest.

`autoscaling.vpa` is available and horizontal autoscaling is not: for a DaemonSet the replica count is the number of matching nodes. Note that `updateMode: Auto` resizes by evicting the pod, which takes the node's Docker socket away with it — `Off` or `Initial` is the safer setting here.

## Parameters

### Global parameters

| Name                                                  | Description                                                                                                                                                                                                                                                                                                                                                         | Value  |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| `global.imageRegistry`                                | Global Docker image registry                                                                                                                                                                                                                                                                                                                                        | `""`   |
| `global.imagePullSecrets`                             | Global Docker registry secret names as an array                                                                                                                                                                                                                                                                                                                     | `[]`   |
| `global.compatibility.openshift.adaptSecurityContext` | Adapt the securityContext sections of the deployment to make them compatible with Openshift restricted-v2 SCC: remove runAsUser, runAsGroup and fsGroup and let the platform use their allowed default IDs. Possible values: auto (apply if the detected running cluster is Openshift), force (perform the adaptation always), disabled (do not perform adaptation) | `auto` |

### Common parameters

| Name                     | Description                                                                             | Value          |
| ------------------------ | --------------------------------------------------------------------------------------- | -------------- |
| `kubeVersion`            | Override Kubernetes version                                                             | `""`           |
| `nameOverride`           | String to partially override common.names.fullname                                      | `""`           |
| `fullnameOverride`       | String to fully override common.names.fullname                                          | `""`           |
| `namespaceOverride`      | String to fully override common.names.namespace                                         | `""`           |
| `commonLabels`           | Labels to add to all deployed objects                                                   | `{}`           |
| `commonAnnotations`      | Annotations to add to all deployed objects                                              | `{}`           |
| `extraDeploy`            | Array of extra objects to deploy with the release                                       | `[]`           |
| `diagnosticMode.enabled` | Enable diagnostic mode (all probes will be disabled and the command will be overridden) | `false`        |
| `diagnosticMode.command` | Command to override all containers in the DaemonSet                                     | `["sleep"]`    |
| `diagnosticMode.args`    | Args to override all containers in the DaemonSet                                        | `["infinity"]` |

### Node targeting

| Name                | Description                                                                                                              | Value |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------ | ----- |
| `nodeSelector`      | Node labels for pod assignment. Empty targets every schedulable node                                                     | `{}`  |
| `tolerations`       | Tolerations for pod assignment                                                                                           | `[]`  |
| `affinity`          | Affinity for pod assignment. Overrides nodeSelector when both are set                                                    | `{}`  |
| `priorityClassName` | Priority class name. `system-node-critical` is defensible here: workloads on the node may depend on this socket existing | `""`  |

### Docker daemon parameters

| Name                         | Description                                                                                                                                       | Value                                   |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| `image.registry`             | Docker image registry                                                                                                                             | `REGISTRY_NAME`                         |
| `image.repository`           | Docker image repository                                                                                                                           | `REPOSITORY_NAME/docker`                |
| `image.tag`                  | Docker image tag. Must be a `-dind` tag                                                                                                           | `29.7.2-dind`                           |
| `image.digest`               | Docker image digest in the way sha256:aa.... Please note this parameter, if set, will override the tag                                            | `""`                                    |
| `image.pullPolicy`           | Docker image pull policy                                                                                                                          | `IfNotPresent`                          |
| `image.pullSecrets`          | Docker image pull secrets                                                                                                                         | `[]`                                    |
| `image.debug`                | Enable image debug mode. Passes `--debug` to dockerd                                                                                              | `false`                                 |
| `containerd.socket`          | Path on the node to the containerd socket the daemon should drive                                                                                 | `/run/containerd/containerd.sock`       |
| `containerd.namespace`       | containerd namespace for Docker's containers. Keep it away from `k8s.io`, which is the kubelet's                                                  | `moby`                                  |
| `containerd.pluginNamespace` | containerd namespace for Docker's plugins                                                                                                         | `plugins.moby`                          |
| `dataRoot`                   | Node directory for Docker's data (images, layers, volumes, build cache)                                                                           | `/var/lib/docker`                       |
| `dockerSocket`               | Node path for the Docker API socket. Must be under `hostRunDir`                                                                                   | `/run/docker.sock`                      |
| `hostRunDir`                 | Node directory holding runtime sockets, mounted so that both the containerd socket above and the published Docker socket are shared with the node | `/run`                                  |
| `hostCli.enabled`            | Copy the Docker client out of the daemon image onto the node                                                                                      | `true`                                  |
| `hostCli.binDir`             | Node directory to place the `docker` binary in. It must be on the node's PATH; use /opt/bin on Flatcar and other images whose /usr is read-only   | `/usr/local/bin`                        |
| `hostCli.plugins.buildx`     | Install the buildx CLI plugin on the node                                                                                                         | `false`                                 |
| `hostCli.plugins.compose`    | Install the compose CLI plugin on the node                                                                                                        | `false`                                 |
| `hostCli.plugins.dir`        | Node directory for CLI plugins. The client searches this path regardless of where its own binary sits                                             | `/usr/local/libexec/docker/cli-plugins` |
| `hostNetwork`                | Run the daemon in the node's network namespace                                                                                                    | `true`                                  |
| `hostPID`                    | Share the node's PID namespace. Required - the daemon resolves container PIDs that only exist there                                               | `true`                                  |
| `dnsPolicy`                  | Pod DNS policy. ClusterFirstWithHostNet is required for name resolution to work on host network                                                   | `ClusterFirstWithHostNet`               |
| `hostPluginDirs`             | Node directories holding plugin specs, mounted read-only into the daemon                                                                          | `[]`                                    |
| `daemonConfig`               | Contents of /etc/docker/daemon.json, as a map. The shipped default is in values.yaml, annotated setting by setting                                | `{...}`                                 |
| `extraArgs`                  | Extra flags appended to the `dockerd` command line                                                                                                | `[]`                                    |
| `command`                    | Override default container command. Skips the image entrypoint, and with it the iptables detection and docker-init injection it performs          | `[]`                                    |
| `args`                       | Override the whole dockerd argument list. Takes precedence over every flag this chart builds                                                      | `[]`                                    |
| `lifecycleHooks`             | for the Docker container(s) to automate configuration before or after startup                                                                     | `{}`                                    |
| `extraEnvVars`               | Array with extra environment variables to add to the Docker container                                                                             | `[]`                                    |
| `extraEnvVarsCM`             | Name of existing ConfigMap containing extra env vars                                                                                              | `""`                                    |
| `extraEnvVarsSecret`         | Name of existing Secret containing extra env vars                                                                                                 | `""`                                    |

### Garbage collector parameters

| Name                                                   | Description                                                                                                                                                                                                             | Value                                                                     |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `gc.enabled`                                           | Deploy the Drone garbage collector as a sidecar                                                                                                                                                                         | `true`                                                                    |
| `gc.image.registry`                                    | Drone GC image registry                                                                                                                                                                                                 | `REGISTRY_NAME`                                                           |
| `gc.image.repository`                                  | Drone GC image repository                                                                                                                                                                                               | `REPOSITORY_NAME/drone/gc`                                                |
| `gc.image.tag`                                         | Drone GC image tag. Upstream only ever published one semver tag (1.0.0, from 2019), so this points at `latest` - see the digest below                                                                                   | `latest`                                                                  |
| `gc.image.digest`                                      | Drone GC image digest in the way sha256:aa.... Please note this parameter, if set, will override the tag                                                                                                                | `sha256:92265ac9bdeb3a0b897c91d108089d3161695a04755808bf60766dfe15d41799` |
| `gc.image.pullPolicy`                                  | Drone GC image pull policy                                                                                                                                                                                              | `IfNotPresent`                                                            |
| `gc.image.pullSecrets`                                 | Drone GC image pull secrets                                                                                                                                                                                             | `[]`                                                                      |
| `gc.interval`                                          | How often to collect. Accepts a Go duration                                                                                                                                                                             | `5m`                                                                      |
| `gc.cache`                                             | Maximum image cache size. Images are evicted, least-frequently-used first, until the cache fits. Size it against the node's free disk, not against the whole disk                                                       | `5gb`                                                                     |
| `gc.ignoreImages`                                      | Images never removed, comma-separated. Globs are supported. Useful for base images every build starts from                                                                                                              | `""`                                                                      |
| `gc.ignoreContainers`                                  | Container names never removed, comma-separated. Globs are supported                                                                                                                                                     | `""`                                                                      |
| `gc.debug`                                             | Enable debug logging in the collector                                                                                                                                                                                   | `false`                                                                   |
| `gc.debugPretty`                                       | Pretty-print the collector logs                                                                                                                                                                                         | `false`                                                                   |
| `gc.debugColor`                                        | Colourise the collector logs                                                                                                                                                                                            | `false`                                                                   |
| `gc.extraEnvVars`                                      | Array with extra environment variables to add to the collector container                                                                                                                                                | `[]`                                                                      |
| `gc.extraVolumeMounts`                                 | Optionally specify extra list of additional volumeMounts for the collector container                                                                                                                                    | `[]`                                                                      |
| `gc.resourcesPreset`                                   | Set container resources according to one common preset (allowed values: none, nano, micro, small, medium, large, xlarge, 2xlarge). This is ignored if gc.resources is set (gc.resources is recommended for production). | `nano`                                                                    |
| `gc.resources`                                         | Set container requests and limits for different resources like CPU or memory (essential for production workloads)                                                                                                       | `{}`                                                                      |
| `gc.containerSecurityContext.enabled`                  | Enabled containers' Security Context                                                                                                                                                                                    | `true`                                                                    |
| `gc.containerSecurityContext.seLinuxOptions`           | Set SELinux options in container                                                                                                                                                                                        | `{}`                                                                      |
| `gc.containerSecurityContext.runAsUser`                | Set containers' Security Context runAsUser. Must be able to read the Docker socket, which is root-owned                                                                                                                 | `0`                                                                       |
| `gc.containerSecurityContext.runAsNonRoot`             | Set container's Security Context runAsNonRoot                                                                                                                                                                           | `false`                                                                   |
| `gc.containerSecurityContext.privileged`               | Set container's Security Context privileged                                                                                                                                                                             | `false`                                                                   |
| `gc.containerSecurityContext.readOnlyRootFilesystem`   | Set container's Security Context readOnlyRootFilesystem                                                                                                                                                                 | `true`                                                                    |
| `gc.containerSecurityContext.allowPrivilegeEscalation` | Set container's Security Context allowPrivilegeEscalation                                                                                                                                                               | `false`                                                                   |
| `gc.containerSecurityContext.capabilities.drop`        | List of capabilities to be dropped                                                                                                                                                                                      | `["ALL"]`                                                                 |
| `gc.containerSecurityContext.seccompProfile.type`      | Set container's Security Context seccomp profile                                                                                                                                                                        | `RuntimeDefault`                                                          |

### DaemonSet parameters

| Name                                                | Description                                                                                                                                                                                                       | Value           |
| --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------- |
| `updateStrategy.type`                               | DaemonSet update strategy                                                                                                                                                                                         | `RollingUpdate` |
| `updateStrategy.rollingUpdate.maxUnavailable`       | Maximum number of nodes updated at once. Each restart briefly removes the Docker socket from that node                                                                                                            | `1`             |
| `revisionHistoryLimit`                              | The number of old history to retain to allow rollback                                                                                                                                                             | `10`            |
| `hostAliases`                                       | Pod host aliases                                                                                                                                                                                                  | `[]`            |
| `podLabels`                                         | Extra labels for pods                                                                                                                                                                                             | `{}`            |
| `podAnnotations`                                    | Extra annotations for pods                                                                                                                                                                                        | `{}`            |
| `automountServiceAccountToken`                      | Mount Service Account token in pod. Nothing in this chart calls the Kubernetes API                                                                                                                                | `false`         |
| `terminationGracePeriodSeconds`                     | Grace period. On SIGTERM the daemon stops accepting work but lets running containers finish, so anything shorter than your longest build kills builds mid-flight                                                  | `3600`          |
| `podSecurityContext.enabled`                        | Enable pod security context                                                                                                                                                                                       | `true`          |
| `podSecurityContext.fsGroup`                        | Group ID for the pod's volumes                                                                                                                                                                                    | `0`             |
| `containerSecurityContext.enabled`                  | Enable container security context                                                                                                                                                                                 | `true`          |
| `containerSecurityContext.seLinuxOptions`           | Set SELinux options in container                                                                                                                                                                                  | `{}`            |
| `containerSecurityContext.runAsUser`                | User ID for the container                                                                                                                                                                                         | `0`             |
| `containerSecurityContext.runAsNonRoot`             | Run container as non-root                                                                                                                                                                                         | `false`         |
| `containerSecurityContext.privileged`               | Run container as privileged. The daemon does not start without it                                                                                                                                                 | `true`          |
| `containerSecurityContext.readOnlyRootFilesystem`   | Mount the container root filesystem read-only                                                                                                                                                                     | `false`         |
| `containerSecurityContext.allowPrivilegeEscalation` | Allow privilege escalation                                                                                                                                                                                        | `true`          |
| `resourcesPreset`                                   | Set container resources according to one common preset (allowed values: none, nano, micro, small, medium, large, xlarge, 2xlarge). This is ignored if resources is set (resources is recommended for production). | `medium`        |
| `resources`                                         | Set container requests and limits for different resources like CPU or memory (essential for production workloads)                                                                                                 | `{}`            |
| `startupProbe.enabled`                              | Enable startupProbe                                                                                                                                                                                               | `true`          |
| `startupProbe.initialDelaySeconds`                  | Initial delay seconds for startupProbe                                                                                                                                                                            | `10`            |
| `startupProbe.periodSeconds`                        | Period seconds for startupProbe                                                                                                                                                                                   | `10`            |
| `startupProbe.timeoutSeconds`                       | Timeout seconds for startupProbe                                                                                                                                                                                  | `10`            |
| `startupProbe.failureThreshold`                     | Failure threshold for startupProbe                                                                                                                                                                                | `30`            |
| `startupProbe.successThreshold`                     | Success threshold for startupProbe                                                                                                                                                                                | `1`             |
| `livenessProbe.enabled`                             | Enable livenessProbe                                                                                                                                                                                              | `true`          |
| `livenessProbe.initialDelaySeconds`                 | Initial delay seconds for livenessProbe                                                                                                                                                                           | `60`            |
| `livenessProbe.periodSeconds`                       | Period seconds for livenessProbe                                                                                                                                                                                  | `30`            |
| `livenessProbe.timeoutSeconds`                      | Timeout seconds for livenessProbe                                                                                                                                                                                 | `15`            |
| `livenessProbe.failureThreshold`                    | Failure threshold for livenessProbe                                                                                                                                                                               | `5`             |
| `livenessProbe.successThreshold`                    | Success threshold for livenessProbe                                                                                                                                                                               | `1`             |
| `readinessProbe.enabled`                            | Enable readinessProbe                                                                                                                                                                                             | `true`          |
| `readinessProbe.initialDelaySeconds`                | Initial delay seconds for readinessProbe                                                                                                                                                                          | `15`            |
| `readinessProbe.periodSeconds`                      | Period seconds for readinessProbe                                                                                                                                                                                 | `15`            |
| `readinessProbe.timeoutSeconds`                     | Timeout seconds for readinessProbe                                                                                                                                                                                | `10`            |
| `readinessProbe.failureThreshold`                   | Failure threshold for readinessProbe                                                                                                                                                                              | `5`             |
| `readinessProbe.successThreshold`                   | Success threshold for readinessProbe                                                                                                                                                                              | `1`             |
| `customStartupProbe`                                | Custom startupProbe that overrides the default one                                                                                                                                                                | `{}`            |
| `customLivenessProbe`                               | Custom livenessProbe that overrides the default one                                                                                                                                                               | `{}`            |
| `customReadinessProbe`                              | Custom readinessProbe that overrides the default one                                                                                                                                                              | `{}`            |
| `extraVolumes`                                      | Optionally specify extra list of additional volumes for the pods                                                                                                                                                  | `[]`            |
| `extraVolumeMounts`                                 | Optionally specify extra list of additional volumeMounts for the Docker container                                                                                                                                 | `[]`            |
| `initContainers`                                    | Add additional init containers to the pods                                                                                                                                                                        | `[]`            |
| `sidecars`                                          | Add additional sidecar containers to the pods                                                                                                                                                                     | `[]`            |
| `extraPodSpec`                                      | Optionally specify extra PodSpec                                                                                                                                                                                  | `{}`            |

### Other Parameters

| Name                                          | Description                                                                                                                                                            | Value   |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------- |
| `autoscaling.vpa.enabled`                     | Enable VPA                                                                                                                                                             | `false` |
| `autoscaling.vpa.annotations`                 | Annotations for VPA resource                                                                                                                                           | `{}`    |
| `autoscaling.vpa.controlledResources`         | VPA List of resources that the vertical pod autoscaler can control. Defaults to cpu and memory                                                                         | `[]`    |
| `autoscaling.vpa.maxAllowed`                  | VPA Max allowed resources for the pod                                                                                                                                  | `{}`    |
| `autoscaling.vpa.minAllowed`                  | VPA Min allowed resources for the pod                                                                                                                                  | `{}`    |
| `autoscaling.vpa.updatePolicy.updateMode`     | Autoscaling update policy Specifies whether recommended updates are applied when a Pod is started and whether recommended updates are applied during the life of a Pod | `Auto`  |
| `serviceAccount.create`                       | Enable creation of ServiceAccount for the pods                                                                                                                         | `true`  |
| `serviceAccount.name`                         | The name of the ServiceAccount to use. If not set and create is true, a name is generated using the common.names.fullname template                                     | `""`    |
| `serviceAccount.annotations`                  | Additional custom annotations for the ServiceAccount                                                                                                                   | `{}`    |
| `serviceAccount.automountServiceAccountToken` | Allows auto mount of ServiceAccountToken on the serviceAccount created                                                                                                 | `false` |

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example,

```console
helm install my-release \
  --set nodeSelector."docker\.io/daemon"=true \
  --set gc.cache=20gb \
  oci://REGISTRY_NAME/REPOSITORY_NAME/dockerd
```

Alternatively, a YAML file that specifies the values for the parameters can be provided while installing the chart. For example,

```console
helm install my-release -f values.yaml oci://REGISTRY_NAME/REPOSITORY_NAME/dockerd
```

## Troubleshooting

**`docker build` works but every `docker run` fails with `bind-mount /proc/<pid>/ns/net -> /var/run/docker/netns/...: no such file or directory`.** `hostPID` is off. The container's process was created by the node's containerd and lives in the node's PID namespace; the daemon cannot see that PID from a private one, and networking setup is where it notices. Set `hostPID=true` — it is required by this architecture, not a debugging aid.

**The daemon logs `Failed to find nft tool` at startup.** Harmless when `docker info` reports `firewall=iptables`, which is the default: the message comes from the daemon clearing rules belonging to the *nftables* firewall backend it is not using, and the `-dind` image ships only `iptables`. If you deliberately run the nftables backend, that image is not enough.

**Pods are Ready but `docker` on the node says "cannot connect to the Docker daemon".** The socket was created inside the container instead of on the node. Check that `dockerSocket` is under `hostRunDir` and that `hostRunDir` really is the node's runtime directory.

**`docker run` fails with an error about the rootfs or an unknown path.** `dataRoot` is not mounted at the same absolute path on both sides, so containerd cannot resolve the rootfs dockerd prepared. It must be the same path in the pod as on the node.

**The daemon crash-loops immediately with "directives are specified both as a flag and in the configuration file".** A key in `daemonConfig` collides with a flag. The chart validates the five it passes, so this means a key it does not know about — remove it from `daemonConfig` or from `extraArgs`.

**`docker` cannot see images the kubelet pulled, or vice versa.** Working as intended: different containerd namespaces. See the section above.

**Builds are killed during an upgrade.** `terminationGracePeriodSeconds` defaults to 3600 so in-flight work finishes; also raise `updateStrategy.rollingUpdate.maxUnavailable` only as far as you can afford nodes losing their socket at once.

**The pod will not start on a privileged-restricted cluster.** Bind its ServiceAccount to a policy that permits privileged containers (on OpenShift, the `privileged` SCC). Do not relax the namespace default instead.

### Diagnostic mode

To keep the pod running with the daemon stopped:

```console
helm upgrade my-release --set diagnosticMode.enabled=true oci://REGISTRY_NAME/REPOSITORY_NAME/dockerd
kubectl exec -it ds/my-release-dockerd -c dockerd -- sh
```

## License

Copyright &copy; 2026 Broadcom. The term "Broadcom" refers to Broadcom Inc. and/or its subsidiaries.

This chart began as a rewrite of [peterwwillis/helm-docker-in-docker](https://github.com/peterwwillis/helm-docker-in-docker) (BSD-2-Clause-Patent).

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

<http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.
