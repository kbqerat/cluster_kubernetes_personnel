#!/usr/bin/env bash
# Extract the demo mTLS client cert (issued by cert-manager) to local files.
set -euo pipefail
: "${KUBECONFIG:?export KUBECONFIG=\$PWD/kubeconfig first}"

kubectl -n demo get secret demo-client-cert -o jsonpath='{.data.tls\.crt}' | base64 -d > demo-client.crt
kubectl -n demo get secret demo-client-cert -o jsonpath='{.data.tls\.key}' | base64 -d > demo-client.key
kubectl -n demo get secret demo-client-cert -o jsonpath='{.data.ca\.crt}'  | base64 -d > homelab-ca.crt

cat <<'EOF'
Wrote demo-client.crt, demo-client.key, homelab-ca.crt

  # should succeed (200, prints request headers):
  curl -sS --cacert homelab-ca.crt --cert demo-client.crt --key demo-client.key \
    https://whoami-mtls.192-168-252-240.sslip.io

  # should fail at the TLS handshake (no client cert):
  curl -sS --cacert homelab-ca.crt https://whoami-mtls.192-168-252-240.sslip.io
EOF
