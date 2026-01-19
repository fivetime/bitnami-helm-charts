{{/*
Copyright Simon Li. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/* vim: set filetype=mustache: */}}

{{/*
Return the proper PowerDNS Auth image name
*/}}
{{- define "powerdns-auth.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper MySQL image name for db-init
*/}}
{{- define "powerdns-auth.dbInit.mysql.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.dbInit.mysql.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper PostgreSQL image name for db-init
*/}}
{{- define "powerdns-auth.dbInit.postgresql.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.dbInit.postgresql.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper MySQL image name for db-sync
*/}}
{{- define "powerdns-auth.dbSync.mysql.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.dbSync.mysql.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper PostgreSQL image name for db-sync
*/}}
{{- define "powerdns-auth.dbSync.postgresql.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.dbSync.postgresql.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "powerdns-auth.imagePullSecrets" -}}
{{- include "common.images.pullSecrets" (dict "images" (list .Values.image .Values.dbInit.mysql.image .Values.dbInit.postgresql.image .Values.dbSync.mysql.image .Values.dbSync.postgresql.image) "global" .Values.global) -}}
{{- end -}}

{{/*
Create the name of the service account to use
*/}}
{{- define "powerdns-auth.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
Return the PowerDNS Auth configuration secret name
*/}}
{{- define "powerdns-auth.configSecretName" -}}
{{- printf "%s-config" (include "common.names.fullname" .) -}}
{{- end -}}

{{/*
Return the database credentials secret name
*/}}
{{- define "powerdns-auth.databaseSecretName" -}}
{{- if .Values.database.existingSecret.enabled -}}
    {{- .Values.database.existingSecret.name -}}
{{- else -}}
    {{- printf "%s-db" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the database admin credentials secret name
*/}}
{{- define "powerdns-auth.databaseAdminSecretName" -}}
{{- if .Values.database.existingSecret.enabled -}}
    {{- .Values.database.existingSecret.name -}}
{{- else -}}
    {{- printf "%s-db-admin" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Return the database host
*/}}
{{- define "powerdns-auth.databaseHost" -}}
{{- if eq .Values.database.type "postgresql" -}}
    {{- .Values.database.postgresql.host -}}
{{- else -}}
    {{- .Values.database.mysql.host -}}
{{- end -}}
{{- end -}}

{{/*
Return the database port
*/}}
{{- define "powerdns-auth.databasePort" -}}
{{- if eq .Values.database.type "postgresql" -}}
    {{- .Values.database.postgresql.port -}}
{{- else -}}
    {{- .Values.database.mysql.port -}}
{{- end -}}
{{- end -}}

{{/*
Return the database name
*/}}
{{- define "powerdns-auth.databaseName" -}}
{{- if eq .Values.database.type "postgresql" -}}
    {{- .Values.database.postgresql.database -}}
{{- else -}}
    {{- .Values.database.mysql.database -}}
{{- end -}}
{{- end -}}

{{/*
Return the database username
*/}}
{{- define "powerdns-auth.databaseUsername" -}}
{{- if eq .Values.database.type "postgresql" -}}
    {{- .Values.database.postgresql.username -}}
{{- else -}}
    {{- .Values.database.mysql.username -}}
{{- end -}}
{{- end -}}

{{/*
Return the database password
*/}}
{{- define "powerdns-auth.databasePassword" -}}
{{- if eq .Values.database.type "postgresql" -}}
    {{- .Values.database.postgresql.password -}}
{{- else -}}
    {{- .Values.database.mysql.password -}}
{{- end -}}
{{- end -}}

{{/*
Return the database admin username
*/}}
{{- define "powerdns-auth.databaseAdminUsername" -}}
{{- if eq .Values.database.type "postgresql" -}}
    {{- .Values.database.postgresql.adminUsername -}}
{{- else -}}
    {{- .Values.database.mysql.adminUsername -}}
{{- end -}}
{{- end -}}

{{/*
Return the database admin password
*/}}
{{- define "powerdns-auth.databaseAdminPassword" -}}
{{- if eq .Values.database.type "postgresql" -}}
    {{- .Values.database.postgresql.adminPassword -}}
{{- else -}}
    {{- .Values.database.mysql.adminPassword -}}
{{- end -}}
{{- end -}}

{{/*
Return true if a secret object should be created for database credentials
*/}}
{{- define "powerdns-auth.createDatabaseSecret" -}}
{{- if not .Values.database.existingSecret.enabled -}}
    {{- true -}}
{{- end -}}
{{- end -}}

{{/*
Return true if webserver/API is enabled
*/}}
{{- define "powerdns-auth.webserverEnabled" -}}
{{- if .Values.webserver.enabled -}}
    {{- true -}}
{{- end -}}
{{- end -}}

{{/*
Return true if GeoIP backend is enabled
*/}}
{{- define "powerdns-auth.geoipEnabled" -}}
{{- if and .Values.geoip.enabled .Values.geoipZones.enabled -}}
    {{- true -}}
{{- end -}}
{{- end -}}

{{/*
Generate PowerDNS configuration
*/}}
{{- define "powerdns-auth.configuration" -}}
#################################
# PowerDNS Authoritative Server Configuration
# Generated by Helm
#################################

# Daemon settings
daemon=no
guardian=no
write-pid=no
disable-syslog=yes

# Network settings
local-address={{ .Values.config.localAddress }}
local-port={{ .Values.config.localPort }}

# Logging
loglevel={{ .Values.config.loglevel }}
log-dns-details={{ if .Values.config.logDnsDetails }}yes{{ else }}no{{ end }}
log-dns-queries={{ if .Values.config.logDnsQueries }}yes{{ else }}no{{ end }}
query-logging={{ if .Values.config.queryLogging }}yes{{ else }}no{{ end }}

# AXFR / Replication
disable-axfr={{ if .Values.config.disableAxfr }}yes{{ else }}no{{ end }}
allow-axfr-ips={{ .Values.config.allowAxfrIps }}
allow-notify-from={{ .Values.config.allowNotifyFrom }}

# Primary/Secondary mode
primary={{ if .Values.config.primary }}yes{{ else }}no{{ end }}
secondary={{ if .Values.config.secondary }}yes{{ else }}no{{ end }}
{{- if .Values.config.alsoNotify }}
also-notify={{ .Values.config.alsoNotify }}
{{- end }}
{{- if .Values.config.onlyNotify }}
only-notify={{ .Values.config.onlyNotify }}
{{- end }}

# Autoprimary/Autosecondary
{{- if .Values.config.autosecondary }}
autosecondary=yes
{{- end }}
{{- if .Values.config.allowUnsignedAutoprimary }}
allow-unsigned-autoprimary=yes
{{- end }}
{{- if .Values.config.allowUnsignedNotify }}
allow-unsigned-notify=yes
{{- end }}

# Performance tuning
{{- if .Values.config.performance }}
receiver-threads={{ .Values.config.performance.receiverThreads | default 2 }}
{{- if .Values.config.performance.distributorThreads }}
distributor-threads={{ .Values.config.performance.distributorThreads }}
{{- end }}
signing-threads={{ .Values.config.performance.signingThreads | default 3 }}
reuseport={{ if .Values.config.performance.reuseport }}yes{{ else }}no{{ end }}
{{- if .Values.config.performance.udpTruncationThreshold }}
udp-truncation-threshold={{ .Values.config.performance.udpTruncationThreshold }}
{{- end }}
{{- else }}
# Legacy performance config (deprecated, use config.performance)
receiver-threads={{ .Values.config.receiverThreads | default 2 }}
retrieval-threads={{ .Values.config.retrievalThreads | default 2 }}
signing-threads={{ .Values.config.signingThreads | default 3 }}
reuseport={{ if .Values.config.reuseport }}yes{{ else }}no{{ end }}
{{- end }}

# TCP settings
max-tcp-connection-duration={{ .Values.config.maxTcpConnectionDuration }}
max-tcp-connections={{ .Values.config.maxTcpConnections }}
tcp-fast-open={{ .Values.config.tcpFastOpen }}

# DNSSEC defaults
default-ksk-algorithm={{ .Values.config.defaultKskAlgorithm }}
default-ksk-size={{ .Values.config.defaultKskSize }}
{{- if .Values.config.defaultZskAlgorithm }}
default-zsk-algorithm={{ .Values.config.defaultZskAlgorithm }}
{{- end }}
default-zsk-size={{ .Values.config.defaultZskSize }}

# DNAME processing
dname-processing={{ if .Values.config.dnameProcessing }}yes{{ else }}no{{ end }}
expand-alias={{ if .Values.config.expandAlias }}yes{{ else }}no{{ end }}

# Security
version-string={{ .Values.config.versionString }}
{{- if .Values.config.securityPollSuffix }}
security-poll-suffix={{ .Values.config.securityPollSuffix }}
{{- else }}
security-poll-suffix=
{{- end }}

# Cache settings
{{- if .Values.config.cache }}
cache-ttl={{ .Values.config.cache.ttl | default 20 }}
negquery-cache-ttl={{ .Values.config.cache.negTtl | default 60 }}
query-cache-ttl={{ if .Values.config.cache.queryEnabled }}{{ .Values.config.cache.queryTtl | default 20 }}{{ else }}0{{ end }}
{{- else }}
# Legacy cache config (deprecated, use config.cache)
cache-ttl={{ .Values.config.cacheTtl | default 20 }}
negquery-cache-ttl={{ .Values.config.negqueryCacheTtl | default 60 }}
query-cache-ttl={{ if .Values.config.queryCacheEnabled }}20{{ else }}0{{ end }}
{{- end }}

# SOA defaults
{{- if .Values.config.defaultSoaContent }}
default-soa-content={{ .Values.config.defaultSoaContent }}
{{- end }}
{{- if .Values.config.defaultSoaMail }}
default-soa-mail={{ .Values.config.defaultSoaMail }}
{{- end }}
{{- if .Values.config.defaultSoaName }}
default-soa-name={{ .Values.config.defaultSoaName }}
{{- end }}
default-ttl={{ .Values.config.defaultTtl }}

# DNS UPDATE (RFC 2136)
{{- if .Values.config.allowDnsupdateFrom }}
allow-dnsupdate-from={{ .Values.config.allowDnsupdateFrom }}
dnsupdate={{ if .Values.config.allowDnsupdateFrom }}yes{{ else }}no{{ end }}
{{- end }}
{{- if .Values.config.dnsupdateRequireTsig }}
dnsupdate-require-tsig=yes
{{- end }}
{{- if .Values.config.forwardDnsupdate }}
forward-dnsupdate=yes
{{- end }}

# LUA records configuration (for dynamic GeoDNS with database backend)
{{- if .Values.config.luaRecords.enabled }}
enable-lua-records=yes
{{- with .Values.config.luaRecords }}
{{- if .ednsSubnetProcessing }}
edns-subnet-processing=yes
{{- end }}
{{- if .execLimit }}
lua-records-exec-limit={{ .execLimit }}
{{- end }}
{{- if .luaAxfrScript }}
lua-axfr-script={{ .luaAxfrScript }}
{{- end }}
{{- with .healthChecks }}
{{- if not (eq .enabled false) }}
{{- if .interval }}
lua-health-checks-interval={{ .interval }}
{{- end }}
{{- if .expireDelay }}
lua-health-checks-expire-delay={{ .expireDelay }}
{{- end }}
{{- /* NOTE: lua-health-checks-max-concurrent and lua-health-checks-timeout are not valid PowerDNS settings */}}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

# Backend configuration
{{- $needGeoip := or .Values.geoip.enabled (and .Values.config.luaRecords.enabled .Values.config.luaRecords.geoipDatabaseFiles) }}
{{- if eq .Values.database.type "postgresql" }}
launch={{ if $needGeoip }}geoip,{{ end }}gpgsql
gpgsql-host={{ include "powerdns-auth.databaseHost" . }}
gpgsql-port={{ include "powerdns-auth.databasePort" . }}
gpgsql-dbname={{ include "powerdns-auth.databaseName" . }}
gpgsql-user={{ include "powerdns-auth.databaseUsername" . }}
gpgsql-password={{ include "powerdns-auth.databasePassword" . }}
gpgsql-dnssec=yes
{{- /* NOTE: gpgsql-prepare-statements removed in PowerDNS 5.0 - prepared statements are always enabled */}}
{{- else }}
launch={{ if $needGeoip }}geoip,{{ end }}gmysql
gmysql-host={{ include "powerdns-auth.databaseHost" . }}
gmysql-port={{ include "powerdns-auth.databasePort" . }}
gmysql-dbname={{ include "powerdns-auth.databaseName" . }}
gmysql-user={{ include "powerdns-auth.databaseUsername" . }}
gmysql-password={{ include "powerdns-auth.databasePassword" . }}
gmysql-dnssec=yes
gmysql-timeout={{ .Values.database.mysql.timeout }}
{{- end }}

{{- if $needGeoip }}
# GeoIP backend configuration
{{- if and .Values.config.luaRecords.enabled .Values.config.luaRecords.geoipDatabaseFiles }}
geoip-database-files={{ join " " .Values.config.luaRecords.geoipDatabaseFiles }}
{{- else if .Values.geoip.enabled }}
geoip-database-files={{ join " " .Values.geoip.databases }}
{{- end }}
{{- if .Values.geoipZones.enabled }}
# Zones file from ConfigMap (either empty for LUA Records or with actual zones)
geoip-zones-file=/etc/pdns/geoip-zones.yaml
{{- else if and .Values.geoip.enabled .Values.geoip.zonesFile }}
geoip-zones-file={{ .Values.geoip.zonesFile }}
{{- end }}
{{- if and .Values.geoip.enabled .Values.geoip.dnssecKeydir }}
geoip-dnssec-keydir={{ .Values.geoip.dnssecKeydir }}
{{- end }}
{{- end }}

{{- if .Values.webserver.enabled }}
# Webserver / API configuration
webserver=yes
webserver-address={{ .Values.webserver.address }}
webserver-port={{ .Values.webserver.port }}
webserver-allow-from={{ .Values.webserver.allowFrom }}
{{- if .Values.webserver.password }}
webserver-password={{ .Values.webserver.password }}
{{- end }}
api=yes
{{- if .Values.webserver.apiKey }}
api-key={{ .Values.webserver.apiKey }}
{{- end }}
{{- end }}

{{- range $key, $value := .Values.config.extra }}
{{ $key }}={{ $value }}
{{- end }}
{{- end -}}

{{/*
Compile all warnings into a single message.
*/}}
{{- define "powerdns-auth.validateValues" -}}
{{- $messages := list -}}
{{- $messages := append $messages (include "powerdns-auth.validateValues.database" .) -}}
{{- $messages := append $messages (include "powerdns-auth.validateValues.geoip" .) -}}
{{- $messages := append $messages (include "powerdns-auth.validateValues.luaRecords" .) -}}
{{- $messages := append $messages (include "powerdns-auth.validateValues.geoipUpdate" .) -}}
{{- $messages := without $messages "" -}}
{{- $message := join "\n" $messages -}}
{{- if $message -}}
{{-   printf "\nVALUES VALIDATION:\n%s" $message | fail -}}
{{- end -}}
{{- end -}}

{{/*
Validate values of PowerDNS Auth - Database
*/}}
{{- define "powerdns-auth.validateValues.database" -}}
{{- if not (or (eq .Values.database.type "postgresql") (eq .Values.database.type "mysql")) -}}
powerdns-auth: database.type
    Invalid database type. Valid values are "postgresql" or "mysql".
{{- end -}}
{{- if and (not .Values.database.existingSecret.enabled) (not (include "powerdns-auth.databaseHost" .)) -}}
powerdns-auth: database host
    You must provide a database host. Set database.postgresql.host or database.mysql.host.
{{- end -}}
{{- end -}}

{{/*
Validate values of PowerDNS Auth - GeoIP
*/}}
{{- define "powerdns-auth.validateValues.geoip" -}}
{{- if and .Values.geoip.enabled (not .Values.geoipVolume.enabled) -}}
powerdns-auth: geoip
    GeoIP backend is enabled but geoipVolume is not enabled. You must provide GeoIP database files.
{{- end -}}
{{- end -}}

{{/*
Validate values of PowerDNS Auth - LUA Records
*/}}
{{- define "powerdns-auth.validateValues.luaRecords" -}}
{{- if .Values.config.luaRecords.enabled -}}
{{- if and .Values.config.luaRecords.geoipDatabaseFiles (not .Values.geoipVolume.enabled) -}}
powerdns-auth: luaRecords
    LUA records with GeoIP functions enabled but geoipVolume is not enabled.
    You must mount GeoIP database files for country(), continent(), pickclosest() functions.
    Set geoipVolume.enabled=true and configure the volume source.
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Validate values of PowerDNS Auth - GeoIP Update
*/}}
{{- define "powerdns-auth.validateValues.geoipUpdate" -}}
{{- if .Values.geoipUpdate.enabled -}}
{{- if not .Values.geoipVolume.enabled -}}
powerdns-auth: geoipUpdate
    GeoIP update CronJob is enabled but geoipVolume is not enabled.
    Set geoipVolume.enabled=true to provide storage for GeoIP databases.
{{- end -}}
{{- if and (not .Values.geoipUpdate.existingSecret.enabled) (not .Values.geoipUpdate.accountId) -}}
powerdns-auth: geoipUpdate
    GeoIP update requires MaxMind account credentials.
    Set geoipUpdate.accountId and geoipUpdate.licenseKey, or use geoipUpdate.existingSecret.
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Return the GeoIP update image name
*/}}
{{- define "powerdns-auth.geoipUpdate.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.geoipUpdate.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the GeoIP update secret name
*/}}
{{- define "powerdns-auth.geoipUpdate.secretName" -}}
{{- if .Values.geoipUpdate.existingSecret.enabled -}}
    {{- .Values.geoipUpdate.existingSecret.name -}}
{{- else -}}
    {{- printf "%s-geoip-credentials" (include "common.names.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
GeoIP Update Job Pod Spec - shared between Job and CronJob
*/}}
{{- define "powerdns-auth.geoipUpdate.podSpec" -}}
{{- include "powerdns-auth.imagePullSecrets" . | nindent 0 }}
serviceAccountName: {{ template "powerdns-auth.serviceAccountName" . }}
restartPolicy: {{ .Values.geoipUpdate.restartPolicy | default "OnFailure" }}
{{- if .Values.geoipUpdate.podSecurityContext.enabled }}
securityContext: {{- include "common.compatibility.renderSecurityContext" (dict "secContext" .Values.geoipUpdate.podSecurityContext "context" $) | nindent 2 }}
{{- end }}
{{- if .Values.geoipUpdate.nodeSelector }}
nodeSelector: {{- include "common.tplvalues.render" ( dict "value" .Values.geoipUpdate.nodeSelector "context" $) | nindent 2 }}
{{- end }}
{{- if .Values.geoipUpdate.tolerations }}
tolerations: {{- include "common.tplvalues.render" (dict "value" .Values.geoipUpdate.tolerations "context" .) | nindent 2 }}
{{- end }}
{{- if .Values.geoipUpdate.affinity }}
affinity: {{- include "common.tplvalues.render" ( dict "value" .Values.geoipUpdate.affinity "context" $) | nindent 2 }}
{{- end }}
initContainers:
  # Step 1: Download GeoIP databases from MaxMind
  - name: geoip-download
    image: {{ include "powerdns-auth.geoipUpdate.image" . }}
    imagePullPolicy: {{ .Values.geoipUpdate.image.pullPolicy }}
    {{- if .Values.geoipUpdate.containerSecurityContext.enabled }}
    securityContext: {{- include "common.compatibility.renderSecurityContext" (dict "secContext" .Values.geoipUpdate.containerSecurityContext "context" $) | nindent 6 }}
    {{- end }}
    env:
      - name: GEOIPUPDATE_ACCOUNT_ID
        valueFrom:
          secretKeyRef:
            name: {{ include "powerdns-auth.geoipUpdate.secretName" . }}
            key: {{ .Values.geoipUpdate.existingSecret.keys.accountId | default "account-id" }}
      - name: GEOIPUPDATE_LICENSE_KEY
        valueFrom:
          secretKeyRef:
            name: {{ include "powerdns-auth.geoipUpdate.secretName" . }}
            key: {{ .Values.geoipUpdate.existingSecret.keys.licenseKey | default "license-key" }}
      - name: GEOIPUPDATE_EDITION_IDS
        value: {{ join " " .Values.geoipUpdate.editionIds | quote }}
      {{- if .Values.geoipUpdate.host }}
      - name: GEOIPUPDATE_HOST
        value: {{ .Values.geoipUpdate.host | quote }}
      {{- end }}
      {{- if .Values.geoipUpdate.proxy }}
      - name: GEOIPUPDATE_PROXY
        value: {{ .Values.geoipUpdate.proxy | quote }}
      {{- end }}
      {{- if .Values.geoipUpdate.proxyUserPassword }}
      - name: GEOIPUPDATE_PROXY_USER_PASSWORD
        valueFrom:
          secretKeyRef:
            name: {{ include "powerdns-auth.geoipUpdate.secretName" . }}
            key: {{ .Values.geoipUpdate.existingSecret.keys.proxyUserPassword | default "proxy-user-password" }}
      {{- end }}
      {{- if .Values.geoipUpdate.preserveFileTimes }}
      - name: GEOIPUPDATE_PRESERVE_FILE_TIMES
        value: "1"
      {{- end }}
      {{- if .Values.geoipUpdate.verbose }}
      - name: GEOIPUPDATE_VERBOSE
        value: "1"
      {{- end }}
      - name: GEOIPUPDATE_DB_DIR
        value: {{ .Values.geoipUpdate.databaseDirectory | default "/usr/share/GeoIP" | quote }}
      {{- if .Values.geoipUpdate.extraEnvVars }}
      {{- include "common.tplvalues.render" (dict "value" .Values.geoipUpdate.extraEnvVars "context" $) | nindent 6 }}
      {{- end }}
    {{- if .Values.geoipUpdate.resources }}
    resources: {{- toYaml .Values.geoipUpdate.resources | nindent 6 }}
    {{- else if ne .Values.geoipUpdate.resourcesPreset "none" }}
    resources: {{- include "common.resources.preset" (dict "type" .Values.geoipUpdate.resourcesPreset) | nindent 6 }}
    {{- end }}
    volumeMounts:
      - name: geoip-data
        mountPath: {{ .Values.geoipUpdate.databaseDirectory | default "/usr/share/GeoIP" }}
      {{- if .Values.geoipUpdate.extraVolumeMounts }}
      {{- include "common.tplvalues.render" (dict "value" .Values.geoipUpdate.extraVolumeMounts "context" $) | nindent 6 }}
      {{- end }}
containers:
  {{- if .Values.geoipUpdate.autoReload.enabled }}
  # Step 2: Calculate hash and update ConfigMap to trigger Pod rolling update
  - name: hash-update
    image: {{ .Values.geoipUpdate.autoReload.image.registry }}/{{ .Values.geoipUpdate.autoReload.image.repository }}:{{ .Values.geoipUpdate.autoReload.image.tag }}
    imagePullPolicy: {{ .Values.geoipUpdate.autoReload.image.pullPolicy | default "IfNotPresent" }}
    securityContext:
      runAsUser: 1000
      runAsGroup: 1000
      runAsNonRoot: true
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL
    env:
      - name: NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
      - name: CONFIGMAP_NAME
        value: {{ include "common.names.fullname" . }}-geoip-hash
      - name: GEOIP_DIR
        value: {{ .Values.geoipUpdate.databaseDirectory | default "/usr/share/GeoIP" | quote }}
    command:
      - /bin/sh
      - -c
      - |
        set -e
        
        echo "=== GeoIP Hash Update ==="
        echo "Directory: ${GEOIP_DIR}"
        
        # Check if any mmdb files exist (download succeeded)
        MMDB_COUNT=$(find ${GEOIP_DIR} -name "*.mmdb" -type f 2>/dev/null | wc -l)
        if [ "${MMDB_COUNT}" -eq 0 ]; then
          echo "ERROR: No .mmdb files found in ${GEOIP_DIR}"
          echo "Download may have failed. Skipping hash update."
          exit 1
        fi
        
        echo "Found ${MMDB_COUNT} mmdb file(s)"
        
        # Calculate combined hash of all mmdb files
        NEW_HASH=$(find ${GEOIP_DIR} -name "*.mmdb" -type f -exec sha256sum {} \; | sort | sha256sum | cut -d' ' -f1)
        echo "New hash: ${NEW_HASH}"
        
        # Get current hash from ConfigMap
        CURRENT_HASH=$(kubectl get configmap ${CONFIGMAP_NAME} -n ${NAMESPACE} -o jsonpath='{.data.geoip-hash}' 2>/dev/null || echo "")
        echo "Current hash: ${CURRENT_HASH:-<not set>}"
        
        # Compare hashes
        if [ "${NEW_HASH}" = "${CURRENT_HASH}" ]; then
          echo "Hash unchanged. No update needed."
          echo "GeoIP databases are already up to date."
          exit 0
        fi
        
        # Update ConfigMap with new hash
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        echo "Hash changed. Updating ConfigMap ${CONFIGMAP_NAME}..."
        
        kubectl patch configmap ${CONFIGMAP_NAME} -n ${NAMESPACE} \
          --type merge \
          -p "{\"data\":{\"geoip-hash\":\"${NEW_HASH}\",\"updated-at\":\"${TIMESTAMP}\",\"previous-hash\":\"${CURRENT_HASH}\"}}"
        
        echo "ConfigMap updated successfully."
        echo "PowerDNS pods will perform rolling update to load new GeoIP databases."
    resources:
      requests:
        cpu: "50m"
        memory: "32Mi"
      limits:
        cpu: "100m"
        memory: "64Mi"
    volumeMounts:
      - name: geoip-data
        mountPath: {{ .Values.geoipUpdate.databaseDirectory | default "/usr/share/GeoIP" }}
        readOnly: true
  {{- else }}
  # No auto-reload: just a placeholder container that completes successfully
  - name: complete
    image: {{ .Values.geoipUpdate.autoReload.image.registry | default "docker.io" }}/{{ .Values.geoipUpdate.autoReload.image.repository | default "busybox" }}:{{ .Values.geoipUpdate.autoReload.image.tag | default "latest" }}
    command: ["sh", "-c", "echo 'GeoIP databases updated. Auto-reload is disabled.'"]
    securityContext:
      runAsUser: 1000
      runAsNonRoot: true
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
    resources:
      requests:
        cpu: "10m"
        memory: "8Mi"
      limits:
        cpu: "50m"
        memory: "16Mi"
  {{- end }}
volumes:
  - name: geoip-data
    {{- if eq .Values.geoipVolume.type "pvc" }}
    persistentVolumeClaim:
      claimName: {{ .Values.geoipVolume.pvc.claimName }}
    {{- else if eq .Values.geoipVolume.type "hostPath" }}
    hostPath:
      path: {{ .Values.geoipVolume.hostPath.path }}
      type: DirectoryOrCreate
    {{- else }}
    emptyDir: {}
    {{- end }}
  {{- if .Values.geoipUpdate.extraVolumes }}
  {{- include "common.tplvalues.render" (dict "value" .Values.geoipUpdate.extraVolumes "context" $) | nindent 2 }}
  {{- end }}
{{- end -}}
