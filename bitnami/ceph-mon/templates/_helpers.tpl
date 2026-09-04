{{/*
Copyright fivetime.
SPDX-License-Identifier: Apache-2.0
*/}}

{{/*
Return the proper ceph image name
*/}}
{{- define "ceph-mon.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "ceph-mon.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.image) "context" $) -}}
{{- end -}}

{{/*
Fullname of a single mon instance: <release fullname>-<mon name>
*/}}
{{- define "ceph-mon.instanceFullname" -}}
{{- printf "%s-%s" (include "common.names.fullname" .context) .mon.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Selector labels for one mon instance (Service -> Pod)
*/}}
{{- define "ceph-mon.instanceSelectorLabels" -}}
app.kubernetes.io/component: mon
ceph-mon.fivetime.io/mon: {{ .mon.name | quote }}
{{- end -}}

{{/*
Format an address the way Ceph's entity_addr_t parser expects: an IPv6 literal
MUST be bracketed. Without brackets the parser's IPv6 character scan swallows a
trailing ":<port>" into the address itself, inet_pton() still succeeds, and you
silently get a DIFFERENT address with port 0 -- no error is reported anywhere
("v2:fc00:c:1:2:3::21:3300" parses as fc00:c:1:2:3:0:21:3300 port 0).
See entity_addr_t::parse in ceph src/msg/msg_types.cc.
Usage: include "ceph-mon.cephAddr" $vip
*/}}
{{- define "ceph-mon.cephAddr" -}}
{{- if contains ":" . -}}
[{{ . }}]
{{- else -}}
{{ . }}
{{- end -}}
{{- end -}}

{{/*
Compile all warnings into a single message.
*/}}
{{- define "ceph-mon.validateValues" -}}
{{- $messages := list -}}
{{- $messages := append $messages (include "ceph-mon.validateValues.mons" .) -}}
{{- $messages := append $messages (include "ceph-mon.validateValues.bootstrap" .) -}}
{{- $messages := without $messages "" -}}
{{- $message := join "\n" $messages -}}
{{- if $message -}}
{{-   printf "\nVALUES VALIDATION:\n%s" $message | fail -}}
{{- end -}}
{{- end -}}

{{/*
Validate mon instances
*/}}
{{- define "ceph-mon.validateValues.mons" -}}
{{- if not .Values.mons -}}
ceph-mon: mons
    At least one mon instance must be defined in `mons`. Each entry needs
    `name` and `vip`.
{{- else -}}
{{- range .Values.mons -}}
{{- if or (not .name) (not .vip) -}}
ceph-mon: mons
    Every entry in `mons` requires `name` and `vip`.
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Validate bootstrap configuration
*/}}
{{- define "ceph-mon.validateValues.bootstrap" -}}
{{- if not .Values.cluster.configSecretName -}}
ceph-mon: cluster.configSecretName
    `cluster.configSecretName` must point to a secret with the current mon
    addresses (`mon_host` / `mon_initial_members`), so a new mon can find the
    quorum on first boot. Rook maintains `rook-ceph-config`; on a foreign
    cluster create an equivalent secret by hand.
{{- end -}}
{{- end -}}
