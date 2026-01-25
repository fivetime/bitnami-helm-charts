#!/bin/bash
# Copyright The Rook Authors.
# SPDX-License-Identifier: Apache-2.0
#
# Generate kubeconfig for ceph-consumer to access provider cluster
#
# Prerequisites:
#   1. kubectl configured to access the PROVIDER cluster
#   2. provider-rbac.yaml already applied:
#      kubectl apply -f provider-rbac.yaml
#
# Usage:
#   ./generate-provider-kubeconfig.sh [output-file]
#
# Arguments:
#   output-file  Output file path, use "-" for stdout (default: provider-kubeconfig.yaml)
#
# Examples:
#   ./generate-provider-kubeconfig.sh                           # To default file
#   ./generate-provider-kubeconfig.sh -                         # To stdout
#   ./generate-provider-kubeconfig.sh /path/to/kubeconfig.yaml  # Custom path
#
# Environment variables:
#   CEPH_NAMESPACE      Rook-Ceph namespace (default: rook-ceph)
#   CEPH_SECRET_NAME    Token secret name (default: ceph-consumer-reader-token)

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Configuration
NAMESPACE="${CEPH_NAMESPACE:-rook-ceph}"
SECRET_NAME="${CEPH_SECRET_NAME:-ceph-consumer-reader-token}"
OUTPUT_FILE="${1:-provider-kubeconfig.yaml}"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is required but not installed"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    log_error "Cannot connect to Kubernetes cluster"
    exit 1
fi

log_info "Cluster: $(kubectl config current-context)"

# Check secret exists
if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
    log_error "Secret ${SECRET_NAME} not found in namespace ${NAMESPACE}"
    log_error "Please apply provider-rbac.yaml first:"
    log_error "  kubectl apply -f provider-rbac.yaml"
    exit 1
fi

# Get cluster info
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CLUSTER_CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

if [ -z "$CLUSTER_CA" ]; then
    CA_FILE=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.certificate-authority}')
    if [ -n "$CA_FILE" ] && [ -f "$CA_FILE" ]; then
        CLUSTER_CA=$(base64 -w0 < "$CA_FILE" 2>/dev/null || base64 < "$CA_FILE" | tr -d '\n')
    else
        log_error "Cannot find cluster CA certificate"
        exit 1
    fi
fi

# Get token
log_info "Reading token from secret ${SECRET_NAME}..."
TOKEN=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.token}' | base64 -d)

if [ -z "$TOKEN" ]; then
    log_error "Token not found in secret (controller may still be populating it)"
    log_error "Wait a moment and try again"
    exit 1
fi

# Generate kubeconfig
KUBECONFIG_CONTENT="apiVersion: v1
kind: Config
clusters:
  - name: ${CLUSTER_NAME}
    cluster:
      server: ${CLUSTER_SERVER}
      certificate-authority-data: ${CLUSTER_CA}
contexts:
  - name: ceph-consumer@${CLUSTER_NAME}
    context:
      cluster: ${CLUSTER_NAME}
      user: ceph-consumer
      namespace: ${NAMESPACE}
current-context: ceph-consumer@${CLUSTER_NAME}
users:
  - name: ceph-consumer
    user:
      token: ${TOKEN}"

# Output
if [ "$OUTPUT_FILE" = "-" ]; then
    echo "$KUBECONFIG_CONTENT"
else
    echo "$KUBECONFIG_CONTENT" > "$OUTPUT_FILE"
    chmod 600 "$OUTPUT_FILE"
    log_info "Written to: ${OUTPUT_FILE}"
    log_info "Token is permanent (never expires)"
    echo ""
    log_info "Next steps on consumer cluster:"
    echo "  helm install ceph-consumer ./ceph-consumer \\"
    echo "    --namespace rook-ceph \\"
    echo "    --set-file provider.kubeconfig=${OUTPUT_FILE}"
fi
