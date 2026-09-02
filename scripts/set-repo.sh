#!/usr/bin/env bash
# Replace the __GITOPS_REPO_URL__ / __GITOPS_REVISION__ placeholders in every
# ArgoCD manifest with your real Git remote. Run once after creating the GitHub repo.
#   ./scripts/set-repo.sh https://github.com/<you>/cluster_kubernetes_personnel.git [branch]
set -euo pipefail
cd "$(dirname "$0")/.."

URL="${1:-$(git remote get-url origin 2>/dev/null || true)}"
REV="${2:-main}"

if [ -z "$URL" ]; then
  echo "usage: $0 <git-remote-url> [branch]   (or add an 'origin' remote first)" >&2
  exit 1
fi
# git@github.com:u/r.git -> https://github.com/u/r.git
case "$URL" in
  git@github.com:*) URL="https://github.com/${URL#git@github.com:}" ;;
esac

files="$(grep -rl -e '__GITOPS_REPO_URL__' -e '__GITOPS_REVISION__' argocd platform apps bootstrap 2>/dev/null || true)"
if [ -z "$files" ]; then
  echo "No placeholders left — already set."
  exit 0
fi
echo "$files" | while read -r f; do
  sed -i '' -e "s#__GITOPS_REPO_URL__#${URL}#g" -e "s#__GITOPS_REVISION__#${REV}#g" "$f"
  echo "  patched $f"
done
echo "repoURL = $URL"
echo "revision = $REV"
