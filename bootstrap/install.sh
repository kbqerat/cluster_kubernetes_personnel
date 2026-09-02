#!/usr/bin/env bash
# Phase 4 — one-time ArgoCD bootstrap.
# After this, everything (including ArgoCD itself) is managed from Git.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${KUBECONFIG:?export KUBECONFIG=\$PWD/kubeconfig first}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-10.6.4}"

if grep -rq '__GITOPS_REPO_URL__' argocd platform apps; then
  echo "ERROR: manifests still contain __GITOPS_REPO_URL__." >&2
  echo "Run:  make set-repo URL=https://github.com/<you>/cluster_kubernetes_personnel.git" >&2
  exit 1
fi

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --version "$ARGOCD_CHART_VERSION" \
  -f bootstrap/argocd/values.yaml \
  --wait --timeout 10m

kubectl apply -f argocd/root.yaml

cat <<'EOF'

ArgoCD is installed and the root app-of-apps is applied.

  watch sync:   kubectl -n argocd get applications -w
  admin pass:   make argocd-password
  UI (after Traefik + DNS are up):  https://argocd.192-168-252-240.sslip.io

First sync takes a few minutes (CRDs, cert-manager webhook, MetalLB).
EOF
