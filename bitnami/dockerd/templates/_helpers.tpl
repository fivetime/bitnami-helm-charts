{{- /*
Copyright Broadcom, Inc. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/*
Return the proper Docker image name
*/}}
{{- define "dockerd.image" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) -}}
{{- end -}}

{{/*
Return the proper Drone garbage collector image name
*/}}
{{- define "dockerd.gc.image" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.gc.image "global" .Values.global) -}}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "dockerd.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.image .Values.gc.image) "context" $) -}}
{{- end -}}

{{/*
Create the name of the ServiceAccount to use
*/}}
{{- define "dockerd.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Name of the daemon.json ConfigMap
*/}}
{{- define "dockerd.configMapName" -}}
{{- if .Values.existingConfigmap -}}
{{- include "common.tplvalues.render" (dict "value" .Values.existingConfigmap "context" $) -}}
{{- else -}}
{{- printf "%s-daemon-config" (include "common.names.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Whether a daemon.json is mounted at all, from either source.
*/}}
{{- define "dockerd.hasDaemonConfig" -}}
{{- if or .Values.daemonConfig .Values.existingConfigmap -}}true{{- end -}}
{{- end -}}

{{/*
The dockerd command line.

The first element is the literal string `dockerd`, and that is deliberate rather than
incidental. The image entrypoint builds its own argument list only when it is called with
no arguments or with a first argument starting with a dash:

    if [ "$#" -eq 0 ] || [ "${1#-}" != "$1" ]; then
        set -- dockerd --host=... --host=tcp://0.0.0.0:2375 "$@"
    fi
    if [ "$1" = 'dockerd' ]; then
        ... pid cleanup, iptables legacy/nft detection, docker-init as pid 1 ...
    fi

Passing flags first would therefore add an unauthenticated TCP listener on every node -
on host network, at that. Naming `dockerd` explicitly skips that block while still
getting the second one, which is the part worth keeping.
*/}}
{{- define "dockerd.args" -}}
{{- if .Values.args -}}
{{- toYaml .Values.args -}}
{{- else -}}
{{- $args := list "dockerd" -}}
{{- $args = append $args (printf "--host=unix://%s" .Values.dockerSocket) -}}
{{- $args = append $args (printf "--containerd=%s" .Values.containerd.socket) -}}
{{- $args = append $args (printf "--containerd-namespace=%s" .Values.containerd.namespace) -}}
{{- $args = append $args (printf "--containerd-plugins-namespace=%s" .Values.containerd.pluginNamespace) -}}
{{- $args = append $args (printf "--data-root=%s" .Values.dataRoot) -}}
{{- if .Values.image.debug -}}
{{- $args = append $args "--debug" -}}
{{- end -}}
{{- range .Values.extraArgs -}}
{{- $args = append $args (tpl . $) -}}
{{- end -}}
{{- toYaml $args -}}
{{- end -}}
{{- end -}}

{{/*
Directory part of the published socket path, so it can be created on the node.
*/}}
{{- define "dockerd.socketDir" -}}
{{- .Values.dockerSocket | dir -}}
{{- end -}}

{{/*
Environment shared by the daemon and anything that talks to it
*/}}
{{- define "dockerd.clientEnv" -}}
- name: DOCKER_HOST
  value: {{ printf "unix://%s" .Values.dockerSocket | quote }}
{{- end -}}

{{- define "dockerd.envFrom" -}}
{{- if or .Values.extraEnvVarsCM .Values.extraEnvVarsSecret }}
envFrom:
  {{- if .Values.extraEnvVarsCM }}
  - configMapRef:
      name: {{ include "common.tplvalues.render" (dict "value" .Values.extraEnvVarsCM "context" $) }}
  {{- end }}
  {{- if .Values.extraEnvVarsSecret }}
  - secretRef:
      name: {{ include "common.tplvalues.render" (dict "value" .Values.extraEnvVarsSecret "context" $) }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
Validate the values that cannot be defaulted or recovered from
*/}}
{{- define "dockerd.validateValues" -}}
{{- $messages := list -}}
{{- $messages = append $messages (include "dockerd.validateValues.containerdSocket" .) -}}
{{- $messages = append $messages (include "dockerd.validateValues.daemonConfig" .) -}}
{{- $messages = append $messages (include "dockerd.validateValues.paths" .) -}}
{{- $messages = without $messages "" -}}
{{- $message := join "\n" $messages -}}
{{- if $message -}}
{{- printf "\nVALUES VALIDATION:\n%s" $message | fail -}}
{{- end -}}
{{- end -}}

{{- define "dockerd.validateValues.containerdSocket" -}}
{{- if not .Values.containerd.socket -}}
dockerd: containerd.socket is required.

    This chart runs Docker as a control plane over the containerd that is already on the
    node. Without that socket there is nothing for the daemon to drive - and it will not
    fall back to starting its own, because this chart never asks it to.

      --set containerd.socket=/run/containerd/containerd.sock
{{- else if eq .Values.containerd.namespace "k8s.io" -}}
dockerd: containerd.namespace must not be `k8s.io`.

    That namespace belongs to the kubelet. Putting Docker's containers in it means Docker
    and the kubelet each manage containers the other believes it owns; the usual first
    symptom is the kubelet garbage-collecting a build mid-run, or Docker deleting a
    running Pod's container as an unused one.
{{- end -}}
{{- end -}}

{{- define "dockerd.validateValues.daemonConfig" -}}
{{- if and .Values.daemonConfig (not (kindIs "map" .Values.daemonConfig)) -}}
dockerd: daemonConfig must be a map, got {{ kindOf .Values.daemonConfig }}.

    If you were clearing it from the command line, note that `--set daemonConfig={}` sets an
    empty ARRAY - `{}` is Helm's list literal syntax. Use `--set daemonConfig=null`, or an
    empty map in a values file.
{{- else -}}
{{- $cfg := .Values.daemonConfig | default dict -}}
{{- $conflicts := list "containerd" "containerd-namespace" "containerd-plugins-namespace" "data-root" "hosts" -}}
{{- $found := list -}}
{{- range $k := $conflicts -}}
{{- if hasKey $cfg $k -}}
{{- $found = append $found $k -}}
{{- end -}}
{{- end -}}
{{- if $found -}}
dockerd: daemonConfig sets keys this chart already passes as flags: {{ join ", " $found }}.

    dockerd refuses to start when a setting is given both ways - it exits with
    "unable to configure the Docker daemon ... the following directives are specified both
    as a flag and in the configuration file", and the pod crash-loops before it logs
    anything more useful.

    Set these through their own values (containerd.socket, containerd.namespace,
    containerd.pluginNamespace, dataRoot, dockerSocket) and keep daemonConfig for the rest.
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "dockerd.validateValues.paths" -}}
{{- if not (hasPrefix .Values.hostRunDir .Values.dockerSocket) -}}
dockerd: dockerSocket ({{ .Values.dockerSocket }}) is not under hostRunDir ({{ .Values.hostRunDir }}).

    The socket only reaches the node through that mount. Anywhere else and the daemon
    creates it inside the container, where nothing on the node can see it - and because the
    daemon itself is perfectly healthy, the pod goes Ready and the failure only shows up
    when someone on the node runs `docker` and gets "cannot connect to the Docker daemon".

    Note that `/var/run/...` counts as outside `/run` here even though the node treats them
    as the same directory, because the path is resolved inside the container first.
{{- else if not (hasPrefix .Values.hostRunDir .Values.containerd.socket) -}}
dockerd: containerd.socket ({{ .Values.containerd.socket }}) is not under hostRunDir ({{ .Values.hostRunDir }}).

    The containerd socket reaches the pod through the hostRunDir mount. If it lives
    somewhere else, either point hostRunDir at the directory that contains it, or add your
    own hostPath mount through extraVolumes/extraVolumeMounts.
{{- end -}}
{{- end -}}

{{/*
Warnings that do not justify refusing to render
*/}}
{{- define "dockerd.checkPrivileged" -}}
{{- if and .Values.containerSecurityContext.enabled (not .Values.containerSecurityContext.privileged) }}

⚠ WARNING: containerSecurityContext.privileged is false.

    Even as a control plane, the daemon programs iptables, mounts overlay filesystems and
    prepares the rootfs that the node's containerd runs. On a stock runtime it will not
    start without a privileged container.
{{- end -}}
{{- end -}}

{{- define "dockerd.checkExistingConfigmap" -}}
{{- if .Values.existingConfigmap }}

⚠ NOTE: daemon.json comes from the ConfigMap {{ .Values.existingConfigmap }}, which this chart does not own.

    Two things follow from that. The daemons will not roll when you edit it - Helm cannot
    see inside a ConfigMap it does not render, so there is no checksum to change. After
    every edit:

        kubectl rollout restart daemonset/{{ include "common.names.fullname" . }} -n {{ include "common.names.namespace" . }}

    And its contents are not validated against the flags this chart passes ({{ join ", " (list "containerd" "containerd-namespace" "containerd-plugins-namespace" "data-root" "hosts") }}).
    dockerd refuses to start if a setting appears in both places.
{{- if .Values.daemonConfig }}

    daemonConfig is set as well and is being ignored.
{{- end }}
{{- end -}}
{{- end -}}

{{- define "dockerd.checkHostPID" -}}
{{- if not .Values.hostPID }}

⚠ WARNING: hostPID is disabled.

    Containers are started by the node's containerd, so their processes live in the node's
    PID namespace. To wire up networking the daemon bind-mounts /proc/<pid>/ns/net, and
    without the node's PID namespace that path is not visible to it. The daemon will start
    and `docker build` will work, but every `docker run` fails with:

        bind-mount /proc/<pid>/ns/net -> /var/run/docker/netns/...: no such file or directory
{{- end -}}
{{- end -}}

{{- define "dockerd.checkHostNetwork" -}}
{{- if not .Values.hostNetwork }}

⚠ WARNING: hostNetwork is disabled.

    The daemon will create docker0, program NAT and publish container ports inside the
    pod's network namespace instead of the node's. It starts, and then behaves nothing
    like the node-level Docker it is replacing: `docker run -p` binds a port nothing on the
    node can reach, and containers are invisible to everything outside this pod.
{{- end -}}
{{- end -}}

{{- define "dockerd.checkStorageDriver" -}}
{{- $sd := get (.Values.daemonConfig | default dict) "storage-driver" | default "" -}}
{{- if or (eq $sd "zfs") (eq $sd "btrfs") }}

⚠ WARNING: storage-driver is set to `{{ $sd }}`, which needs userspace tools the image does not ship.

    The {{ $sd }} graph driver refuses to initialise without the `{{ $sd }}` command in PATH
    (and, for zfs, an openable /dev/zfs). The official docker:*-dind image is Alpine-based
    and carries neither, so the driver is skipped.

    What makes this worth a warning rather than a crash: the daemon does NOT fail. It walks
    its priority list - overlay2, fuse-overlayfs, btrfs, zfs, vfs - and lands on `vfs`, which
    copies every layer in full instead of sharing them. Builds still work, then take
    minutes instead of seconds and fill the disk.

    Either build an image that includes the tools, or put {{ .Values.dataRoot }} on a
    filesystem overlay2 supports - a zvol formatted xfs/ext4 gives you ZFS underneath while
    keeping overlay2 on top.
{{- end -}}
{{- end -}}

{{- define "dockerd.checkNodeSelector" -}}
{{- if not .Values.nodeSelector }}

⚠ WARNING: nodeSelector is empty, so EVERY schedulable node gets a privileged Docker daemon.

    A privileged container is root on the node it runs on. Delivering one to the whole
    cluster is a much larger decision than delivering it to the nodes that build images.

    Label the nodes that need it and select on that label:

        kubectl label node <node> docker.io/daemon=true
        helm upgrade ... --set nodeSelector."docker\.io/daemon"=true
{{- end -}}
{{- end -}}
