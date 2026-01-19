{{/*
Copyright Simon Li. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/* vim: set filetype=mustache: */}}

{{/*
Return the proper update job image name
*/}}
{{- define "geoip-database.update.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.update.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper kubectl image name
*/}}
{{- define "geoip-database.kubectl.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.update.kubectlImage "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "geoip-database.imagePullSecrets" -}}
{{- include "common.images.pullSecrets" (dict "images" (list .Values.update.image .Values.update.kubectlImage) "global" .Values.global) -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "geoip-database.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Return the credentials secret name
*/}}
{{- define "geoip-database.secretName" -}}
{{- if .Values.source.existingSecret.enabled -}}
    {{- required "source.existingSecret.name is required when existingSecret.enabled is true" .Values.source.existingSecret.name -}}
{{- else -}}
    {{- printf "%s-credentials" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the PVC name
*/}}
{{- define "geoip-database.pvcName" -}}
{{- if .Values.storage.existingClaim -}}
    {{- .Values.storage.existingClaim -}}
{{- else -}}
    {{- printf "%s-data" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the hash ConfigMap name
*/}}
{{- define "geoip-database.hashConfigMapName" -}}
{{- if .Values.hashConfigMap.name -}}
    {{- .Values.hashConfigMap.name -}}
{{- else -}}
    {{- printf "%s-hash" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Check if using GitHub mode
*/}}
{{- define "geoip-database.isGitHubMode" -}}
{{- if eq .Values.source.type "github" -}}
true
{{- end -}}
{{- end -}}

{{/*
Check if secret is needed
*/}}
{{- define "geoip-database.needsSecret" -}}
{{- if eq .Values.source.type "github" -}}
  {{- if .Values.source.github.token -}}
true
  {{- end -}}
{{- else -}}
true
{{- end -}}
{{- end -}}

{{/*
Update Job Pod Spec - shared between Job and CronJob
*/}}
{{- define "geoip-database.update.podSpec" -}}
{{- include "geoip-database.imagePullSecrets" . | nindent 0 }}
serviceAccountName: {{ template "geoip-database.serviceAccountName" . }}
restartPolicy: {{ .Values.update.restartPolicy | default "OnFailure" }}
{{- if .Values.update.podSecurityContext.enabled }}
securityContext: {{- include "common.compatibility.renderSecurityContext" (dict "secContext" .Values.update.podSecurityContext "context" $) | nindent 2 }}
{{- end }}
{{- if .Values.update.priorityClassName }}
priorityClassName: {{ .Values.update.priorityClassName | quote }}
{{- end }}
{{- if .Values.update.nodeSelector }}
nodeSelector: {{- include "common.tplvalues.render" ( dict "value" .Values.update.nodeSelector "context" $) | nindent 2 }}
{{- end }}
{{- if .Values.update.tolerations }}
tolerations: {{- include "common.tplvalues.render" (dict "value" .Values.update.tolerations "context" .) | nindent 2 }}
{{- end }}
{{- if .Values.update.affinity }}
affinity: {{- include "common.tplvalues.render" ( dict "value" .Values.update.affinity "context" $) | nindent 2 }}
{{- end }}
{{- if .Values.update.topologySpreadConstraints }}
topologySpreadConstraints: {{- include "common.tplvalues.render" (dict "value" .Values.update.topologySpreadConstraints "context" .) | nindent 2 }}
{{- end }}
initContainers:
  - name: geoip-download
    image: {{ include "geoip-database.update.image" . }}
    imagePullPolicy: {{ .Values.update.image.pullPolicy }}
    {{- if .Values.update.containerSecurityContext.enabled }}
    securityContext: {{- include "common.compatibility.renderSecurityContext" (dict "secContext" .Values.update.containerSecurityContext "context" $) | nindent 6 }}
    {{- end }}
    env:
      {{- if eq .Values.source.type "github" }}
      # GitHub relay mode
      - name: GITHUB_OWNER
        value: {{ required "source.github.owner is required when source.type is github" .Values.source.github.owner | quote }}
      - name: GITHUB_REPO
        value: {{ .Values.source.github.repo | default "geoip-update-relay" | quote }}
      {{- if .Values.source.github.token }}
      # Private repo - token provided directly
      - name: GITHUB_TOKEN
        valueFrom:
          secretKeyRef:
            name: {{ include "geoip-database.secretName" . }}
            key: {{ .Values.source.existingSecret.keys.githubToken | default "github-token" }}
      {{- else if and .Values.source.existingSecret.enabled .Values.source.existingSecret.name }}
      # Private repo - token from existing secret
      - name: GITHUB_TOKEN
        valueFrom:
          secretKeyRef:
            name: {{ .Values.source.existingSecret.name }}
            key: {{ .Values.source.existingSecret.keys.githubToken | default "github-token" }}
      {{- end }}
      {{- /* Public repo without token - no GITHUB_TOKEN env var needed */}}
      {{- else }}
      # MaxMind direct mode
      - name: GEOIPUPDATE_ACCOUNT_ID
        valueFrom:
          secretKeyRef:
            name: {{ include "geoip-database.secretName" . }}
            key: {{ .Values.source.existingSecret.keys.accountId | default "account-id" }}
      - name: GEOIPUPDATE_LICENSE_KEY
        valueFrom:
          secretKeyRef:
            name: {{ include "geoip-database.secretName" . }}
            key: {{ .Values.source.existingSecret.keys.licenseKey | default "license-key" }}
      {{- if .Values.source.maxmind.host }}
      - name: GEOIPUPDATE_HOST
        value: {{ .Values.source.maxmind.host | quote }}
      {{- end }}
      {{- if .Values.source.maxmind.proxy }}
      - name: GEOIPUPDATE_PROXY
        value: {{ .Values.source.maxmind.proxy | quote }}
      {{- end }}
      {{- if .Values.source.maxmind.proxyUserPassword }}
      - name: GEOIPUPDATE_PROXY_USER_PASSWORD
        valueFrom:
          secretKeyRef:
            name: {{ include "geoip-database.secretName" . }}
            key: {{ .Values.source.existingSecret.keys.proxyUserPassword | default "proxy-user-password" }}
      {{- end }}
      {{- end }}
      - name: GEOIPUPDATE_EDITION_IDS
        value: {{ required "databases.editionIds cannot be empty" (join " " .Values.databases.editionIds) | quote }}
      {{- if .Values.databases.preserveFileTimes }}
      - name: GEOIPUPDATE_PRESERVE_FILE_TIMES
        value: "1"
      {{- end }}
      {{- if .Values.update.verbose }}
      - name: GEOIPUPDATE_VERBOSE
        value: "1"
      {{- end }}
      - name: GEOIPUPDATE_DB_DIR
        value: {{ .Values.databases.directory | quote }}
      {{- if .Values.update.extraEnvVars }}
      {{- include "common.tplvalues.render" (dict "value" .Values.update.extraEnvVars "context" $) | nindent 6 }}
      {{- end }}
    {{- if .Values.update.resources }}
    resources: {{- toYaml .Values.update.resources | nindent 6 }}
    {{- else if ne .Values.update.resourcesPreset "none" }}
    resources: {{- include "common.resources.preset" (dict "type" .Values.update.resourcesPreset) | nindent 6 }}
    {{- end }}
    volumeMounts:
      - name: geoip-data
        mountPath: {{ .Values.databases.directory }}
      {{- if .Values.update.extraVolumeMounts }}
      {{- include "common.tplvalues.render" (dict "value" .Values.update.extraVolumeMounts "context" $) | nindent 6 }}
      {{- end }}
containers:
  {{- if .Values.hashConfigMap.enabled }}
  - name: hash-update
    image: {{ include "geoip-database.kubectl.image" . }}
    imagePullPolicy: {{ .Values.update.kubectlImage.pullPolicy }}
    {{- if .Values.update.containerSecurityContext.enabled }}
    securityContext: {{- include "common.compatibility.renderSecurityContext" (dict "secContext" .Values.update.containerSecurityContext "context" $) | nindent 6 }}
    {{- end }}
    env:
      - name: GEOIP_DIR
        value: {{ .Values.databases.directory | quote }}
      - name: CONFIGMAP_NAME
        value: {{ include "geoip-database.hashConfigMapName" . | quote }}
      - name: NAMESPACE
        value: {{ include "common.names.namespace" . | quote }}
    command:
      - /bin/bash
      - -c
      - |
        set -e
        echo "Calculating GeoIP database hash..."
        
        # 计算所有 mmdb 文件的组合哈希
        HASH=$(find "$GEOIP_DIR" -name "*.mmdb" -type f -exec sha256sum {} \; | sort | sha256sum | cut -d' ' -f1 | head -c 16)
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        
        if [ -z "$HASH" ]; then
          echo "ERROR: No .mmdb files found in $GEOIP_DIR"
          exit 1
        fi
        
        echo "Combined hash: ${HASH}"
        echo "Timestamp: ${TIMESTAMP}"
        
        # 更新 ConfigMap
        kubectl patch configmap "$CONFIGMAP_NAME" \
          -n "$NAMESPACE" \
          --type merge \
          -p "{\"data\":{\"hash\":\"${HASH}\",\"updatedAt\":\"${TIMESTAMP}\"}}"
        
        echo "ConfigMap updated successfully"
    resources:
      requests:
        cpu: 10m
        memory: 32Mi
      limits:
        cpu: 100m
        memory: 64Mi
    volumeMounts:
      - name: geoip-data
        mountPath: {{ .Values.databases.directory }}
        readOnly: true
  {{- else }}
  - name: done
    image: docker.io/busybox:1.36
    imagePullPolicy: IfNotPresent
    command: ["sh", "-c", "echo 'GeoIP databases updated successfully'"]
    resources:
      requests:
        cpu: 1m
        memory: 4Mi
      limits:
        cpu: 10m
        memory: 16Mi
  {{- end }}
volumes:
  - name: geoip-data
    persistentVolumeClaim:
      claimName: {{ include "geoip-database.pvcName" . }}
  {{- if .Values.update.extraVolumes }}
  {{- include "common.tplvalues.render" (dict "value" .Values.update.extraVolumes "context" $) | nindent 2 }}
  {{- end }}
{{- end -}}
