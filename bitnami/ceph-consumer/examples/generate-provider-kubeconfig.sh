#!/bin/bash
# Copyright The Rook Authors.
# SPDX-License-Identifier: Apache-2.0
#
# Generate kubeconfig for ceph-consumer to access provider cluster
#
# Prerequisites:
#   1. kubectl configured to access the PROVIDER cluster
#   2. provider-rbac.yaml already applied
#
# Usage:
#   ./generate-provider-kubeconfig.sh [output-file] [token-duration]
#
# Examples:
#   ./generate-provider-kubeconfig.sh                           # Output to stdout, 1 year token
#   ./generate-provider-kubeconfig.sh provider-kubeconfig.yaml  # Output to file
#   ./generate-provider-kubeconfig.sh - 8760h                   # 1 year token to stdout

set -euo pipefail

OUTPUT_FILE="${1:--}"
TOKEN_DURATION="${2:-8760h}"  # Default: 1 year

NAMESPACE="rook-ceph"
SERVICE_ACCOUNT="ceph-consumer-reader"

# Get cluster info
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CLUSTER_CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# If CA is not embedded, read from file
if [ -z "$CLUSTER_CA" ]; then
    CA_FILE=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.certificate-authority}')
    if [ -n "$CA_FILE" ] && [ -f "$CA_FILE" ]; then
        CLUSTER_CA=$(base64 -w0 < "$CA_FILE")
    else
        echo "Error: Cannot find cluster CA certificate" >&2
        exit 1
    fi
fi

# Generate token
echo "Generating token for ServiceAccount ${SERVICE_ACCOUNT} (duration: ${TOKEN_DURATION})..." >&2
TOKEN=$(kubectl create token "$SERVICE_ACCOUNT" -n "$NAMESPACE" --duration="$TOKEN_DURATION")

# Generate kubeconfig
KUBECONFIG_CONTENT=$(cat <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: ${CLUSTER_NAME}
    cluster:
      server: ${CLUSTER_SERVER}
      certificate-authority-data: ${CLUSTER_CA}
contexts:
  - name: ceph-consumer-reader@${CLUSTER_NAME}
    context:
      cluster: ${CLUSTER_NAME}
      user: ceph-consumer-reader
      namespace: ${NAMESPACE}
current-context: ceph-consumer-reader@${CLUSTER_NAME}
users:
  - name: ceph-consumer-reader
    user:
      token: ${TOKEN}
EOF
)

# Output
if [ "$OUTPUT_FILE" = "-" ]; then
    echo "$KUBECONFIG_CONTENT"
else
    echo "$KUBECONFIG_CONTENT" > "$OUTPUT_FILE"
    echo "Kubeconfig written to: $OUTPUT_FILE" >&2
    echo "Token expires in: $TOKEN_DURATION" >&2
fi
