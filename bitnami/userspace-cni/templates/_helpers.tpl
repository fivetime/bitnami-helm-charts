{{/*
Copyright Broadcom, Inc. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/*
Return the proper userspace-cni image name
*/}}
{{- define "userspace-cni.image" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) -}}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "userspace-cni.imagePullSecrets" -}}
{{- include "common.images.pullSecrets" (dict "images" (list .Values.image) "global" .Values.global) -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "userspace-cni.serviceAccountName" -}}
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
{{- define "userspace-cni.cniBinDir" -}}
{{- default "/opt/cni/bin" .Values.hostCNIBinDir -}}
{{- end -}}

{{/*
Render the shell command used by the init container to install the userspace CNI
binary on the host. The image ships a single binary at /userspace.
*/}}
{{- define "userspace-cni.installCommand" -}}
{{- $dst := printf "%s%s" .Values.CNIMountPath (include "userspace-cni.cniBinDir" .) -}}
cp -f /userspace {{ $dst }}/userspace
{{- end -}}
