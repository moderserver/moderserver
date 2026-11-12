.PHONY: all help verify-all test-e2e build-image setup-host build-conformance test-conformance test-conformance-runtime run-qemu run-demo stop-qemu

all: verify-all

help: ## Show this help message
	@echo "ModerServer Core Build & Verification Automation"
	@echo ""
	@echo "Usage:"
	@echo "  make <target>"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

verify-all: ## Run all static verifications (boilerplate, shellcheck, actionlint, yamllint, renovate, gitleaks)
	./hack/verify-all.sh

test-conformance: ## Run Static Conformance on platform components (or COMPONENT=<name>)
	./hack/test-conformance.sh $(COMPONENT)

test-conformance-runtime: ## Deploy platform layer and run live Runtime Conformance analysis
	./hack/test-conformance-runtime.sh $(NAMESPACE)

test-e2e: ## Run QEMU virtual machine bootstrap & E2E node infrastructure test
	./hack/test-e2e-qemu.sh

build-image: ## Build bootable installer ISO
	./os/build-image.sh

build-conformance: ## Build Conformance Suite container image
	./hack/build-conformance.sh

setup-host: ## Execute host bootstrap and K3s OpenRC configuration
	./bootstrap/setup-host.sh
