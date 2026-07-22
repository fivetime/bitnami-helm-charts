{{/*
Copyright Broadcom, Inc. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/* vim: set filetype=mustache: */}}

{{/*
CSI driver name (the CSIDriver object name applications reference).
*/}}
{{- define "juicefs-csi.driverName" -}}
{{- default "csi.juicefs.com" .Values.driverName -}}
{{- end -}}

{{/*
Return the proper CSI plugin image name (controller + node juicefs-plugin).
*/}}
{{- define "juicefs-csi.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/*
Render a sidecar image (livenessprobe, node-driver-registrar, provisioner, resizer, snapshotter).
*/}}
{{- define "juicefs-csi.sidecarImage" -}}
{{ include "common.images.image" (dict "imageRoot" .root "global" .global) }}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "juicefs-csi.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.image .Values.sidecars.livenessProbeImage .Values.sidecars.nodeDriverRegistrarImage .Values.sidecars.csiProvisionerImage .Values.sidecars.csiResizerImage) "context" $) -}}
{{- end -}}

{{/*
Controller service account name.
*/}}
{{- define "juicefs-csi.controller.serviceAccountName" -}}
{{- if .Values.serviceAccount.controller.create -}}
    {{- default (printf "%s-controller" (include "common.names.fullname" .)) .Values.serviceAccount.controller.name -}}
{{- else -}}
    {{- default "default" .Values.serviceAccount.controller.name -}}
{{- end -}}
{{- end -}}

{{/*
Node service account name.
*/}}
{{- define "juicefs-csi.node.serviceAccountName" -}}
{{- if .Values.serviceAccount.node.create -}}
    {{- default (printf "%s-node" (include "common.names.fullname" .)) .Values.serviceAccount.node.name -}}
{{- else -}}
    {{- default "default" .Values.serviceAccount.node.name -}}
{{- end -}}
{{- end -}}

{{/*
Validate the mount mode: this Bitnami port supports mountpod (production
default) and process modes. sidecar/serverless require the mutating webhook
and its TLS certificate management, which is out of scope for this chart.
*/}}
{{- define "juicefs-csi.validateValues" -}}
{{- $allowed := list "mountpod" "process" -}}
{{- if not (has .Values.mountMode $allowed) -}}
{{- printf "\nVALUES VALIDATION:\njuicefs-csi-driver: mountMode\n    This chart supports mountMode \"mountpod\" (recommended) and \"process\".\n    sidecar/serverless modes need the mutating webhook and TLS certs, which\n    are not included in this Bitnami port. Got: %q\n" .Values.mountMode | fail -}}
{{- end -}}
{{- end -}}
