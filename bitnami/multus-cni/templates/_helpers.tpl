{{/*
Copyright Broadcom, Inc. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/*
Return the proper Multus CNI image name.
When `mode=thick` is selected and the configured `image.tag` does not already
contain the substring "thick", append a `-thick` suffix so the user does not
have to remember to switch tag families when flipping the mode.
*/}}
{{- define "multus-cni.image" -}}
{{- $imageRoot := deepCopy .Values.image -}}
{{- $tag := default "stable" $imageRoot.tag -}}
{{- if and (eq .Values.mode "thick") (not (contains "thick" $tag)) (not $imageRoot.digest) -}}
{{- $_ := set $imageRoot "tag" (printf "%s-thick" $tag) -}}
{{- end -}}
{{- include "common.images.image" (dict "imageRoot" $imageRoot "global" .Values.global) -}}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "multus-cni.imagePullSecrets" -}}
{{- include "common.images.pullSecrets" (dict "images" (list .Values.image) "global" .Values.global) -}}
{{- end -}}

{{/*
 Create the name of the service account to use
 */}}
{{- define "multus-cni.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{- default (include "common.names.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
    {{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Return the CNI binary directory
Note: Both containerd and CRI-O now use /opt/cni/bin as the default CNI plugin directory
*/}}
{{- define "multus-cni.cniBinDir" -}}
{{- default "/opt/cni/bin" .Values.hostCNIBinDir -}}
{{- end -}}
