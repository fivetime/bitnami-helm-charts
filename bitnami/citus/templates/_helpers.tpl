{{/*
Copyright Anthropic, Inc.
SPDX-License-Identifier: Apache-2.0
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "citus.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "citus.fullname" -}}
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
{{- define "citus.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "citus.labels" -}}
helm.sh/chart: {{ include "citus.chart" . }}
{{ include "citus.selectorLabels" . }}
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
{{- define "citus.selectorLabels" -}}
app.kubernetes.io/name: {{ include "citus.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Coordinator labels
*/}}
{{- define "citus.coordinator.labels" -}}
{{ include "citus.labels" . }}
app.kubernetes.io/component: coordinator
{{- end }}

{{/*
Coordinator selector labels
*/}}
{{- define "citus.coordinator.selectorLabels" -}}
{{ include "citus.selectorLabels" . }}
app.kubernetes.io/component: coordinator
{{- end }}

{{/*
Worker labels
*/}}
{{- define "citus.worker.labels" -}}
{{ include "citus.labels" . }}
app.kubernetes.io/component: worker
{{- end }}

{{/*
Worker selector labels
*/}}
{{- define "citus.worker.selectorLabels" -}}
{{ include "citus.selectorLabels" . }}
app.kubernetes.io/component: worker
{{- end }}

{{/*
Manager labels
*/}}
{{- define "citus.manager.labels" -}}
{{ include "citus.labels" . }}
app.kubernetes.io/component: manager
{{- end }}

{{/*
Manager selector labels
*/}}
{{- define "citus.manager.selectorLabels" -}}
{{ include "citus.selectorLabels" . }}
app.kubernetes.io/component: manager
{{- end }}

{{/*
Create the name of the coordinator service account
*/}}
{{- define "citus.coordinator.serviceAccountName" -}}
{{- if .Values.coordinator.serviceAccount.create }}
{{- default (printf "%s-coordinator" (include "citus.fullname" .)) .Values.coordinator.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.coordinator.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the worker service account
*/}}
{{- define "citus.worker.serviceAccountName" -}}
{{- if .Values.worker.serviceAccount.create }}
{{- default (printf "%s-worker" (include "citus.fullname" .)) .Values.worker.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.worker.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper Citus image name
*/}}
{{- define "citus.image" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end }}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "citus.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.image .Values.metrics.image .Values.volumePermissions.image) "context" $) }}
{{- end }}

{{/*
Return the proper metrics image name
*/}}
{{- define "citus.metrics.image" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.metrics.image "global" .Values.global) }}
{{- end }}

{{/*
Return the proper volume permissions image name
*/}}
{{- define "citus.volumePermissions.image" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.volumePermissions.image "global" .Values.global) }}
{{- end }}

{{/*
Return the proper Manager image name
*/}}
{{- define "citus.manager.image" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.manager.image "global" .Values.global) }}
{{- end }}

{{/*
Return the proper Backup image name
*/}}
{{- define "citus.backup.image" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.backup.image "global" .Values.global) }}
{{- end }}

{{/*
Return the Citus secret name
*/}}
{{- define "citus.secretName" -}}
{{- if .Values.auth.existingSecret }}
{{- .Values.auth.existingSecret }}
{{- else }}
{{- printf "%s-secret" (include "citus.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Return the Citus postgres password key
*/}}
{{- define "citus.secretPasswordKey" -}}
{{- if .Values.auth.existingSecret }}
{{- .Values.auth.secretKeys.adminPasswordKey }}
{{- else }}
{{- print "postgres-password" }}
{{- end }}
{{- end }}

{{/*
Return the Citus user password key
*/}}
{{- define "citus.secretUserPasswordKey" -}}
{{- if .Values.auth.existingSecret }}
{{- .Values.auth.secretKeys.userPasswordKey }}
{{- else }}
{{- print "password" }}
{{- end }}
{{- end }}

{{/*
Return the Coordinator fullname
*/}}
{{- define "citus.coordinator.fullname" -}}
{{- printf "%s-coordinator" (include "citus.fullname" .) }}
{{- end }}

{{/*
Return the Worker fullname
*/}}
{{- define "citus.worker.fullname" -}}
{{- printf "%s-worker" (include "citus.fullname" .) }}
{{- end }}

{{/*
Return the Manager fullname
*/}}
{{- define "citus.manager.fullname" -}}
{{- printf "%s-manager" (include "citus.fullname" .) }}
{{- end }}

{{/*
Return the Coordinator headless service name
*/}}
{{- define "citus.coordinator.svcHeadless" -}}
{{- printf "%s-coordinator-hl" (include "citus.fullname" .) }}
{{- end }}

{{/*
Return the Worker headless service name
*/}}
{{- define "citus.worker.svcHeadless" -}}
{{- printf "%s-worker-hl" (include "citus.fullname" .) }}
{{- end }}

{{/*
Get the coordinator FQDN
*/}}
{{- define "citus.coordinator.fqdn" -}}
{{- printf "%s.%s.svc.%s" (include "citus.coordinator.fullname" .) .Release.Namespace .Values.clusterDomain }}
{{- end }}

{{/*
Get the worker hostname pattern for DNS
*/}}
{{- define "citus.worker.hostnamePattern" -}}
{{- printf "%s-{0}.%s.%s.svc.%s" (include "citus.worker.fullname" .) (include "citus.worker.svcHeadless" .) .Release.Namespace .Values.clusterDomain }}
{{- end }}

{{/*
Get specific worker hostname
*/}}
{{- define "citus.worker.hostname" -}}
{{- $worker := index . 0 }}
{{- $context := index . 1 }}
{{- printf "%s-%d.%s.%s.svc.%s" (include "citus.worker.fullname" $context) $worker (include "citus.worker.svcHeadless" $context) $context.Release.Namespace $context.Values.clusterDomain }}
{{- end }}

{{/*
Create a default PGDATA path
*/}}
{{- define "citus.pgdata" -}}
{{- print "/var/lib/postgresql/data/pgdata" }}
{{- end }}

{{/*
Compile all warnings into a single message
*/}}
{{- define "citus.validateValues" -}}
{{- $messages := list -}}
{{- $messages := append $messages (include "citus.validateValues.auth" .) -}}
{{- $messages := append $messages (include "citus.validateValues.workers" .) -}}
{{- $messages := without $messages "" -}}
{{- $message := join "\n" $messages -}}
{{- if $message -}}
{{-   printf "\nVALUES VALIDATION:\n%s" $message -}}
{{- end -}}
{{- end -}}

{{/*
Validate auth configuration
*/}}
{{- define "citus.validateValues.auth" -}}
{{- if and (not .Values.auth.existingSecret) (not .Values.auth.postgresPassword) -}}
citus: auth.postgresPassword
    You must provide a password for the PostgreSQL admin user (postgres).
    Set auth.postgresPassword or use auth.existingSecret.
{{- end -}}
{{- end -}}

{{/*
Validate worker configuration
*/}}
{{- define "citus.validateValues.workers" -}}
{{- if lt (int .Values.worker.replicaCount) 1 -}}
citus: worker.replicaCount
    Worker replica count must be at least 1.
    Current value: {{ .Values.worker.replicaCount }}
{{- end -}}
{{- end -}}

{{/*
Return PostgreSQL configuration
*/}}
{{- define "citus.postgresql.conf" -}}
# Citus configuration
shared_preload_libraries = '{{ .Values.postgresql.sharedPreloadLibraries }}'
max_connections = {{ .Values.postgresql.maxConnections }}
wal_level = '{{ .Values.postgresql.walLevel }}'
max_wal_senders = {{ .Values.postgresql.maxWalSenders }}
max_replication_slots = {{ .Values.postgresql.maxReplicationSlots }}
max_worker_processes = {{ .Values.postgresql.maxWorkerProcesses }}
citus.shard_count = {{ .Values.postgresql.citusShardCount }}
citus.shard_replication_factor = {{ .Values.postgresql.citusShardReplicationFactor }}

# Network settings
listen_addresses = '*'

{{- if .Values.postgresql.extraConfiguration }}
# Extra configuration
{{ .Values.postgresql.extraConfiguration }}
{{- end }}
{{- end }}

{{/*
Return pg_hba.conf configuration
*/}}
{{- define "citus.pg_hba.conf" -}}
# PostgreSQL Client Authentication Configuration File
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     trust

# IPv4 local connections:
host    all             all             127.0.0.1/32            trust

# IPv6 local connections:
host    all             all             ::1/128                 trust

# Allow connections from anywhere with password
host    all             all             0.0.0.0/0               scram-sha-256
host    all             all             ::/0                    scram-sha-256

# Allow replication connections from pod network
host    replication     all             10.0.0.0/8              scram-sha-256
host    replication     all             172.16.0.0/12           scram-sha-256
host    replication     all             192.168.0.0/16          scram-sha-256
{{- end }}

{{/*
Return true if a secret object should be created
*/}}
{{- define "citus.createSecret" -}}
{{- if not .Values.auth.existingSecret }}
{{- true -}}
{{- end -}}
{{- end -}}

{{/*
Returns the available value for resources presets
*/}}
{{- define "citus.resources.preset" -}}
{{- $presets := dict 
  "nano" (dict 
    "requests" (dict "cpu" "100m" "memory" "128Mi")
    "limits" (dict "cpu" "200m" "memory" "256Mi")
  )
  "micro" (dict 
    "requests" (dict "cpu" "250m" "memory" "256Mi")
    "limits" (dict "cpu" "500m" "memory" "512Mi")
  )
  "small" (dict 
    "requests" (dict "cpu" "500m" "memory" "512Mi")
    "limits" (dict "cpu" "1" "memory" "1Gi")
  )
  "medium" (dict 
    "requests" (dict "cpu" "1" "memory" "1Gi")
    "limits" (dict "cpu" "2" "memory" "2Gi")
  )
  "large" (dict 
    "requests" (dict "cpu" "2" "memory" "2Gi")
    "limits" (dict "cpu" "4" "memory" "4Gi")
  )
  "xlarge" (dict 
    "requests" (dict "cpu" "4" "memory" "4Gi")
    "limits" (dict "cpu" "8" "memory" "8Gi")
  )
  "2xlarge" (dict 
    "requests" (dict "cpu" "8" "memory" "8Gi")
    "limits" (dict "cpu" "16" "memory" "16Gi")
  )
-}}
{{- if hasKey $presets .type -}}
{{- index $presets .type | toYaml -}}
{{- else -}}
{{- print "{}" -}}
{{- end -}}
{{- end -}}

{{/*
Return Coordinator resources
*/}}
{{- define "citus.coordinator.resources" -}}
{{- if ne .Values.coordinator.resourcesPreset "none" -}}
{{- include "citus.resources.preset" (dict "type" .Values.coordinator.resourcesPreset) -}}
{{- else -}}
{{- toYaml .Values.coordinator.resources -}}
{{- end -}}
{{- end -}}

{{/*
Return Worker resources
*/}}
{{- define "citus.worker.resources" -}}
{{- if ne .Values.worker.resourcesPreset "none" -}}
{{- include "citus.resources.preset" (dict "type" .Values.worker.resourcesPreset) -}}
{{- else -}}
{{- toYaml .Values.worker.resources -}}
{{- end -}}
{{- end -}}
