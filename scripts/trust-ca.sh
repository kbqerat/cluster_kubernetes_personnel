#!/usr/bin/env bash
# Add the homelab root CA to the macOS System keychain so browsers / curl
# trust every *.192-168-252-240.sslip.io certificate.
set -euo pipefail
: "${KUBECONFIG:?export KUBECONFIG=\$PWD/kubeconfig first}"

OUT="${OUT:-homelab-root-ca.crt}"
kubectl -n cert-manager get secret homelab-root-ca \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > "$OUT"

echo "Wrote $OUT"
echo "Adding to /Library/Keychains/System.keychain (needs sudo)..."
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain "$OUT"
echo "Done. Restart your browser."
