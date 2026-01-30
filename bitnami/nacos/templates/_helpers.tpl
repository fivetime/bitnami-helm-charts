{{/*
Expand the name of the chart.
*/}}
{{- define "nacos.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "nacos.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "nacos.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Allow the release namespace to be overridden
*/}}
{{- define "nacos.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "nacos.labels" -}}
helm.sh/chart: {{ include "nacos.chart" . }}
{{ include "nacos.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Values.commonLabels }}
{{ toYaml .Values.commonLabels }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "nacos.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nacos.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "nacos.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "nacos.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper Nacos image name
*/}}
{{- define "nacos.image" -}}
{{- $registryName := .Values.image.registry -}}
{{- $repositoryName := .Values.image.repository -}}
{{- $tag := .Values.image.tag | toString -}}
{{- if .Values.global }}
    {{- if .Values.global.imageRegistry }}
        {{- $registryName = .Values.global.imageRegistry -}}
    {{- end -}}
{{- end -}}
{{- if $registryName }}
{{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
{{- else }}
{{- printf "%s:%s" $repositoryName $tag -}}
{{- end }}
{{- end }}

{{/*
Return the proper plugin image name
*/}}
{{- define "nacos.plugin.image" -}}
{{- $registryName := .Values.plugin.image.registry -}}
{{- $repositoryName := .Values.plugin.image.repository -}}
{{- $tag := .Values.plugin.image.tag | toString -}}
{{- if .Values.global }}
    {{- if .Values.global.imageRegistry }}
        {{- $registryName = .Values.global.imageRegistry -}}
    {{- end -}}
{{- end -}}
{{- if $registryName }}
{{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
{{- else }}
{{- printf "%s:%s" $repositoryName $tag -}}
{{- end }}
{{- end }}

{{/*
Return the proper init image name based on database type
*/}}
{{- define "nacos.init.image" -}}
{{- $dbType := .Values.database.type -}}
{{- $registryName := "" -}}
{{- $repositoryName := "" -}}
{{- $tag := "" -}}
{{- if eq $dbType "mysql" }}
{{- $registryName = .Values.database.init.image.mysql.registry -}}
{{- $repositoryName = .Values.database.init.image.mysql.repository -}}
{{- $tag = .Values.database.init.image.mysql.tag | toString -}}
{{- else if eq $dbType "postgresql" }}
{{- $registryName = .Values.database.init.image.postgresql.registry -}}
{{- $repositoryName = .Values.database.init.image.postgresql.repository -}}
{{- $tag = .Values.database.init.image.postgresql.tag | toString -}}
{{- end -}}
{{- if .Values.global }}
    {{- if .Values.global.imageRegistry }}
        {{- $registryName = .Values.global.imageRegistry -}}
    {{- end -}}
{{- end -}}
{{- if $registryName }}
{{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
{{- else }}
{{- printf "%s:%s" $repositoryName $tag -}}
{{- end }}
{{- end }}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "nacos.imagePullSecrets" -}}
{{- $pullSecrets := list }}
{{- if .Values.global }}
    {{- range .Values.global.imagePullSecrets }}
        {{- $pullSecrets = append $pullSecrets . }}
    {{- end }}
{{- end }}
{{- range .Values.image.pullSecrets }}
    {{- $pullSecrets = append $pullSecrets . }}
{{- end }}
{{- if $pullSecrets }}
imagePullSecrets:
{{- range $pullSecrets }}
  - name: {{ . }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Return the database secret name
*/}}
{{- define "nacos.database.secretName" -}}
{{- if .Values.database.existingSecret }}
{{- .Values.database.existingSecret }}
{{- else }}
{{- printf "%s-db" (include "nacos.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the auth secret name
*/}}
{{- define "nacos.auth.secretName" -}}
{{- if .Values.auth.existingSecret }}
{{- .Values.auth.existingSecret }}
{{- else }}
{{- printf "%s-auth" (include "nacos.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the headless service name
*/}}
{{- define "nacos.headless.serviceName" -}}
{{- printf "%s-headless" (include "nacos.fullname" .) }}
{{- end }}

{{/*
Return the replica count
*/}}
{{- define "nacos.replicaCount" -}}
{{- if eq .Values.mode "standalone" }}
{{- 1 }}
{{- else }}
{{- .Values.replicaCount }}
{{- end }}
{{- end }}

{{/*
Return true if database type is external (mysql or postgresql)
*/}}
{{- define "nacos.database.external" -}}
{{- if or (eq .Values.database.type "mysql") (eq .Values.database.type "postgresql") -}}
true
{{- end -}}
{{- end }}

{{/*
Return JDBC URL based on database type
*/}}
{{- define "nacos.database.jdbcUrl" -}}
{{- if eq .Values.database.type "mysql" }}
{{- printf "jdbc:mysql://%s:%v/%s?%s" .Values.database.host (int .Values.database.port) .Values.database.name .Values.database.param }}
{{- else if eq .Values.database.type "postgresql" }}
{{- printf "jdbc:postgresql://%s:%v/%s?%s" .Values.database.host (int .Values.database.port) .Values.database.name .Values.database.param }}
{{- end }}
{{- end }}

{{/*
Return the PVC name
*/}}
{{- define "nacos.pvc.name" -}}
{{- if .Values.persistence.existingClaim }}
{{- .Values.persistence.existingClaim }}
{{- else }}
{{- printf "%s-data" (include "nacos.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the storage class
*/}}
{{- define "nacos.storageClass" -}}
{{- if .Values.persistence.storageClass }}
{{- if (eq "-" .Values.persistence.storageClass) }}
storageClassName: ""
{{- else }}
storageClassName: {{ .Values.persistence.storageClass | quote }}
{{- end }}
{{- else if .Values.global }}
{{- if .Values.global.storageClass }}
{{- if (eq "-" .Values.global.storageClass) }}
storageClassName: ""
{{- else }}
storageClassName: {{ .Values.global.storageClass | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Return pod anti-affinity rules
*/}}
{{- define "nacos.podAntiAffinity" -}}
{{- if eq .Values.podAntiAffinityPreset "hard" }}
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          {{- include "nacos.selectorLabels" . | nindent 10 }}
      topologyKey: kubernetes.io/hostname
{{- else if eq .Values.podAntiAffinityPreset "soft" }}
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            {{- include "nacos.selectorLabels" . | nindent 12 }}
        topologyKey: kubernetes.io/hostname
{{- end }}
{{- end }}

{{/*
Generate auth token if not provided
*/}}
{{- define "nacos.auth.token" -}}
{{- if .Values.auth.token }}
{{- .Values.auth.token }}
{{- else }}
{{- randAlphaNum 64 | b64enc }}
{{- end }}
{{- end }}

{{/*
Generate auth identity key if not provided
*/}}
{{- define "nacos.auth.identityKey" -}}
{{- if .Values.auth.identity.key }}
{{- .Values.auth.identity.key }}
{{- else }}
{{- printf "nacos-%s" (randAlphaNum 8 | lower) }}
{{- end }}
{{- end }}

{{/*
Generate auth identity value if not provided
*/}}
{{- define "nacos.auth.identityValue" -}}
{{- if .Values.auth.identity.value }}
{{- .Values.auth.identity.value }}
{{- else }}
{{- randAlphaNum 32 }}
{{- end }}
{{- end }}

{{/*
Return Nacos cluster members list
*/}}
{{- define "nacos.clusterMembers" -}}
{{- $fullname := include "nacos.fullname" . -}}
{{- $headless := include "nacos.headless.serviceName" . -}}
{{- $namespace := include "nacos.namespace" . -}}
{{- $clusterDomain := .Values.clusterDomain -}}
{{- $replicaCount := int (include "nacos.replicaCount" .) -}}
{{- $members := list -}}
{{- range $i := until $replicaCount -}}
{{- $members = append $members (printf "%s-%d.%s.%s.svc.%s:8848" $fullname $i $headless $namespace $clusterDomain) -}}
{{- end -}}
{{- join " " $members -}}
{{- end }}
