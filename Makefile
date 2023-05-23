# Use bash as shell
SHELL = /bin/bash

PROJECT_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
export PATH := $(PROJECT_DIR)/bin:$(PATH)

define go-get-tool
@[ -f $(1) ] || { \
set -e ;\
TMP_DIR=$$(mktemp -d) ;\
cd $$TMP_DIR ;\
go mod init tmp ;\
echo "Downloading $(2)" ;\
GOBIN=$(PROJECT_DIR)/bin go install $(2) ;\
rm -rf $$TMP_DIR ;\
}
endef

KUSTOMIZE = $(PROJECT_DIR)/bin/kustomize
kustomize: ## Installs kustomize in $PROJECT_DIR/bin
	$(call go-get-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v5@v5.0.3)

ENVSUBST = $(PROJECT_DIR)/bin/envsubst
envsubst: ## Installs envsubst in $PROJECT_DIR/bin
	$(call go-get-tool,$(ENVSUBST),github.com/a8m/envsubst/cmd/envsubst@v1.4.2)

.PHONY: smcp authorino talker-api

export AUTH_NS := authorino
export ODH_NS := opendatahub
export ODH_ROUTE := $(shell kubectl get route --all-namespaces -l maistra.io/gateway-name=odh-gateway -o yaml | yq '.items[].spec.host')

smcp: kustomize envsubst
	$(KUSTOMIZE) build smcp | $(ENVSUBST)

authorino: kustomize envsubst
	$(KUSTOMIZE) build authorino | $(ENVSUBST)

talker-api: kustomize envsubst
	$(KUSTOMIZE) build talker-api | $(ENVSUBST)

odh: kustomize envsubst
	@echo "NOT IMPLEMENTED"

$(VERBOSE).SILENT:
