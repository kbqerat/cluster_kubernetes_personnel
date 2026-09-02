SHELL := /bin/bash
TF_DIR := terraform
KUBECONFIG_FILE := $(CURDIR)/kubeconfig
SSH_PUBKEY := $(shell cat $$HOME/.ssh/id_ed25519.pub)

export KUBECONFIG := $(KUBECONFIG_FILE)

.PHONY: help init plan up k3s cluster nodes ssh down clean \
        set-repo argocd-bootstrap gitops argocd-password apps sync \
        trust-ca demo-client-cert urls

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'

## --- Phase 1-2: infrastructure ------------------------------------------------

init: ## terraform init
	cd $(TF_DIR) && terraform init

plan: ## terraform plan (1 server + 2 agents)
	cd $(TF_DIR) && terraform plan -var 'ssh_public_key=$(SSH_PUBKEY)'

up: ## terraform apply — create the VMs (serial, avoids the macOS DHCP race)
	cd $(TF_DIR) && terraform apply -auto-approve -parallelism=1 -var 'ssh_public_key=$(SSH_PUBKEY)'
	@echo "Waiting for DHCP / cloud-init..." && sleep 15
	cd $(TF_DIR) && terraform refresh -var 'ssh_public_key=$(SSH_PUBKEY)' >/dev/null && terraform output

k3s: ## Install k3s on the VMs, write ./kubeconfig
	./scripts/provision-k3s.sh

cluster: up k3s ## up + k3s

nodes: ## kubectl get nodes
	kubectl get nodes -o wide

ssh: ## Shell into a node: make ssh NODE=k3s-agent-1
	multipass shell $(or $(NODE),k3s-server)

## --- Phase 4+: GitOps -------------------------------------------------------

set-repo: ## Point manifests at your Git remote: make set-repo URL=https://github.com/you/repo.git
	./scripts/set-repo.sh $(URL) $(or $(REV),main)

argocd-bootstrap: ## Install ArgoCD + apply the root app-of-apps
	./bootstrap/install.sh

gitops: set-repo argocd-bootstrap ## set-repo + argocd-bootstrap

apps: ## Show ArgoCD application sync/health status
	kubectl -n argocd get applications

sync: ## Force a refresh+sync of every ArgoCD app
	kubectl -n argocd annotate applications --all \
	  argocd.argoproj.io/refresh=hard --overwrite

argocd-password: ## Print the initial ArgoCD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret \
	  -o jsonpath='{.data.password}' | base64 -d; echo

## --- helpers --------------------------------------------------------------

trust-ca: ## Add the homelab root CA to the macOS keychain
	./scripts/trust-ca.sh

demo-client-cert: ## Export the mTLS demo client cert to ./demo-client.*
	./scripts/demo-client-cert.sh

urls: ## Print the homelab URLs
	@printf '%s\n' \
	  "ArgoCD       https://argocd.192-168-252-240.sslip.io" \
	  "Grafana      https://grafana.192-168-252-240.sslip.io" \
	  "Prometheus   https://prometheus.192-168-252-240.sslip.io" \
	  "Alertmanager https://alertmanager.192-168-252-240.sslip.io" \
	  "Traefik      https://traefik.192-168-252-240.sslip.io" \
	  "whoami       https://whoami.192-168-252-240.sslip.io" \
	  "whoami mTLS  https://whoami-mtls.192-168-252-240.sslip.io"

## --- teardown -----------------------------------------------------------------

down: ## terraform destroy — delete the VMs
	cd $(TF_DIR) && terraform destroy -auto-approve -var 'ssh_public_key=$(SSH_PUBKEY)'

clean: down ## destroy + remove local artifacts
	rm -f kubeconfig homelab-root-ca.crt homelab-ca.crt demo-client.crt demo-client.key
	rm -rf $(TF_DIR)/.generated
