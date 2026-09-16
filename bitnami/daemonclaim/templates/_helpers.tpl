{{- /*
Copyright Broadcom, Inc. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/*
Return the proper daemonclaim image name
*/}}
{{- define "daemonclaim.image" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) -}}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "daemonclaim.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.image) "context" $) -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "daemonclaim.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Name of the webhook Service
*/}}
{{- define "daemonclaim.webhook.serviceName" -}}
{{- printf "%s-webhook" (include "common.names.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Name of the Secret holding the webhook serving certificate
*/}}
{{- define "daemonclaim.webhook.secretName" -}}
{{- if .Values.webhook.certificate.existingSecret -}}
{{- .Values.webhook.certificate.existingSecret -}}
{{- else -}}
{{- printf "%s-webhook-tls" (include "common.names.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Whether cert-manager issues the certificate
*/}}
{{- define "daemonclaim.webhook.useCertManager" -}}
{{- if and (not .Values.webhook.certificate.existingSecret) .Values.webhook.certificate.certManager.enabled -}}
true
{{- end -}}
{{- end -}}

{{/*
Whether Helm generates the certificate
*/}}
{{- define "daemonclaim.webhook.autoGenerate" -}}
{{- if and (not .Values.webhook.certificate.existingSecret) (not .Values.webhook.certificate.certManager.enabled) -}}
true
{{- end -}}
{{- end -}}

{{/*
Name of the cert-manager Certificate
*/}}
{{- define "daemonclaim.webhook.certificateName" -}}
{{- printf "%s-webhook" (include "common.names.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Arguments for the controller binary
*/}}
{{- define "daemonclaim.args" -}}
- --health-probe-bind-address=:8081
- --webhook-port={{ .Values.webhook.port }}
- --webhook-cert-path=/certs
{{- if .Values.metrics.enabled }}
- --metrics-bind-address=:{{ .Values.metrics.port }}
- --metrics-secure=false
{{- else }}
- --metrics-bind-address=0
{{- end }}
{{- if .Values.leaderElection }}
- --leader-elect
{{- end }}
{{- if eq .Values.logLevel "debug" }}
- --zap-log-level=debug
{{- end }}
{{- range .Values.extraArgs }}
- {{ . | quote }}
{{- end }}
{{- end -}}

{{/*
Compile all warnings into a single message.
*/}}
{{- define "daemonclaim.validateValues" -}}
{{- $messages := list -}}
{{- $messages = append $messages (include "daemonclaim.validateValues.replicas" .) -}}
{{- $messages = append $messages (include "daemonclaim.validateValues.certificate" .) -}}
{{- $messages = append $messages (include "daemonclaim.validateValues.failurePolicy" .) -}}
{{- $messages = without $messages "" -}}
{{- $message := join "\n" $messages -}}
{{- if $message -}}
{{-   printf "\nVALUES VALIDATION:\n%s" $message | fail -}}
{{- end -}}
{{- end -}}

{{- define "daemonclaim.validateValues.replicas" -}}
{{- if and (gt (int .Values.replicaCount) 1) (not .Values.leaderElection) -}}
daemonclaim: replicaCount
    replicaCount is {{ .Values.replicaCount }} but leaderElection is false. Two controllers
    reconciling the same DaemonClaims race each other; set leaderElection=true or replicaCount=1.
{{- end -}}
{{- end -}}

{{- define "daemonclaim.validateValues.certificate" -}}
{{- if and .Values.webhook.certificate.existingSecret .Values.webhook.certificate.certManager.enabled -}}
daemonclaim: webhook.certificate
    Both webhook.certificate.existingSecret and webhook.certificate.certManager.enabled are set.
    Pick one: the Secret you already have, or let cert-manager issue one.
{{- end -}}
{{- end -}}

{{- define "daemonclaim.validateValues.failurePolicy" -}}
{{- if not (has .Values.webhook.failurePolicy (list "Fail" "Ignore")) -}}
daemonclaim: webhook.failurePolicy
    Must be Fail or Ignore, got {{ .Values.webhook.failurePolicy | quote }}.
{{- end -}}
{{- end -}}

{{/*
Warn about Ignore in NOTES
*/}}
{{- define "daemonclaim.checkFailurePolicy" -}}
{{- if eq .Values.webhook.failurePolicy "Ignore" }}

WARNING: webhook.failurePolicy is Ignore

  When the webhook is unreachable the API server admits opted-in pods unmodified, with the
  placeholder claimName they were written with. Every node's pod then points at the same
  claim - either sharing one volume or all Pending on a name that does not exist. Fail is the
  safe setting: it refuses those pods until the webhook is back, and touches nothing else.
{{- end -}}
{{- end -}}

{{/*
Warn about auto-generated certificates in NOTES
*/}}
{{- define "daemonclaim.checkCertificate" -}}
{{- if include "daemonclaim.webhook.autoGenerate" . }}

NOTE: the webhook certificate was generated by Helm

  It is stored in Secret {{ include "daemonclaim.webhook.secretName" . }}, reused on upgrade, and
  valid for {{ .Values.webhook.certificate.autoGenerated.validityDays }} days. Nothing rotates it.
  On a cluster with cert-manager, set webhook.certificate.certManager.enabled=true instead.
{{- end -}}
{{- end -}}
