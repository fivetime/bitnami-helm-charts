{{/*
Copyright Anthropic. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/*
Return the proper PowerDNS-Admin image name
*/}}
{{- define "powerdns-admin.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "powerdns-admin.imagePullSecrets" -}}
{{- include "common.images.pullSecrets" (dict "images" (list .Values.image) "global" .Values.global) -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "powerdns-admin.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Return the main secret name
*/}}
{{- define "powerdns-admin.secretName" -}}
{{- if .Values.powerdnsAdmin.existingSecret -}}
    {{- .Values.powerdnsAdmin.existingSecret -}}
{{- else -}}
    {{- include "common.names.fullname" . -}}
{{- end -}}
{{- end -}}

{{/*
Return true if we should create the main application secret
*/}}
{{- define "powerdns-admin.createSecret" -}}
{{- if not .Values.powerdnsAdmin.existingSecret -}}
    {{- true -}}
{{- end -}}
{{- end -}}

{{/*
Return the database secret name
*/}}
{{- define "powerdns-admin.database.secretName" -}}
{{- if .Values.externalDatabase.existingSecret -}}
    {{- .Values.externalDatabase.existingSecret -}}
{{- else -}}
    {{- printf "%s-database" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the PowerDNS API secret name
*/}}
{{- define "powerdns-admin.powerdnsApi.secretName" -}}
{{- if .Values.powerdnsApi.existingSecret -}}
    {{- .Values.powerdnsApi.existingSecret -}}
{{- else -}}
    {{- printf "%s-pdns-api" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the LDAP secret name
*/}}
{{- define "powerdns-admin.auth.ldap.secretName" -}}
{{- if .Values.auth.ldap.existingSecret -}}
    {{- .Values.auth.ldap.existingSecret -}}
{{- else -}}
    {{- printf "%s-ldap" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the SAML secret name
*/}}
{{- define "powerdns-admin.auth.saml.secretName" -}}
{{- if .Values.auth.saml.existingSecret -}}
    {{- .Values.auth.saml.existingSecret -}}
{{- else -}}
    {{- printf "%s-saml" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the OIDC secret name
*/}}
{{- define "powerdns-admin.auth.oidc.secretName" -}}
{{- if .Values.auth.oidc.existingSecret -}}
    {{- .Values.auth.oidc.existingSecret -}}
{{- else -}}
    {{- printf "%s-oidc" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the Google OAuth secret name
*/}}
{{- define "powerdns-admin.auth.google.secretName" -}}
{{- if .Values.auth.google.existingSecret -}}
    {{- .Values.auth.google.existingSecret -}}
{{- else -}}
    {{- printf "%s-google" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the GitHub OAuth secret name
*/}}
{{- define "powerdns-admin.auth.github.secretName" -}}
{{- if .Values.auth.github.existingSecret -}}
    {{- .Values.auth.github.existingSecret -}}
{{- else -}}
    {{- printf "%s-github" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the Azure OAuth secret name
*/}}
{{- define "powerdns-admin.auth.azure.secretName" -}}
{{- if .Values.auth.azure.existingSecret -}}
    {{- .Values.auth.azure.existingSecret -}}
{{- else -}}
    {{- printf "%s-azure" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the Mail secret name
*/}}
{{- define "powerdns-admin.mail.secretName" -}}
{{- if .Values.mail.existingSecret -}}
    {{- .Values.mail.existingSecret -}}
{{- else -}}
    {{- printf "%s-mail" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the PVC name
*/}}
{{- define "powerdns-admin.pvcName" -}}
{{- if .Values.persistence.existingClaim -}}
    {{- .Values.persistence.existingClaim -}}
{{- else -}}
    {{- include "common.names.fullname" . -}}
{{- end -}}
{{- end -}}

{{/*
Return the backup PVC name
*/}}
{{- define "powerdns-admin.backup.pvcName" -}}
{{- if .Values.backup.storage.pvc.existingClaim -}}
    {{- .Values.backup.storage.pvc.existingClaim -}}
{{- else -}}
    {{- printf "%s-backup" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Compile all warnings into a single message.
*/}}
{{- define "powerdns-admin.validateValues" -}}
{{- $messages := list -}}
{{- $messages := append $messages (include "powerdns-admin.validateValues.database" .) -}}
{{- $messages := append $messages (include "powerdns-admin.validateValues.secretKey" .) -}}
{{- $messages := without $messages "" -}}
{{- $message := join "\n" $messages -}}

{{- if $message -}}
{{-   printf "\nVALUES VALIDATION:\n%s" $message -}}
{{- end -}}
{{- end -}}

{{/*
Validate values of PowerDNS-Admin - Database configuration
*/}}
{{- define "powerdns-admin.validateValues.database" -}}
{{- if and (ne .Values.database.type "sqlite") (not .Values.externalDatabase.host) -}}
powerdns-admin: database.host
    You must provide a database host when using PostgreSQL or MySQL.
    Please set externalDatabase.host
{{- end -}}
{{- end -}}

{{/*
Validate values of PowerDNS-Admin - Secret key configuration
*/}}
{{- define "powerdns-admin.validateValues.secretKey" -}}
{{- if and (not .Values.powerdnsAdmin.secretKey) (not .Values.powerdnsAdmin.existingSecret) -}}
powerdns-admin: secretKey
    You must provide a secret key for Flask session management.
    Please set powerdnsAdmin.secretKey or powerdnsAdmin.existingSecret
{{- end -}}
{{- end -}}

{{/*
Return the database port
*/}}
{{- define "powerdns-admin.databasePort" -}}
{{- if eq .Values.database.type "postgresql" -}}
    {{- .Values.externalDatabase.port | default 5432 -}}
{{- else if eq .Values.database.type "mysql" -}}
    {{- .Values.externalDatabase.port | default 3306 -}}
{{- else -}}
    {{- 0 -}}
{{- end -}}
{{- end -}}

{{/*
Return true if ingress supports pathType
*/}}
{{- define "common.ingress.supportsPathType" -}}
{{- if semverCompare ">=1.18-0" (include "common.capabilities.kubeVersion" .) -}}
{{- print "true" -}}
{{- else -}}
{{- print "false" -}}
{{- end -}}
{{- end -}}

{{/*
Return true if ingress supports ingressClassName
*/}}
{{- define "common.ingress.supportsIngressClassname" -}}
{{- if semverCompare ">=1.18-0" (include "common.capabilities.kubeVersion" .) -}}
{{- print "true" -}}
{{- else -}}
{{- print "false" -}}
{{- end -}}
{{- end -}}
