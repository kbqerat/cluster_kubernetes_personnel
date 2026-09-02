#!/usr/bin/env bash
# Phase 2 — install k3s on the Multipass VMs created by Terraform.
#   - server node: k3s with Traefik + servicelb DISABLED (we install our own later)
#   - agent nodes: joined to the server
# Writes a merged kubeconfig to ./kubeconfig with context "homelab".
set -euo pipefail

SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_USER="${SSH_USER:-ubuntu}"
K3S_CHANNEL="${K3S_CHANNEL:-stable}"
KUBECONFIG_OUT="${KUBECONFIG_OUT:-$PWD/kubeconfig}"
CONTEXT="${CONTEXT:-homelab}"

command -v k3sup >/dev/null || { echo "k3sup not found (brew install k3sup)"; exit 1; }
command -v jq >/dev/null    || { echo "jq not found"; exit 1; }

ip_for() {
  multipass info "$1" --format json | jq -r --arg n "$1" '.info[$n].ipv4[0] // empty'
}

assert_unique_ips() {
  local dupes
  dupes="$(multipass list --format json \
    | jq -r '[.list[] | select(.name|startswith("k3s-")) | .ipv4[0] // empty]
             | group_by(.) | map(select(length>1)) | flatten | unique | .[]')"
  if [ -n "$dupes" ]; then
    echo "ERROR: duplicate node IPs detected: $dupes" >&2
    echo "Fix with:  make down && make up   (recreates VMs serially)" >&2
    multipass list >&2
    exit 1
  fi
}
assert_unique_ips

wait_for_ip() {
  local name="$1" ip="" tries=0
  until [ -n "$ip" ] || [ "$tries" -ge 30 ]; do
    ip="$(ip_for "$name" || true)"
    [ -n "$ip" ] && break
    sleep 3; tries=$((tries + 1))
  done
  [ -n "$ip" ] || { echo "timed out waiting for IP of $name" >&2; return 1; }
  printf '%s' "$ip"
}

wait_for_ssh() {
  local ip="$1" tries=0
  until ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
        -i "$SSH_KEY" "$SSH_USER@$ip" true 2>/dev/null || [ "$tries" -ge 40 ]; do
    sleep 3; tries=$((tries + 1))
  done
  ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
      -i "$SSH_KEY" "$SSH_USER@$ip" true 2>/dev/null \
    || { echo "SSH not ready on $ip (cloud-init may still be running)" >&2; return 1; }
}

SERVER_NAME="${SERVER_NAME:-k3s-server}"
SERVER_IP="$(wait_for_ip "$SERVER_NAME")"
echo "==> server $SERVER_NAME @ $SERVER_IP"
wait_for_ssh "$SERVER_IP"

k3sup install \
  --ip "$SERVER_IP" \
  --user "$SSH_USER" \
  --ssh-key "$SSH_KEY" \
  --k3s-channel "$K3S_CHANNEL" \
  --k3s-extra-args "--disable traefik --disable servicelb --node-name $SERVER_NAME --write-kubeconfig-mode 644" \
  --local-path "$KUBECONFIG_OUT" \
  --context "$CONTEXT"

AGENTS="$(multipass list --format json | jq -r '.list[].name | select(startswith("k3s-agent"))')"
for node in $AGENTS; do
  AGENT_IP="$(wait_for_ip "$node")"
  echo "==> joining $node @ $AGENT_IP"
  wait_for_ssh "$AGENT_IP"
  k3sup join \
    --ip "$AGENT_IP" \
    --server-ip "$SERVER_IP" \
    --user "$SSH_USER" \
    --ssh-key "$SSH_KEY" \
    --k3s-channel "$K3S_CHANNEL" \
    --k3s-extra-args "--node-name $node"
done

echo
echo "kubeconfig written to: $KUBECONFIG_OUT"
echo "run:  export KUBECONFIG=$KUBECONFIG_OUT"
KUBECONFIG="$KUBECONFIG_OUT" kubectl get nodes -o wide
