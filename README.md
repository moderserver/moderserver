# ModerServer

The foundational Alpine Linux and lightweight Kubernetes (K3s) distribution for ModerServer.

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Manifesto](https://img.shields.io/badge/Manifesto-Read-green.svg)](https://github.com/ModerServer/.github/blob/main/MANIFESTO.md)

## Architecture & Responsibilities

1. **Lightweight Alpine Linux OS (<100MB RAM Idle)**:
   * Built on **Alpine Linux** with **OpenRC** (no systemd bloat, no snapd, no background telemetry).
   * Fully automated, unattended flash drive installer (`os/answers.conf`).
   * Declarative, tested OS upgrades: the host OS version and K3s runtime are pinned in Git and upgraded only via verified GitOps releases.

2. **Tuned K3s Kubernetes Runtime**:
   * Pre-configured for low-power edge nodes (e.g. Intel N100/N150 with 4GB RAM).
   * Native OpenRC daemon service (`bootstrap/k3s-service`).
   * Default Traefik and ServiceLB disabled in favor of modern Kubernetes Gateway API.
   * Kernel-level sysctl tuning for CNI packet forwarding, inotify watchers, and low swappiness (`os/sysctl.d/`).

## Developer Commands

From the `moderserver/` directory:

```bash
# Run all repository static verifications (license headers, shellcheck, yamllint, renovate, actionlint)
make verify-all

# Run Static Conformance against platform components
make test-conformance

# Run live Runtime Conformance against deployed platform
make test-conformance-runtime

# Run E2E node infrastructure test
make test-e2e

# Build official Conformance container image
make build-conformance

# Inspect discovered dependencies and check for available updates locally
./hack/run-renovate.sh

# Build bootable installer ISO
make build-image

# Run standalone host preparation on an Alpine machine
make setup-host
```

## License

This repository is licensed under the [Apache 2.0 License](LICENSE).
