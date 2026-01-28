# Terraform Makefile - always use backend-config + var-file per environment
# Variables are passed only declaratively via the tfvars file (-var-file).
# Do not use -var overrides; set create_eks, create_rds, etc. in tfvars.
#
# Usage:
#   make init ENV=prod
#   make plan ENV=prod
#   make apply ENV=prod
#   make init ENV=staging && make plan ENV=staging

ENV ?= prod
BACKEND_CONFIG := environments/$(ENV)/backend.conf
VAR_FILE      := environments/$(ENV)/terraform.tfvars

# EKS node role name (project-environment-eks-eks-node-role). Override if different.
NODE_ROLE_NAME ?= pipeops-prod-eks-eks-node-role

.PHONY: init plan plan-no-refresh apply-plan apply validate fmt import-eks-node import-eks-access bootstrap-eks-access
.DEFAULT_GOAL := help

help:
	@echo "Terraform targets (use ENV=dev|staging|prod):"
	@echo "  make init ENV=prod     - init with -backend-config + -reconfigure"
	@echo "  make plan ENV=prod     - plan with -var-file"
	@echo "  make plan-no-refresh ENV=prod - plan with -refresh=false, -out=tfplan-ENV (when eks-exec not in EKS yet)"
	@echo "  make apply-plan ENV=prod      - apply saved plan (use after plan-no-refresh; creates eks-exec then Helm)"
	@echo "  make apply ENV=prod    - apply with -var-file"
	@echo "  make validate          - terraform validate"
	@echo "  make fmt               - terraform fmt -recursive"
	@echo ""
	@echo "  make bootstrap-eks-access ENV=prod"
	@echo "    - EXISTING clusters only! Apply only EKS access entries (-target, -refresh=false)."
	@echo "      Do NOT use for greenfield: it skips IGW, NAT, route tables, VPC endpoints, etc."
	@echo "      Run with IAM that has EKS admin (e.g. root). Registers eks-exec when"
	@echo "      eks-exec-role-arn.txt exists. For new envs use: make apply ENV=..."
	@echo ""
	@echo "  make import-eks-access ENV=prod"
	@echo "    - Import existing EKS access entries (root, ozimede-cli) into state."
	@echo ""
	@echo "  make import-eks-node ENV=prod [NODE_ROLE_NAME=...]"
	@echo "    - Import existing EKS node IAM role & instance profile (fix 'EntityAlreadyExists')"
	@echo ""
	@echo "Backend: environments/$(ENV)/backend.conf"
	@echo "Vars:    environments/$(ENV)/terraform.tfvars (declarative only; no -var)"
	@echo ""
	@echo "State lock 'ResourceNotFoundException'? Run: make init ENV=$(ENV)  (then retry)"
	@echo "Stale state lock? terraform force-unlock <LOCK_ID>"
	@echo "'aws failed 254' / cluster unreachable? Set use_eks_exec_role=false in tfvars for local dev, or use plan-no-refresh + apply-plan."

check-env:
	@test -f $(BACKEND_CONFIG) || (echo "Missing $(BACKEND_CONFIG). Use ENV=dev|staging|prod."; exit 1)
	@test -f $(VAR_FILE) || (echo "Missing $(VAR_FILE). Use ENV=dev|staging|prod."; exit 1)

init: check-env
	terraform init -backend-config=$(BACKEND_CONFIG) -reconfigure -input=false

plan: check-env
	terraform plan -var-file=$(VAR_FILE) -no-color -input=false

plan-no-refresh: check-env
	@echo "Planning without refresh (skips cluster connection). Use when eks-exec access entry does not exist yet."
	@echo "Then run: make apply-plan ENV=$(ENV)   (applies tfplan-$(ENV), creating eks-exec entry before Helm runs)"
	terraform plan -refresh=false -var-file=$(VAR_FILE) -out=tfplan-$(ENV) -no-color -input=false

apply-plan: check-env
	@test -f tfplan-$(ENV) || (echo "No tfplan-$(ENV). Run: make plan-no-refresh ENV=$(ENV)"; exit 1)
	terraform apply -input=false tfplan-$(ENV)

apply: check-env
	terraform apply -var-file=$(VAR_FILE) -input=false

validate:
	terraform validate

fmt:
	terraform fmt -recursive

import-eks-node: check-env
	@echo "Importing EKS node IAM role and instance profile: $(NODE_ROLE_NAME)"
	terraform import 'module.eks.aws_iam_role.node' $(NODE_ROLE_NAME)
	@terraform import 'module.eks.aws_iam_instance_profile.node' $(NODE_ROLE_NAME) || \
		echo "Instance profile not found (ok if only role existed). Run 'make apply ENV=...' to create it."

EKS_CLUSTER_NAME ?= pipeops-prod-eks
import-eks-access: check-env
	@echo "Importing EKS access entries (root, ozimede-cli). Override EKS_CLUSTER_NAME if needed."
	terraform import -var-file=$(VAR_FILE) 'aws_eks_access_entry.cluster_access["ozimede-cli"]' '$(EKS_CLUSTER_NAME):arn:aws:iam::742890864997:user/ozimede-cli'
	terraform import -var-file=$(VAR_FILE) 'aws_eks_access_entry.cluster_access["root"]' '$(EKS_CLUSTER_NAME):arn:aws:iam::742890864997:root'

bootstrap-eks-access: check-env init
	@echo "Applying EKS access entries only (-target; -refresh=false). EXISTING clusters only!"
	@echo "Do NOT use for greenfield — use 'make apply ENV=$(ENV)' instead. Use AWS identity with EKS admin (e.g. root)."
	terraform apply -refresh=false -var-file=$(VAR_FILE) -input=false \
		-target='aws_eks_access_entry.cluster_access' \
		-target='aws_eks_access_policy_association.cluster_scoped' \
		-target='aws_eks_access_policy_association.namespace_scoped' \
		-auto-approve
