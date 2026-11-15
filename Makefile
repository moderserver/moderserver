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

verify-all: ## Run all static verifications (boilerplate, shellcheck, actionlint, yamllint, renovate, gitleaks, image tags)
	./hack/verify-all.sh

build-all: build-components build-image build-conformance ## Build all platform components, OS image ISO, and conformance container

build-components: ## Build platform component container images (or COMPONENT=<name>)
	./hack/build-components.sh $(COMPONENT)

build-image: ## Build bootable unattended installer ISO (bundles platform images and offline packages)
	./os/build-image.sh

build-conformance: ## Build Conformance Suite container image
	./hack/build-conformance.sh

run-qemu: ## Install and run an interactive ModerServer QEMU virtual machine (Ctrl+C to stop)
	./hack/run-qemu.sh

stop-qemu: ## Stop and clean up the ModerServer QEMU virtual machine
	./hack/run-qemu.sh --stop

test-conformance: ## Run Static Conformance on platform components (or COMPONENT=<name>)
	./hack/test-conformance.sh $(COMPONENT)

test-conformance-runtime: ## Deploy platform layer and run live Runtime Conformance analysis
	./hack/test-conformance-runtime.sh $(NAMESPACE)

test-e2e: ## Install on a QEMU virtual machine and run the E2E suite (node, security, gateway, reboot)
	./hack/test-e2e-qemu.sh

setup-host: ## Configure the running Alpine system as a ModerServer host (K3s, OpenRC services)
	./bootstrap/setup-host.sh
