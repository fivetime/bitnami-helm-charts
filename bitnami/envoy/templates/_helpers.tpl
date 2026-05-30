{{/*
Copyright Broadcom, Inc. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/*
Return the proper Envoy image name
*/}}
{{- define "envoy.image" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) -}}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "envoy.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.image) "context" $) -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "envoy.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{- default (include "common.names.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
    {{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Get the bootstrap configmap name
*/}}
{{- define "envoy.configMapName" -}}
{{- if .Values.existingConfigMap -}}
    {{- tpl .Values.existingConfigMap $ -}}
{{- else -}}
    {{- include "common.names.fullname" . -}}
{{- end -}}
{{- end -}}

{{/*
Envoy node id / cluster (default to release identifiers)
*/}}
{{- define "envoy.node.id" -}}
{{- default (include "common.names.fullname" .) .Values.node.id -}}
{{- end -}}
{{- define "envoy.node.cluster" -}}
{{- default (include "common.names.name" .) .Values.node.cluster -}}
{{- end -}}

{{/*
Validate values
*/}}
{{- define "envoy.validateValues" -}}
{{- $messages := list -}}
{{- if and (not .Values.existingConfigMap) (not .Values.controlPlane.host) -}}
{{- $messages = append $messages "envoy: controlPlane.host is required (the xDS control plane gRPC endpoint) unless existingConfigMap is set." -}}
{{- end -}}
{{- $messages = without $messages "" -}}
{{- $message := join "\n" $messages -}}
{{- if $message -}}
{{- printf "\nVALUES VALIDATION:\n%s" $message | fail -}}
{{- end -}}
{{- end -}}
