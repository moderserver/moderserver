# ModerServer

The foundational Alpine Linux and lightweight Kubernetes (K3s) distribution for ModerServer.

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Manifesto](https://img.shields.io/badge/Manifesto-Read-green.svg)](https://github.com/ModerServer/.github/blob/main/MANIFESTO.md)

## Architecture & Responsibilities

1. **Lightweight Alpine Linux OS (<100MB RAM Idle)**:
   * Built on **Alpine Linux** with **OpenRC** (lightweight initialization without systemd, snapd, or background telemetry).
   * Unattended, fully offline installer (`os/overlay/etc/local.d/moderserver-install.start`): boot the ISO from a flash drive (BIOS or UEFI), ModerServer is installed on the internal disk, the machine powers off, and boots from its own disk from then on. A blank single disk is installed without a question; anything else asks before erasing.
   * Host configuration in one strict script (`bootstrap/setup-host.sh`), from one package list (`bootstrap/host-packages`). No password logins.

2. **Tuned K3s Kubernetes Runtime**:
   * Pre-configured for low-power edge nodes (e.g. Intel N100/N150 with 4GB RAM).
   * Native OpenRC daemon service (`bootstrap/k3s-service`).
   * Default Traefik and ServiceLB disabled in favor of modern Kubernetes Gateway API; the gateway publishes the node's ports 80/443 itself.
   * Baseline Pod Security enforced on every namespace that does not declare its own level (`bootstrap/pod-security.yaml`).
   * Kernel-level sysctl tuning for CNI packet forwarding, inotify watchers, and low swappiness (`os/sysctl.d/`).

3. **GitOps Platform** (`platform/`):
   * At first boot the node installs Argo CD from the OS image, once (`bootstrap/moderserver-bootstrap.sh`). From then on Argo CD reconciles itself and every component from Git; nothing else on the host manages cluster resources.
   * `/etc/moderserver/moderserver.conf` (`bootstrap/moderserver.conf`) names the Git repository, revision and domain the node follows. Point it at your own fork to own your configuration.
   * Components are plain Helm charts (`platform/components/`) wired by an app-of-apps (`platform/system/`): Gateway API, cert-manager with a local CA, NGINX Gateway Fabric, system-upgrade-controller and Argo CD.
   * Hardened by default: non-root containers, read-only root filesystems, default-deny ingress NetworkPolicies per platform namespace, HTTPS-only gateway, and no credential stored in Git (Argo CD generates its own on the node).

4. **Verified Releases**:
   * Nodes follow the `stable` branch, never `main`. CI moves `stable` and publishes images only for commits that passed static verification, static conformance, the QEMU E2E suite (install, security, gateway, reboot) and runtime conformance.
   * Image tags are content-addressed (`<upstream version>-<hash of the Dockerfiles>`), so a rebuilt image always reaches nodes and an unchanged one is never re-pulled.
   * K3s and Alpine upgrades are declared in Git (`platform/components/upgrade`) and applied by system-upgrade-controller. This component is opt-in for now: there is no automated rollback yet, and an upgrade is not yet covered by the E2E suite.

## Developer Commands

From the `moderserver/` directory:

```bash
# Run all repository static verifications (license headers, shellcheck, actionlint, yamllint, renovate, gitleaks, image tags)
make verify-all

# Build all platform components, the installer ISO, and conformance tools
make build-all

# Install ModerServer on a QEMU virtual machine and run it interactively (Ctrl+C to stop)
make run-qemu

# Same machine in the background, then: publish local changes to it, reboot it, stop it
./hack/run-qemu.sh --daemon
./hack/run-qemu.sh --sync
./hack/run-qemu.sh --reboot
make stop-qemu

# Install and boot with UEFI firmware instead of BIOS
FIRMWARE=uefi make run-qemu

# Run Static Conformance against platform components (inside the conformance image)
make test-conformance

# Run live Runtime Conformance against deployed platform
make test-conformance-runtime

# Run the E2E suite: unattended install, node, security, gateway and reboot tests
make test-e2e

# Inspect discovered dependencies and check for available updates locally
./hack/run-renovate.sh

# Configure an already installed Alpine machine as a ModerServer host
make setup-host
```

The QEMU machine follows a local Git mirror of your working tree (committed or
not), so platform changes can be tested without pushing anything.

## License

This repository is licensed under the [Apache 2.0 License](LICENSE).
