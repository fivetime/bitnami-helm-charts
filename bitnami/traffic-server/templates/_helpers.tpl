{{/*
Copyright Broadcom, Inc. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/* vim: set filetype=mustache: */}}
{{/*
Return the proper Apache Traffic Server image name
*/}}
{{- define "trafficserver.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "trafficserver.imagePullSecrets" -}}
{{ include "common.images.renderPullSecrets" (dict "images" (list .Values.image) "context" $) }}
{{- end -}}

{{/*
Return the custom records.yaml configmap name
*/}}
{{- define "trafficserver.recordsConfigmapName" -}}
{{- if .Values.existingRecordsConfigmap -}}
    {{- printf "%s" (tpl .Values.existingRecordsConfigmap $) -}}
{{- else -}}
    {{- printf "%s-records" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the custom remap.config configmap name
*/}}
{{- define "trafficserver.remapConfigmapName" -}}
{{- if .Values.existingRemapConfigmap -}}
    {{- printf "%s" (tpl .Values.existingRemapConfigmap $) -}}
{{- else -}}
    {{- printf "%s-remap" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the custom plugin.config configmap name
*/}}
{{- define "trafficserver.pluginConfigmapName" -}}
{{- if .Values.existingPluginConfigmap -}}
    {{- printf "%s" (tpl .Values.existingPluginConfigmap $) -}}
{{- else -}}
    {{- printf "%s-plugin" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the custom storage.config configmap name
*/}}
{{- define "trafficserver.storageConfigmapName" -}}
{{- if .Values.existingStorageConfigmap -}}
    {{- printf "%s" (tpl .Values.existingStorageConfigmap $) -}}
{{- else -}}
    {{- printf "%s-storage" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the startup script configmap name
*/}}
{{- define "trafficserver.startupScriptConfigmapName" -}}
{{- printf "%s-startup" (include "common.names.fullname" .) -}}
{{- end -}}

{{/*
Return the ip_allow.yaml configmap name
*/}}
{{- define "trafficserver.ipAllowConfigmapName" -}}
{{- if .Values.existingIpAllowConfigmap -}}
    {{- printf "%s" (tpl .Values.existingIpAllowConfigmap $) -}}
{{- else -}}
    {{- printf "%s-ip-allow" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the sni.yaml configmap name
*/}}
{{- define "trafficserver.sniConfigmapName" -}}
{{- if .Values.existingSniConfigmap -}}
    {{- printf "%s" (tpl .Values.existingSniConfigmap $) -}}
{{- else -}}
    {{- printf "%s-sni" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the logging.yaml configmap name
*/}}
{{- define "trafficserver.loggingConfigmapName" -}}
{{- if .Values.existingLoggingConfigmap -}}
    {{- printf "%s" (tpl .Values.existingLoggingConfigmap $) -}}
{{- else -}}
    {{- printf "%s-logging" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the cache.config configmap name
*/}}
{{- define "trafficserver.cacheConfigmapName" -}}
{{- if .Values.existingCacheConfigmap -}}
    {{- printf "%s" (tpl .Values.existingCacheConfigmap $) -}}
{{- else -}}
    {{- printf "%s-cache" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the parent.config configmap name
*/}}
{{- define "trafficserver.parentConfigmapName" -}}
{{- if .Values.existingParentConfigmap -}}
    {{- printf "%s" (tpl .Values.existingParentConfigmap $) -}}
{{- else -}}
    {{- printf "%s-parent" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the strategies.yaml configmap name
*/}}
{{- define "trafficserver.strategiesConfigmapName" -}}
{{- if .Values.existingStrategiesConfigmap -}}
    {{- printf "%s" (tpl .Values.existingStrategiesConfigmap $) -}}
{{- else -}}
    {{- printf "%s-strategies" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the ssl_multicert.config configmap name
*/}}
{{- define "trafficserver.sslMulticertConfigmapName" -}}
{{- if .Values.existingSslMulticertConfigmap -}}
    {{- printf "%s" (tpl .Values.existingSslMulticertConfigmap $) -}}
{{- else -}}
    {{- printf "%s-ssl-multicert" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the hosting.config configmap name
*/}}
{{- define "trafficserver.hostingConfigmapName" -}}
{{- if .Values.existingHostingConfigmap -}}
    {{- printf "%s" (tpl .Values.existingHostingConfigmap $) -}}
{{- else -}}
    {{- printf "%s-hosting" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the volume.config configmap name
*/}}
{{- define "trafficserver.volumeConfigmapName" -}}
{{- if .Values.existingVolumeConfigmap -}}
    {{- printf "%s" (tpl .Values.existingVolumeConfigmap $) -}}
{{- else -}}
    {{- printf "%s-volume" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the splitdns.config configmap name
*/}}
{{- define "trafficserver.splitdnsConfigmapName" -}}
{{- if .Values.existingSplitdnsConfigmap -}}
    {{- printf "%s" (tpl .Values.existingSplitdnsConfigmap $) -}}
{{- else -}}
    {{- printf "%s-splitdns" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the socks.config configmap name
*/}}
{{- define "trafficserver.socksConfigmapName" -}}
{{- if .Values.existingSocksConfigmap -}}
    {{- printf "%s" (tpl .Values.existingSocksConfigmap $) -}}
{{- else -}}
    {{- printf "%s-socks" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the jsonrpc.yaml configmap name
*/}}
{{- define "trafficserver.jsonrpcConfigmapName" -}}
{{- if .Values.existingJsonrpcConfigmap -}}
    {{- printf "%s" (tpl .Values.existingJsonrpcConfigmap $) -}}
{{- else -}}
    {{- printf "%s-jsonrpc" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "trafficserver.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Compile all warnings into a single message, and call fail.
*/}}
{{- define "trafficserver.validateValues" -}}
{{- $messages := list -}}
{{- $messages := append $messages (include "trafficserver.validateValues.extraVolumes" .) -}}
{{- $messages := without $messages "" -}}
{{- $message := join "\n" $messages -}}

{{- if $message -}}
{{-   printf "\nVALUES VALIDATION:\n%s" $message | fail -}}
{{- end -}}
{{- end -}}

{{/* Validate values of Apache Traffic Server - Incorrect extra volume settings */}}
{{- define "trafficserver.validateValues.extraVolumes" -}}
{{- if and (.Values.extraVolumes) (not (or .Values.extraVolumeMounts .Values.sidecars)) -}}
trafficserver: missing-extra-volume-mounts
    You specified extra volumes but not mount points for them. Please set
    the extraVolumeMounts value or use them in sidecars
{{- end -}}
{{- end -}}
