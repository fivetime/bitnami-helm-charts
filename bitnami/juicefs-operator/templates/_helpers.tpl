{{/*
Copyright Broadcom, Inc. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/* vim: set filetype=mustache: */}}

{{/*
Return the proper operator controller-manager image name
*/}}
{{- define "juicefs-operator.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper CSI dashboard image name
*/}}
{{- define "juicefs-operator.dashboard.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.dashboard.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "juicefs-operator.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.image .Values.dashboard.image) "context" $) -}}
{{- end -}}

{{/*
Return the operator service account name.
*/}}
{{- define "juicefs-operator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{- default (include "common.names.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
    {{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Return the CSI dashboard fullname.
*/}}
{{- define "juicefs-operator.dashboard.fullname" -}}
{{- printf "%s-dashboard" (include "common.names.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
