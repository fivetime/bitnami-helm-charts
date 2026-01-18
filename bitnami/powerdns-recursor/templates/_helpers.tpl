{{/*
Copyright Anthropic, Inc. or its affiliates. All Rights Reserved.
SPDX-License-Identifier: Apache-2.0
*/}}

{{/*
Return the proper PowerDNS Recursor image name
*/}}
{{- define "powerdns-recursor.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "powerdns-recursor.imagePullSecrets" -}}
{{- include "common.images.pullSecrets" (dict "images" (list .Values.image) "global" .Values.global) -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "powerdns-recursor.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Return the webserver secret name
*/}}
{{- define "powerdns-recursor.webserverSecretName" -}}
{{- if .Values.webserver.existingSecret -}}
    {{- printf "%s" .Values.webserver.existingSecret -}}
{{- else -}}
    {{- printf "%s-webserver" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Check if Lua configuration is enabled (config.lua needed)
Returns "true" if any feature requiring config.lua is enabled
*/}}
{{- define "powerdns-recursor.luaConfigEnabled" -}}
{{- if or .Values.lua.configEnabled .Values.trustAnchors.enabled .Values.trustAnchors.negative .Values.rpz.enabled (and .Values.zoneToCache .Values.zoneToCache.enabled .Values.zoneToCache.zones) -}}
true
{{- end -}}
{{- end -}}

{{/*
Check if Lua DNS script is enabled (dns.lua needed)
Returns "true" if any feature requiring dns.lua is enabled
*/}}
{{- define "powerdns-recursor.luaDnsEnabled" -}}
{{- if or .Values.lua.dnsEnabled .Values.trustAnchors.enabled -}}
true
{{- end -}}
{{- end -}}

{{/*
Check if any Lua file is needed
Returns "true" if any Lua feature is enabled
*/}}
{{- define "powerdns-recursor.luaEnabled" -}}
{{- if or (include "powerdns-recursor.luaConfigEnabled" .) (include "powerdns-recursor.luaDnsEnabled" .) -}}
true
{{- end -}}
{{- end -}}

{{/*
Compile all warnings into a single message.
*/}}
{{- define "powerdns-recursor.validateValues" -}}
{{- $messages := list -}}
{{- $messages := append $messages (include "powerdns-recursor.validateValues.replicaCount" .) -}}
{{- $messages := without $messages "" -}}
{{- $message := join "\n" $messages -}}

{{- if $message -}}
{{-   printf "\nVALUES VALIDATION:\n%s" $message -}}
{{- end -}}
{{- end -}}

{{/*
Validate values of PowerDNS Recursor - replicaCount
*/}}
{{- define "powerdns-recursor.validateValues.replicaCount" -}}
{{- if and .Values.autoscaling.hpa.enabled (not (eq (int .Values.replicaCount) 0)) -}}
powerdns-recursor: replicaCount
    When HPA is enabled, replicaCount is ignored. Set replicaCount to 0 or disable HPA.
{{- end -}}
{{- end -}}

{{/*
Return podAnnotations with configmap hash
*/}}
{{- define "powerdns-recursor.podAnnotations" -}}
{{- if .Values.podAnnotations }}
{{- include "common.tplvalues.render" (dict "value" .Values.podAnnotations "context" $) }}
{{- end }}
checksum/config: {{ include (print $.Template.BasePath "/configmap-etc.yaml") . | sha256sum }}
{{- if include "powerdns-recursor.luaEnabled" . }}
checksum/lua: {{ include (print $.Template.BasePath "/configmap-lua.yaml") . | sha256sum }}
{{- end }}
{{- end -}}
