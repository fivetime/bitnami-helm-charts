{{/*
Copyright Broadcom, Inc. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/* vim: set filetype=mustache: */}}

{{/*
Return the proper JuiceFS gateway image name
*/}}
{{- define "juicefs-s3-gateway.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "juicefs-s3-gateway.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.image) "context" $) -}}
{{- end -}}

{{/*
Return the credentials secret name (root S3 credentials + meta URL).
*/}}
{{- define "juicefs-s3-gateway.secretName" -}}
{{- if .Values.auth.existingSecret -}}
    {{- tpl .Values.auth.existingSecret $ -}}
{{- else -}}
    {{- printf "%s" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return true if a credentials secret should be created.
*/}}
{{- define "juicefs-s3-gateway.createSecret" -}}
{{- if not .Values.auth.existingSecret -}}
    {{- true -}}
{{- end -}}
{{- end -}}

{{/*
Key inside the secret holding the S3 root access key.
*/}}
{{- define "juicefs-s3-gateway.rootUserKey" -}}
{{- if and .Values.auth.existingSecret .Values.auth.rootUserSecretKey -}}
    {{- tpl .Values.auth.rootUserSecretKey $ -}}
{{- else -}}
    {{- "root-user" -}}
{{- end -}}
{{- end -}}

{{/*
Key inside the secret holding the S3 root secret key.
*/}}
{{- define "juicefs-s3-gateway.rootPasswordKey" -}}
{{- if and .Values.auth.existingSecret .Values.auth.rootPasswordSecretKey -}}
    {{- tpl .Values.auth.rootPasswordSecretKey $ -}}
{{- else -}}
    {{- "root-password" -}}
{{- end -}}
{{- end -}}

{{/*
Key inside the secret holding the metadata engine URL.
*/}}
{{- define "juicefs-s3-gateway.metaUrlKey" -}}
{{- if and .Values.auth.existingSecret .Values.auth.metaUrlSecretKey -}}
    {{- tpl .Values.auth.metaUrlSecretKey $ -}}
{{- else -}}
    {{- "meta-url" -}}
{{- end -}}
{{- end -}}

{{/*
Return the bucket-admin API bearer token secret name.
*/}}
{{- define "juicefs-s3-gateway.admin.secretName" -}}
{{- if .Values.bucketAdmin.existingSecret -}}
    {{- tpl .Values.bucketAdmin.existingSecret $ -}}
{{- else -}}
    {{- printf "%s-admin" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Get the S3 root access key value (generate/manage when not using an existing secret).
*/}}
{{- define "juicefs-s3-gateway.rootUserValue" -}}
{{- include "common.secrets.passwords.manage" (dict "secret" (include "common.names.fullname" .) "key" "root-user" "providedValues" (list "auth.rootUser") "context" $) -}}
{{- end -}}

{{/*
Get the S3 root secret key value.
*/}}
{{- define "juicefs-s3-gateway.rootPasswordValue" -}}
{{- include "common.secrets.passwords.manage" (dict "secret" (include "common.names.fullname" .) "key" "root-password" "providedValues" (list "auth.rootPassword") "context" $) -}}
{{- end -}}

{{/*
Return the service account name.
*/}}
{{- define "juicefs-s3-gateway.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{- default (include "common.names.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
    {{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Compile all validation warnings into a single message and fail.
*/}}
{{- define "juicefs-s3-gateway.validateValues" -}}
{{- $messages := list -}}
{{- $messages := append $messages (include "juicefs-s3-gateway.validateValues.metaUrl" .) -}}
{{- $messages := append $messages (include "juicefs-s3-gateway.validateValues.atime" .) -}}
{{- $messages := append $messages (include "juicefs-s3-gateway.validateValues.adminToken" .) -}}
{{- $messages := without $messages "" -}}
{{- $message := join "\n" $messages -}}
{{- if $message -}}
{{-   printf "\nVALUES VALIDATION:\n%s" $message | fail -}}
{{- end -}}
{{- end -}}

{{/*
The metadata engine URL is mandatory (either inline or via an existing secret).
*/}}
{{- define "juicefs-s3-gateway.validateValues.metaUrl" -}}
{{- if and (empty .Values.auth.metaUrl) (empty .Values.auth.existingSecret) -}}
juicefs-s3-gateway: auth.metaUrl
    A metadata engine URL is required. Set auth.metaUrl (e.g.
    "tikv://pd-host:2379/myjfs") or provide auth.existingSecret.
{{- end -}}
{{- end -}}

{{/*
Tier aging demotion needs atime tracking; warn against the noatime default.
*/}}
{{- define "juicefs-s3-gateway.validateValues.atime" -}}
{{- if and .Values.tierAging.enabled (eq .Values.atimeMode "noatime") -}}
juicefs-s3-gateway: atimeMode
    tierAging.enabled is true but atimeMode is "noatime", so reads never
    refresh atime and files are never considered idle for demotion. Use
    "relatime" (recommended) or "strictatime".
{{- end -}}
{{- end -}}

{{/*
If the bucket-admin API is exposed, it must have a token.
*/}}
{{- define "juicefs-s3-gateway.validateValues.adminToken" -}}
{{- if and .Values.bucketAdmin.enabled (empty .Values.bucketAdmin.token) (empty .Values.bucketAdmin.existingSecret) -}}
juicefs-s3-gateway: bucketAdmin.token
    bucketAdmin.enabled is true but no token is set. Provide
    bucketAdmin.token or bucketAdmin.existingSecret; an unauthenticated
    bucket-provisioning endpoint must never be exposed.
{{- end -}}
{{- end -}}
