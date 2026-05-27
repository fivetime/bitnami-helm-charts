{{/*
Copyright Broadcom, Inc. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/*
Return the proper ovs-cni image name
*/}}
{{- define "ovs-cni.image" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) -}}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "ovs-cni.imagePullSecrets" -}}
{{- include "common.images.pullSecrets" (dict "images" (list .Values.image) "global" .Values.global) -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "ovs-cni.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{- default (include "common.names.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
    {{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Return the CNI binary directory on the host
Note: Both containerd and CRI-O default to /opt/cni/bin
*/}}
{{- define "ovs-cni.cniBinDir" -}}
{{- default "/opt/cni/bin" .Values.hostCNIBinDir -}}
{{- end -}}

{{/*
Render the shell command used by the init container to install ovs-cni binaries
on the host. Each plugin toggle in `.Values.plugins` decides whether the
corresponding binary is copied. Always at least one of the three must be true,
otherwise the init container would be a no-op and the chart would be useless.
*/}}
{{- define "ovs-cni.installCommand" -}}
{{- $dst := printf "%s%s" .Values.CNIMountPath (include "ovs-cni.cniBinDir" .) -}}
{{- $cmds := list -}}
{{- if .Values.plugins.ovs -}}
{{- $cmds = append $cmds (printf "cp /ovs %s/ovs" $dst) -}}
{{- end -}}
{{- if .Values.plugins.mirrorProducer -}}
{{- $cmds = append $cmds (printf "cp /ovs-mirror-producer %s/ovs-mirror-producer" $dst) -}}
{{- end -}}
{{- if .Values.plugins.mirrorConsumer -}}
{{- $cmds = append $cmds (printf "cp /ovs-mirror-consumer %s/ovs-mirror-consumer" $dst) -}}
{{- end -}}
{{- if not $cmds -}}
{{- fail "ovs-cni: at least one of plugins.ovs / plugins.mirrorProducer / plugins.mirrorConsumer must be enabled" -}}
{{- end -}}
{{- join " && " $cmds -}}
{{- end -}}

{{/*
Render the `-ovs-socket` flag value passed to the marker.
unix:/path or tcp:host:port (matches cmd/marker/main.go parseOvsSocket)
*/}}
{{- define "ovs-cni.markerOvsSocketFlag" -}}
{{- if eq .Values.ovsSocket.type "tcp" -}}
{{- if not .Values.ovsSocket.host -}}
{{- fail "ovs-cni: ovsSocket.host must be set when ovsSocket.type=tcp" -}}
{{- end -}}
tcp:{{ .Values.ovsSocket.host }}:{{ .Values.ovsSocket.port }}
{{- else -}}
unix:/host{{ .Values.ovsSocket.path }}
{{- end -}}
{{- end -}}

{{/*
Compile-time validation
*/}}
{{- define "ovs-cni.validateValues" -}}
{{- $messages := list -}}
{{- if and (ne .Values.ovsSocket.type "unix") (ne .Values.ovsSocket.type "tcp") -}}
{{- $messages = append $messages "ovs-cni: ovsSocket.type must be either 'unix' or 'tcp'" -}}
{{- end -}}
{{- if $messages -}}
{{- printf "\n%s" (join "\n" $messages) | fail -}}
{{- end -}}
{{- end -}}
