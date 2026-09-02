# Cluster Kubernetes personnel (Homelab) — GitOps de bout en bout

End-to-end GitOps homelab: a multi-node **k3s** cluster provisioned with **Terraform**,
application delivery via **ArgoCD**, ingress with **Traefik**, TLS/mTLS with **cert-manager**,
DNS via **Cloudflare** (or `sslip.io` while free), and observability with
**Prometheus / Grafana / Loki**. Cluster supervision with **Lens**.

## Substrate (this setup)

| Concern      | Choice                                                            |
|--------------|-----------------------------------------------------------------|
| Nodes        | 3× Multipass VMs on the local Mac (1 server + 2 agents)         |
| Provisioning | Terraform (`larstobi/multipass` provider)                       |
| k3s install  | `k3sup` over SSH, Traefik + servicelb disabled                  |
| LoadBalancer | MetalLB (L2) on the Multipass subnet                            |
| DNS          | `sslip.io` wildcard now → Cloudflare later                      |
| TLS/mTLS     | cert-manager self-signed root CA now → Let's Encrypt DNS-01 later |

Default node size: 2 vCPU / 2 GiB / 12 GiB disk. Tune in `terraform/variables.tf`
or via `-var` (16 GB Mac: keep total VM memory ≤ ~7 GiB).

## Prerequisites

```bash
brew install terraform helm k3sup argocd kubectx k9s yq sops age gh
brew install --cask multipass lens
```

SSH key at `~/.ssh/id_ed25519` (used by `k3sup`). kubectl already required.

## Quickstart — Phase 1 & 2 (cluster up)

```bash
make init      # terraform init
make plan      # review: 1 server + 2 agents
make up        # create the VMs
make k3s       # install k3s, write ./kubeconfig
export KUBECONFIG=$PWD/kubeconfig
make nodes     # 3x Ready
```

Add the cluster to Lens: point it at `./kubeconfig` (context `homelab`).

Tear down: `make down` (VMs) or `make clean` (VMs + local artifacts).

## Quickstart — Phase 4+ (GitOps)

```bash
gh repo create cluster_kubernetes_personnel --private --source=. --remote=origin --push
make set-repo                       # bake your repo URL into the ArgoCD manifests
git commit -am "set gitops repo url" && git push
make argocd-bootstrap               # helm install argocd + apply root app-of-apps
watch make apps                     # all Applications -> Synced / Healthy (~5-10 min)
make trust-ca                       # trust the homelab root CA on macOS
make urls                           # ArgoCD / Grafana / Prometheus / whoami URLs
```

Everything after `argocd-bootstrap` is driven by `git push`. Full details and
failure modes in [docs/runbook.md](docs/runbook.md); design in
[docs/architecture.md](docs/architecture.md).

## Roadmap

| Phase | Scope | Status |
|------:|-------|--------|
| 0 | Repo scaffold, Makefile, .gitignore | ✅ |
| 1 | Terraform → 3 Multipass VMs | ✅ |
| 2 | k3s server + agents via k3sup, kubeconfig | ✅ |
| 3 | Lens / k9s supervision | ✅ |
| 4 | ArgoCD bootstrap + app-of-apps (sync waves) | ✅ |
| 5 | Platform: MetalLB, Traefik, cert-manager + ClusterIssuers | ✅ |
| 6 | Ingress + wildcard TLS + mTLS route | ✅ |
| 7 | Observability: kube-prometheus-stack + Loki + Alloy | ✅ |
| 8 | Grafana dashboard-as-code + homelab PrometheusRules | ✅ |
| 9 | Demo app (whoami) delivered purely via Git push | ✅ |
| 10 | Cloudflare + Let's Encrypt DNS-01 (committed, dormant) | ◑ needs a domain |

All manifests are authored and chart-validated. What remains is *running* it:
`make up && make k3s && make argocd-bootstrap` on a Mac with Local Network
permission granted to the terminal app (see runbook).

## Layout

```
terraform/    Phase 1 — VM provisioning (Multipass)
scripts/      provision-k3s.sh, set-repo.sh, trust-ca.sh, demo-client-cert.sh
bootstrap/    Phase 4 — one-time ArgoCD install + values
argocd/       root app-of-apps + one Application per platform/apps component
platform/     Phase 5-8 — MetalLB, Traefik, cert-manager, observability, ingress
apps/         Phase 9 — workloads (whoami demo)
docs/         architecture.md (mermaid), runbook.md
```

## Chart versions (pinned)

| Component | Chart | App |
| --- | --- | --- |
| ArgoCD | argo-cd 10.6.4 | v3.5.2 |
| MetalLB | metallb 0.16.1 | v0.16.1 |
| cert-manager | cert-manager v1.21.1 | v1.21.1 |
| Traefik | traefik 41.4.0 | v3.7.12 |
| kube-prometheus-stack | 88.6.2 | Prometheus operator v0.93.1 |
| Loki | loki 7.3.0 | 3.6.12 |
| Alloy | alloy 1.12.1 | v1.19.2 |
