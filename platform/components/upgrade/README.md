# Upgrade Component

Declarative operating system and Kubernetes runtime upgrades for ModerServer.

* **Upstream Controller**: [rancher/system-upgrade-controller](https://github.com/rancher/system-upgrade-controller)
* **Scope**: K3s binary upgrades (`k3s-plan.yaml`) and host Alpine package upgrades through a host chroot (`os-plan.yaml`), both pinned in Git.
* **Status**: opt-in (`components.upgrade.enabled` in `platform/system/values.yaml`). Once enabled, a node cordons itself, upgrades, and reboots on its own after a kernel upgrade.
* **Single node**: plans cordon but never drain, since there is no second node to move workloads to.
