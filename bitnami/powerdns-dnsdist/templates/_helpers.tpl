{{/*
Copyright Simon Li
SPDX-License-Identifier: Apache-2.0
*/}}

{{/*
Return the proper DNSdist image name
*/}}
{{- define "dnsdist.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "dnsdist.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.image) "context" $) -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "dnsdist.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Return the DNSdist configuration Secret name
*/}}
{{- define "dnsdist.secretName" -}}
{{- printf "%s-secret" (include "common.names.fullname" .) -}}
{{- end -}}

{{/*
Return the DNSdist TLS Secret name
*/}}
{{- define "dnsdist.tlsSecretName" -}}
{{- if .Values.tls.existingSecret -}}
    {{ .Values.tls.existingSecret }}
{{- else -}}
    {{ printf "%s-tls" (include "common.names.fullname" .) }}
{{- end -}}
{{- end -}}

{{/*
Return true if TLS is enabled
*/}}
{{- define "dnsdist.tlsEnabled" -}}
{{- if or .Values.listeners.dot.enabled .Values.listeners.doh.enabled .Values.listeners.doq.enabled .Values.listeners.doh3.enabled -}}
true
{{- end -}}
{{- end -}}

{{/*
Return true if TLS secret should be created
*/}}
{{- define "dnsdist.createTlsSecret" -}}
{{- if and (include "dnsdist.tlsEnabled" .) (not .Values.tls.existingSecret) .Values.tls.cert .Values.tls.key -}}
true
{{- end -}}
{{- end -}}

{{/*
Compile all warnings into a single message
*/}}
{{- define "dnsdist.validateValues" -}}
{{- $messages := list -}}
{{- $messages = append $messages (include "dnsdist.validateValues.backends" .) -}}
{{- $messages = append $messages (include "dnsdist.validateValues.tls" .) -}}
{{- $messages = without $messages "" -}}
{{- $message := join "\n" $messages -}}
{{- if $message -}}
{{- printf "\nVALUES VALIDATION:\n%s" $message | fail -}}
{{- end -}}
{{- end -}}

{{/*
Validate at least one backend is enabled
*/}}
{{- define "dnsdist.validateValues.backends" -}}
{{- if not (or .Values.backends.recursor.enabled .Values.backends.auth.enabled .Values.backends.external.enabled) -}}
dnsdist: At least one backend must be enabled (backends.recursor, backends.auth, or backends.external)
{{- end -}}
{{- end -}}

{{/*
Validate TLS configuration
*/}}
{{- define "dnsdist.validateValues.tls" -}}
{{- if include "dnsdist.tlsEnabled" . -}}
{{- if and (not .Values.tls.existingSecret) (not (and .Values.tls.cert .Values.tls.key)) -}}
dnsdist: TLS is enabled but no certificate provided. Set tls.existingSecret or both tls.cert and tls.key
{{- end -}}
{{- end -}}
{{- end -}}
