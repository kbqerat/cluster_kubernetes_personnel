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

# 2. GitHub repo (once) — MUST be public, or ArgoCD needs repo creds
gh repo create cluster_kubernetes_personnel --public --source=. --remote=origin --push
make set-repo                 # bakes 'origin' into the 15 Application manifests
git commit -am "set gitops repo url" && git push

# 3. Dashboard basic-auth secret (Prometheus/Alertmanager/Traefik) + Grafana admin
kubectl create namespace traefik --dry-run=client -o yaml | kubectl apply -f -
htpasswd -nbBC 10 admin 'CHOOSE_ONE' | kubectl -n traefik create secret generic dashboard-auth --from-file=users=/dev/stdin
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl -n observability create secret generic grafana-admin \
  --from-literal=admin-user=admin --from-literal=admin-password='CHOOSE_ANOTHER'

# 4. GitOps
make argocd-bootstrap         # helm install argocd + apply root app-of-apps
watch make apps               # wait for all 14 Applications = Synced / Healthy

# 5. Trust the homelab CA + see the endpoints
make trust-ca
make urls
```

First full sync is ~8–12 min (CRDs, cert-manager webhook, Prometheus operator,
Loki + Prometheus PVCs). The app-of-apps advances by sync-wave; a wave that is
briefly `Degraded`/`Missing` while a CRD lands is normal — ArgoCD retries.

## Credentials

| What | User | Where the password lives |
|------|------|--------------------------|
| ArgoCD UI/CLI | `admin` | `make argocd-password` (secret `argocd/argocd-initial-admin-secret`) |
| Grafana | `admin` | secret `observability/grafana-admin` (you created it in step 3) |
| Prometheus / Alertmanager / Traefik dashboards | `admin` | secret `traefik/dashboard-auth` (htpasswd, step 3) |

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

### k3s API server unreachable, `load average` in the 30s, pods evicted

The **server node ran out of RAM**. 3×2 GiB cannot hold the control plane +
kube-prometheus-stack + Loki + Alloy + ArgoCD. Defaults are now **server 4 GiB /
agents 3 GiB** (`terraform/variables.tf`). To resize VMs that already exist
(the `multipass` provider treats `memory` as ForceNew, so `terraform apply`
would destroy them):

```bash
multipass stop --all
multipass set local.k3s-server.memory=4G
multipass set local.k3s-agent-1.memory=3G
multipass set local.k3s-agent-2.memory=3G
multipass start k3s-server        # wait for it, then:
multipass start k3s-agent-1 k3s-agent-2
```

Steady-state after that: server ~62%, agents ~50% of RAM.

---

## Gotchas hit during first bring-up (all fixed in the manifests)

- **Private repo** → ArgoCD `authentication required: Repository not found`.
  The repo must be public, or add an ArgoCD repository Secret with a token.
- **`TLSOption` named `default`** is special-cased by Traefik (applied globally,
  not addressable). IngressRoutes must use `tls: {}` and let it apply implicitly;
  only non-`default` options (like `mtls`) can be referenced by name/namespace.
- **Grafana + a PVC** persists the admin password from first boot and ignores
  later Secret changes. Grafana is now `persistence.enabled: false` (all state is
  provisioned from ConfigMaps) with `admin.existingSecret: grafana-admin`.
- **Dormant Let's Encrypt ClusterIssuers** report `Ready=False` without a
  Cloudflare token and drag `cert-manager-issuers` to `Degraded`. They live as
  `*.clusterissuer.example.yaml` (excluded from sync) until you have a domain.
- **kube-prometheus-stack admission-webhook Jobs** self-delete; ArgoCD tracked
  them as drift until given `argocd.argoproj.io/hook: PreSync` annotations
  (`prometheusOperator.admissionWebhooks.annotations` in values).
- **`mapfile`** (bash 4) is not in macOS's bash 3.2 — `scripts/provision-k3s.sh`
  uses a portable `for` loop.

---

## Turn the résumé bullet real: Cloudflare + Let's Encrypt

1. Get a domain, set its nameservers to Cloudflare.
2. Cloudflare → My Profile → API Tokens → token with `Zone:DNS:Edit` + `Zone:Zone:Read` for that zone.
3. `kubectl -n cert-manager create secret generic cloudflare-api-token --from-literal=api-token='<TOKEN>'`
4. `git mv` the two `platform/cert-manager/issuers/1?-letsencrypt-*.clusterissuer.example.yaml`
   to drop `.example`, and replace `example.com` in them with your Cloudflare zone.
5. Point hostnames at the new domain (search-replace `192-168-252-240.sslip.io`),
   and change the wildcard `Certificate` / IngressRoutes' `issuerRef` to
   `letsencrypt-staging`, verify, then `letsencrypt-prod`.
6. Cloudflare DNS: `A *  → <your public IP>` (or a Cloudflare Tunnel if the LB IP
   is not public).
