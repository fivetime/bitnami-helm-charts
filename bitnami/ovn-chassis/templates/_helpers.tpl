{{- /*
Copyright Broadcom, Inc. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/*
Return the proper OVN image name
*/}}
{{- define "ovn-chassis.image" -}}
{{ include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) }}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "ovn-chassis.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.image) "context" $) -}}
{{- end -}}

{{/*
Name of the ServiceAccount
*/}}
{{- define "ovn-chassis.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{ default (include "common.names.fullname" .) .Values.serviceAccount.name }}
{{- else -}}
    {{ default "default" .Values.serviceAccount.name }}
{{- end -}}
{{- end -}}

{{/*
ovn-bridge-mappings.

Never renders empty. An empty mapping is not merely useless, it is a startup failure:
`ovs-vsctl set open . external_ids:ovn-bridge-mappings=` (no value after the `=`) is a
syntax error, so the container would CrashLoop with a message that says nothing about
bridge mappings. The scripts guard against this too - see `set_ext` in the entrypoint -
but keeping the rendered value non-empty means the guard never has to fire.
*/}}
{{- define "ovn-chassis.bridgeMappings" -}}
{{- if .Values.ovn.provider.bridgeMappings -}}
{{ .Values.ovn.provider.bridgeMappings }}
{{- else -}}
{{ printf "%s:%s" .Values.ovn.provider.physicalNetwork .Values.ovn.provider.bridge }}
{{- end -}}
{{- end -}}

{{/*
ovn-cms-options.

Assembled from the gateway flag, the availability zone and any extras. May legitimately
be empty - a plain compute chassis advertises no CMS options at all - which the
entrypoint handles by deleting the key rather than writing `ovn-cms-options=`.
*/}}
{{- define "ovn-chassis.cmsOptions" -}}
{{- $opts := list -}}
{{- if .Values.ovn.gateway.enabled -}}
{{- $opts = append $opts "enable-chassis-as-gw" -}}
{{- end -}}
{{- if .Values.ovn.availabilityZones -}}
{{- $opts = append $opts (printf "availability-zones=%s" .Values.ovn.availabilityZones) -}}
{{- end -}}
{{- if .Values.ovn.extraCMSOptions -}}
{{- $opts = append $opts .Values.ovn.extraCMSOptions -}}
{{- end -}}
{{ join "," $opts }}
{{- end -}}

{{/*
Environment shared by every container.

NODE_NAME and NODE_IP come from the Downward API rather than from `hostname` or from
inspecting interfaces: they are what Kubernetes itself believes about this node, which is
also what the rest of the stack (Neutron's chassis lookup, kubetron's node-to-chassis
mapping) will use.
*/}}
{{- define "ovn-chassis.commonEnv" -}}
- name: NODE_NAME
  valueFrom:
    fieldRef:
      fieldPath: spec.nodeName
- name: NODE_IP
  valueFrom:
    fieldRef:
      fieldPath: status.hostIP
{{- if .Values.extraEnvVars }}
{{- include "common.tplvalues.render" (dict "value" .Values.extraEnvVars "context" $) }}
{{- end }}
{{- end -}}

{{- define "ovn-chassis.envFrom" -}}
{{- if or .Values.extraEnvVarsCM .Values.extraEnvVarsSecret }}
envFrom:
  {{- if .Values.extraEnvVarsCM }}
  - configMapRef:
      name: {{ .Values.extraEnvVarsCM }}
  {{- end }}
  {{- if .Values.extraEnvVarsSecret }}
  - secretRef:
      name: {{ .Values.extraEnvVarsSecret }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
Volume mounts shared by every container.

The rundir is a hostPath, not an emptyDir, and that is the integration surface: ovs-cni,
`ovs-vsctl` run by hand on the node, and any other pod that needs the OVS socket all find
it at this path. An emptyDir here would work for this chart alone and break everything
around it.
*/}}
{{- define "ovn-chassis.commonVolumeMounts" -}}
- name: scripts
  mountPath: /opt/ovn
- name: ovs-run
  mountPath: {{ .Values.openvswitch.runPath }}
  mountPropagation: Bidirectional
{{- if .Values.extraVolumeMounts }}
{{- include "common.tplvalues.render" (dict "value" .Values.extraVolumeMounts "context" $) }}
{{- end }}
{{- end -}}

{{/*
Canonicalise a database remote.

`tcp://host:6642` is what people write, because that is how ovn-kubernetes and most docs
spell it; `tcp:host:6642` is what ovsdb actually parses. Accept both and emit the second,
so a working-looking address does not fail at connect time.
*/}}
{{- define "ovn-chassis.sbAddress" -}}
{{ .Values.ovn.southbound.address | replace "//" "" }}
{{- end -}}

{{- define "ovn-chassis.nbAddress" -}}
{{ .Values.ovn.northbound.address | replace "//" "" }}
{{- end -}}

{{/*
Validate the values that cannot be defaulted.
*/}}
{{- define "ovn-chassis.validateValues" -}}
{{- $messages := list -}}
{{- $messages = append $messages (include "ovn-chassis.validateValues.southbound" .) -}}
{{- $messages = append $messages (include "ovn-chassis.validateValues.gateway" .) -}}
{{- $messages = append $messages (include "ovn-chassis.validateValues.tls" .) -}}
{{- $messages = without $messages "" -}}
{{- $message := join "\n" $messages -}}
{{- if $message -}}
{{- printf "\nVALUES VALIDATION:\n%s" $message | fail -}}
{{- end -}}
{{- end -}}

{{- define "ovn-chassis.validateValues.southbound" -}}
{{- if not .Values.ovn.southbound.address -}}
ovn-chassis: ovn.southbound.address is required.

    ovn-controller has nothing to do without a Southbound database to connect to. Point
    it at the OVN you already run - the chart never deploys one.

      --set ovn.southbound.address=tcp://SB_HOST:6642

    Accepts a comma-separated list for a RAFT cluster, an ovsdb-relay address, or an
    ssl: address together with ovn.tls.*
{{- end -}}
{{- end -}}

{{- define "ovn-chassis.validateValues.gateway" -}}
{{- if and .Values.ovn.gateway.enabled (not .Values.ovn.provider.createBridge) (not .Values.ovn.provider.bridgeMappings) -}}
ovn-chassis: ovn.gateway.enabled is on but this chart will not create the provider bridge.

    These nodes will advertise `enable-chassis-as-gw`, so Neutron may schedule tenant
    routers' external gateway ports onto them. If bridge {{ .Values.ovn.provider.bridge }}
    does not already exist on EVERY targeted node, that traffic is black-holed - and it
    fails silently: the port binds and the router reports healthy.

    Either prepare the bridge out of band and re-run with
      --set ovn.provider.bridgeMappings={{ .Values.ovn.provider.physicalNetwork }}:{{ .Values.ovn.provider.bridge }}
    to acknowledge it, or let the chart create it with
      --set ovn.provider.createBridge=true --set ovn.provider.interface=<nic-without-ip>
{{- end -}}
{{- end -}}

{{- define "ovn-chassis.validateValues.tls" -}}
{{- if and .Values.ovn.tls.enabled (not .Values.ovn.tls.existingSecret) -}}
ovn-chassis: ovn.tls.enabled requires ovn.tls.existingSecret (keys: tls.crt, tls.key, ca.crt).
{{- end -}}
{{- end -}}
