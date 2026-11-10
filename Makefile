.PHONY: all help verify-all test-e2e build-image setup-host

all: verify-all

help: ## Show this help message
	@echo "ModerServer Core Build & Verification Automation"
	@echo ""
	@echo "Usage:"
	@echo "  make <target>"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

verify-all: ## Run all static verifications (boilerplate, shellcheck, yamllint)
	./hack/verify-all.sh

test-e2e: ## Run QEMU virtual machine bootstrap & E2E test
	./hack/test-e2e-qemu.sh

build-image: ## Build bootable installer ISO
	./os/build-image.sh

setup-host: ## Execute host bootstrap and K3s OpenRC configuration
	./bootstrap/setup-host.sh
