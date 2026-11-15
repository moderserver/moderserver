# ModerServer

<img src="docs/assets/logo.svg" alt="ModerServer logo" width="180">

A self-installing, GitOps-managed home server distribution based on Alpine
Linux and K3s, designed for low-power hardware.

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Manifesto](https://img.shields.io/badge/Manifesto-Read-green.svg)](https://github.com/ModerServer/.github/blob/main/MANIFESTO.md)

## Overview

- **Lightweight**: Alpine Linux and K3s, sized for low-power hardware.
- **Secure by design**: nothing runs as root, applications are isolated, all
  traffic is encrypted, one hardware-key sign-on for everything.
- **GitOps**: the server's entire configuration lives in a Git repository,
  and the server applies it by itself.
- **Self-healing**: failed applications are restarted automatically.
- **Hands-off upgrades**: only tested versions are installed.
- **Private**: no telemetry, no account, no cloud dependency.
- **Open**: standard Kubernetes, free and open source.

## Quick start

Requirements: Docker, Helm, QEMU and `kubectl`. ModerServer runs in a virtual
machine; nothing is installed on the host.

```bash
make build-image   # build the installer ISO
make run-qemu      # install it on a virtual disk and boot it
```

Once the platform is ready, the GitOps dashboard is available at
https://argocd.localhost:18443 (the certificate is issued by the server's own
CA). Stop the machine with `Ctrl+C`.

The virtual machine follows a local mirror of the working tree, so platform
changes can be tested without pushing.

## Development

```bash
make help              # list all targets
make verify-all        # static checks
make test-conformance  # conformance suite on the platform components
make test-e2e          # install on a virtual machine and run the end-to-end tests
```

## License

This repository is licensed under the [Apache 2.0 License](LICENSE).
