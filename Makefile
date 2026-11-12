.PHONY: all help verify-all build-all build-components build-image build-conformance run-qemu stop-qemu test-conformance test-conformance-runtime test-e2e setup-host

all: verify-all

help: ## Show this help message
	@echo "ModerServer Core Build & Verification Automation"
	@echo ""
	@echo "Usage:"
	@echo "  make <target>"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'

verify-all: ## Run all static verifications (boilerplate, shellcheck, actionlint, yamllint, renovate, gitleaks)
	./hack/verify-all.sh

build-all: build-components build-image build-conformance ## Build all platform components, appliance ISO, and conformance container

build-components: ## Build platform component container images (or COMPONENT=<name>)
	./hack/build-components.sh $(COMPONENT)

build-image: ## Build bootable installer ISO (auto-bundles pre-baked platform images)
	./os/build-image.sh

build-conformance: ## Build Conformance Suite container image
	./hack/build-conformance.sh

test-conformance: ## Run Static Conformance on platform components (or COMPONENT=<name>)
	./hack/test-conformance.sh $(COMPONENT)

test-conformance-runtime: ## Deploy platform layer and run live Runtime Conformance analysis
	./hack/test-conformance-runtime.sh $(NAMESPACE)

test-e2e: ## Run QEMU virtual machine bootstrap & E2E node infrastructure test
	./hack/test-e2e-qemu.sh

setup-host: ## Execute host bootstrap and K3s OpenRC configuration
	./bootstrap/setup-host.sh
