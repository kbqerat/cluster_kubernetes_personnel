# Runbook

All commands run from the repo root with `export KUBECONFIG=$PWD/kubeconfig`.

## Full bring-up (from nothing)

```bash
# 1. Infra + k3s
make init
make up                       # 3 Multipass VMs, serial
make k3s                      # k3sup installs k3s, writes ./kubeconfig
export KUBECONFIG=$PWD/kubeconfig
make nodes                    # 3x Ready

# 2. GitHub repo (once)
gh repo create cluster_kubernetes_personnel --private --source=. --remote=origin --push
make set-repo                 # rewrites __GITOPS_REPO_URL__ from 'origin', commit the result
git add -A && git commit -m "set gitops repo url" && git push

# 3. GitOps
make argocd-bootstrap         # helm install argocd + apply root app-of-apps
watch make apps               # wait for all Applications = Synced / Healthy

# 4. Trust the homelab CA + see the endpoints
make trust-ca
make urls
```

First full sync is ~5–10 min (CRDs, cert-manager webhook, Prometheus operator,
Loki PVC).

## Daily use

| Task | Command |
|------|---------|
| Cluster nodes | `make nodes` |
| ArgoCD app status | `make apps` |
| Force resync everything | `make sync` |
| ArgoCD admin password | `make argocd-password` |
| Shell into a node | `make ssh NODE=k3s-agent-1` |
| Pause the lab (keep disks) | `multipass stop --all` |
| Resume | `multipass start --all` && re-check `make nodes` |
| Destroy VMs | `make down` |

## Deploy an app the GitOps way

1. Add manifests under `apps/<name>/manifests/`.
2. Add `argocd/apps/NN-<name>.yaml` (copy `12-demo.yaml`, bump the number).
3. `git commit && git push`. ArgoCD picks it up within ~3 min (or `make sync`).

## mTLS demo

```bash
make demo-client-cert
curl -sS --cacert homelab-ca.crt --cert demo-client.crt --key demo-client.key \
  https://whoami-mtls.192-168-252-240.sslip.io          # 200 + headers
curl -sS --cacert homelab-ca.crt \
  https://whoami-mtls.192-168-252-240.sslip.io          # TLS handshake refused
```

## Lens

Add cluster → kubeconfig `./kubeconfig`, context `homelab`. Namespaces to watch:
`argocd`, `traefik`, `cert-manager`, `observability`, `metallb-system`.

---

## Known issues (macOS + Multipass)

### `EHOSTUNREACH` / "No route to host" to a VM, ARP resolves

The Multipass `vmnet` bridge wedged (usually after a fast destroy/recreate).

```bash
sudo launchctl kickstart -k system/com.canonical.multipassd
sleep 30 && ping -c2 192.168.252.5
```

### Commands from the VS Code / Claude Code terminal can't reach VMs, but Terminal.app can

macOS **Local Network** privacy. Grant it:
System Settings → Privacy & Security → Local Network → **Visual Studio Code** ON,
then fully quit and relaunch VS Code (permission is read at launch).
`ping -c2 192.168.252.5` from that terminal should then reply.

### Two VMs get the same IP

Multipass DHCP race on parallel `multipass launch`. `make up` already forces
`terraform apply -parallelism=1`; `scripts/provision-k3s.sh` refuses to continue
on a duplicate. Fix: `make down && make up`.

### Pods stuck `Pending` (Insufficient memory)

3×2 GiB is tight with the full observability stack. Give the agents more:

```bash
cd terraform && terraform apply -parallelism=1 \
  -var "ssh_public_key=$(cat ~/.ssh/id_ed25519.pub)" \
  -var 'agent_memory=3GiB'
# then: multipass restart --all  (memory change needs a VM restart)
```

Or trim: lower `prometheus.prometheusSpec.retention`, or scale `alloy` to a
smaller `resources.requests`.

---

## Turn the résumé bullet real: Cloudflare + Let's Encrypt

1. Get a domain, set its nameservers to Cloudflare.
2. Cloudflare → My Profile → API Tokens → token with `Zone:DNS:Edit` + `Zone:Zone:Read` for that zone.
3. `kubectl -n cert-manager create secret generic cloudflare-api-token --from-literal=api-token='<TOKEN>'`
4. Edit `platform/cert-manager/issuers/1?-letsencrypt-*.yaml`: replace `example.com` with your zone.
5. Point hostnames at the new domain (search-replace `192-168-252-240.sslip.io`),
   and change the wildcard `Certificate` / IngressRoutes' `issuerRef` to
   `letsencrypt-staging`, verify, then `letsencrypt-prod`.
6. Cloudflare DNS: `A *  → <your public IP>` (or a Cloudflare Tunnel if the LB IP
   is not public).
