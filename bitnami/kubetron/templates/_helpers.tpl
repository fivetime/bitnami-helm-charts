{{/*
Copyright Broadcom, Inc. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/*
Return the proper kubetron image name (used by both the manager and the apiserver, same binary bundle)
*/}}
{{- define "kubetron.image" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.image "global" .Values.global) -}}
{{- end -}}

{{/*
Return the proper etcd image name
*/}}
{{- define "kubetron.etcd.image" -}}
{{- include "common.images.image" (dict "imageRoot" .Values.apiserver.etcd.image "global" .Values.global) -}}
{{- end -}}

{{/*
Return the proper Docker Image Registry Secret Names
*/}}
{{- define "kubetron.imagePullSecrets" -}}
{{- include "common.images.renderPullSecrets" (dict "images" (list .Values.image .Values.apiserver.etcd.image) "context" $) -}}
{{- end -}}

{{/*
Name of the SHARED control plane this release attaches to. Defaults to this release's own
fullname (single-release deployments). When running one release per Neutron/OVN cluster,
the `sharedResources.create=false` releases set `controlPlaneName` to the owner's fullname
so they reuse its ServiceAccount, serving certificate and webhook Service.
*/}}
{{- define "kubetron.controlPlaneName" -}}
{{- default (include "common.names.fullname" .) .Values.controlPlaneName -}}
{{- end -}}

{{/*
Create the name of the (shared) manager service account to use
*/}}
{{- define "kubetron.serviceAccountName" -}}
{{- default (include "kubetron.controlPlaneName" .) .Values.serviceAccount.name -}}
{{- end -}}

{{/*
Shared manager webhook Service name (the MutatingWebhookConfiguration clientConfig points here)
*/}}
{{- define "kubetron.webhook.serviceName" -}}
{{- include "kubetron.controlPlaneName" . -}}
{{- end -}}

{{/*
Name of the (shared) Secret holding the manager webhook serving certificate
*/}}
{{- define "kubetron.webhook.secretName" -}}
{{- printf "%s-webhook-cert" (include "kubetron.controlPlaneName" .) -}}
{{- end -}}

{{/*
Functional label (dict) stamped on every manager pod so the SHARED webhook Service and
ServiceMonitor can select managers across releases (independent of app.kubernetes.io/instance).
*/}}
{{- define "kubetron.controlPlaneLabel" -}}
{{- dict "kubetron.network.kubevirt.io/control-plane" (include "kubetron.controlPlaneName" .) | toYaml -}}
{{- end -}}

{{/*
Aggregated apiserver fully qualified name (shared, owned by the control-plane release)
*/}}
{{- define "kubetron.apiserver.fullname" -}}
{{- printf "%s-apiserver" (include "kubetron.controlPlaneName" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Aggregated apiserver service account name
*/}}
{{- define "kubetron.apiserver.serviceAccountName" -}}
{{- if .Values.apiserver.serviceAccount.create -}}
    {{- default (include "kubetron.apiserver.fullname" .) .Values.apiserver.serviceAccount.name -}}
{{- else -}}
    {{- default "default" .Values.apiserver.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Name of the Secret holding the apiserver serving certificate
*/}}
{{- define "kubetron.apiserver.secretName" -}}
{{- printf "%s-cert" (include "kubetron.apiserver.fullname" .) -}}
{{- end -}}

{{/*
etcd (bundled) fully qualified name and headless service name
*/}}
{{- define "kubetron.etcd.fullname" -}}
{{- printf "%s-etcd" (include "kubetron.controlPlaneName" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Comma-separated etcd client endpoints for the apiserver --etcd-servers flag
*/}}
{{- define "kubetron.etcd.endpoints" -}}
{{- $fullname := include "kubetron.etcd.fullname" . -}}
{{- $ns := include "common.names.namespace" . -}}
{{- $eps := list -}}
{{- range $i := until (int .Values.apiserver.etcd.replicaCount) -}}
{{- $eps = append $eps (printf "http://%s-%d.%s.%s.svc:2379" $fullname $i $fullname $ns) -}}
{{- end -}}
{{- join "," $eps -}}
{{- end -}}

{{/*
etcd static bootstrap peer list for the --initial-cluster flag
*/}}
{{- define "kubetron.etcd.initialCluster" -}}
{{- $fullname := include "kubetron.etcd.fullname" . -}}
{{- $ns := include "common.names.namespace" . -}}
{{- $peers := list -}}
{{- range $i := until (int .Values.apiserver.etcd.replicaCount) -}}
{{- $peers = append $peers (printf "%s-%d=http://%s-%d.%s.%s.svc:2380" $fullname $i $fullname $i $fullname $ns) -}}
{{- end -}}
{{- join "," $peers -}}
{{- end -}}

{{/*
Generate (or reuse) a self-signed serving certificate. Memoized on the root context so
the CA baked into the Secret is byte-identical to the caBundle stamped into the webhook
configuration / APIService within the same render.

Usage:  {{- include "kubetron.genCerts" (dict "context" $ "service" "<svc>" "secretName" "<secret>" "cacheKey" "<key>") }}
Result: {{ (index $ "<key>").crt }} / .key / .ca   (all PEM strings)
*/}}
{{- define "kubetron.genCerts" -}}
{{- $ := .context -}}
{{- $cacheKey := .cacheKey -}}
{{- if not (index $ $cacheKey) -}}
{{- $svc := .service -}}
{{- $ns := include "common.names.namespace" $ -}}
{{- $altNames := list (printf "%s.%s.svc" $svc $ns) (printf "%s.%s.svc.cluster.local" $svc $ns) -}}
{{- $existing := lookup "v1" "Secret" $ns .secretName -}}
{{- if and $existing $existing.data (index $existing.data "tls.crt") (index $existing.data "ca.crt") -}}
{{- $_ := set $ $cacheKey (dict "crt" (index $existing.data "tls.crt" | b64dec) "key" (index $existing.data "tls.key" | b64dec) "ca" (index $existing.data "ca.crt" | b64dec)) -}}
{{- else -}}
{{- $ca := genCA (printf "%s-ca" $svc) 3650 -}}
{{- $cert := genSignedCert $svc nil $altNames 3650 $ca -}}
{{- $_ := set $ $cacheKey (dict "crt" $cert.Cert "key" $cert.Key "ca" $ca.Cert) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Compile all validation warnings into a single failure message.
*/}}
{{- define "kubetron.validateValues" -}}
{{- $messages := list -}}
{{- if and .Values.apiserver.enabled .Values.crds.install -}}
{{- $messages = append $messages "kubetron: apiserver.enabled and crds.install are both true. The aggregated apiserver serves NetworkPortClaims INSTEAD of the CRD; installing both makes the API group ambiguous. Set crds.install=false when apiserver.enabled=true — but note this ALSO removes the NetworkPortPool CRD (both are behind the same condition) and the aggregated apiserver does not serve it, so warm pools stop working while the manager still runs its pool controller." -}}
{{- end -}}
{{- if and .Values.apiserver.enabled (eq (int (mod (int .Values.apiserver.etcd.replicaCount) 2)) 0) -}}
{{- $messages = append $messages "kubetron: apiserver.etcd.replicaCount should be an odd number (1, 3 or 5) so the cluster can form a quorum." -}}
{{- end -}}
{{- if and (gt (int .Values.replicaCount) 1) (not .Values.controller.leaderElect) -}}
{{- $messages = append $messages "kubetron: replicaCount > 1 requires controller.leaderElect=true, otherwise every replica reconciles concurrently." -}}
{{- end -}}
{{- if and (not .Values.sharedResources.create) (not .Values.controlPlaneName) -}}
{{- $messages = append $messages "kubetron: sharedResources.create=false requires controlPlaneName to be set to the owner release's fullname, so this manager can find the shared ServiceAccount, serving certificate and webhook Service." -}}
{{- end -}}
{{- $messages = without $messages "" -}}
{{- $message := join "\n" $messages -}}
{{- if $message -}}
{{- printf "\nVALUES VALIDATION:\n%s" $message | fail -}}
{{- end -}}
{{- end -}}
