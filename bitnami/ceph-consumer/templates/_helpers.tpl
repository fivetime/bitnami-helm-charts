{{/*
Copyright The Rook Authors.
SPDX-License-Identifier: Apache-2.0
*/}}

{{/*
Return the proper ceph-consumer controller image name
*/}}
{{- define "ceph-consumer.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.controller.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "ceph-consumer.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.controller.image) "context" $) -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "ceph-consumer.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Return the consumer namespace
*/}}
{{- define "ceph-consumer.consumerNamespace" -}}
{{- default .Values.consumer.namespace (include "common.names.namespace" .) -}}
{{- end -}}

{{/*
Return the provider namespace
*/}}
{{- define "ceph-consumer.providerNamespace" -}}
{{- .Values.provider.namespace -}}
{{- end -}}

{{/*
Return the kubeconfig secret name
*/}}
{{- define "ceph-consumer.kubeconfigSecretName" -}}
{{- if .Values.provider.kubeconfigSecret -}}
    {{ .Values.provider.kubeconfigSecret }}
{{- else -}}
    {{ printf "%s-provider-kubeconfig" (include "common.names.fullname" .) }}
{{- end -}}
{{- end -}}

{{/*
Return the configmap name for controller configuration
*/}}
{{- define "ceph-consumer.configConfigMapName" -}}
{{ printf "%s-config" (include "common.names.fullname" .) }}
{{- end -}}

{{/*
Labels for managed resources
*/}}
{{- define "ceph-consumer.managedLabels" -}}
app.kubernetes.io/managed-by: {{ include "common.names.fullname" . }}
ceph-consumer.rook.io/managed: "true"
{{- end -}}

{{/*
Compile all warnings into a single message.
*/}}
{{- define "ceph-consumer.validateValues" -}}
{{- $messages := list -}}
{{- $messages := append $messages (include "ceph-consumer.validateValues.kubeconfig" .) -}}
{{- $messages := without $messages "" -}}
{{- $message := join "\n" $messages -}}
{{- if $message -}}
{{-   printf "\nVALUES VALIDATION:\n%s" $message -}}
{{- end -}}
{{- end -}}

{{/*
Validate kubeconfig is provided
*/}}
{{- define "ceph-consumer.validateValues.kubeconfig" -}}
{{- if and (not .Values.provider.kubeconfig) (not .Values.provider.kubeconfigSecret) -}}
ceph-consumer: provider.kubeconfig or provider.kubeconfigSecret
    You must provide either provider.kubeconfig or provider.kubeconfigSecret
    to connect to the provider Ceph cluster.
{{- end -}}
{{- end -}}
