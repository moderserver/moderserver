#!/usr/bin/env bash
# Copyright 2026 ModerServer Contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -euo pipefail

# renovate: datasource=github-releases depName=k3s-io/k3s
DEFAULT_K3S_VERSION="v1.37.2+k3s1"
K3S_VERSION="${K3S_VERSION:-${DEFAULT_K3S_VERSION}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Configuring Alpine Linux host for ModerServer..."

# 1. Install prerequisites, firmware & hardware drivers
echo "--> Installing host networking, hardware firmware, and tools..."
apk update
apk add --no-cache \
  curl \
  ca-certificates \
  iptables \
  ebtables \
  ip6tables \
  cgroup-tools \
  wireguard-tools \
  chrony \
  acpid \
  zram-init \
  linux-firmware-realtek \
  linux-firmware-intel \
  intel-media-driver \
  libva-intel-driver

# 2. Kernel modules configuration (CNI, WireGuard, Intel QuickSync, ZRAM)
echo "--> Enabling required kernel modules..."
mkdir -p /etc/modules-load.d
cat << 'EOF' > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
wireguard
i915
zram
EOF
modprobe -q overlay || true
modprobe -q br_netfilter || true
modprobe -q wireguard || true
modprobe -q i915 || true
modprobe -q zram || true

# 3. Configure ZRAM Memory Swap (2GB compressed in-RAM safety buffer for 4GB hardware)
echo "--> Configuring ZRAM compressed swap buffer..."
mkdir -p /etc/conf.d
cat << 'EOF' > /etc/conf.d/zram-init
num_devices=1
type0=swap
size0=2048
algo0=lz4
EOF
rc-update add zram-init boot || true

# 4. Configure ACPI for graceful hardware power-button shutdown
rc-update add acpid boot || true

# 5. Kernel sysctl tuning
echo "--> Applying hardened sysctl parameters..."
cp "${CORE_ROOT}/os/sysctl.d/99-moderserver.conf" /etc/sysctl.d/99-moderserver.conf
sysctl -p /etc/sysctl.d/99-moderserver.conf || true

# 6. Configure bootloader for cgroups v2
if [ -f /etc/default/extlinux.conf ] || [ -f /etc/update-extlinux.conf ]; then
  echo "--> Ensuring cgroup memory and cpuset are enabled in extlinux..."
  if ! grep -q "cgroup_enable=cpuset" /etc/update-extlinux.conf 2>/dev/null; then
    sed -i 's/^default_kernel_opts="/default_kernel_opts="cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory /' /etc/update-extlinux.conf 2>/dev/null || true
    update-extlinux || true
  fi
fi

# 7. Install K3s configuration
echo "--> Setting up K3s configuration..."
mkdir -p /etc/rancher/k3s
cp "${SCRIPT_DIR}/config.yaml" /etc/rancher/k3s/config.yaml
cp "${SCRIPT_DIR}/kubelet.config" /etc/rancher/k3s/kubelet.config
chmod 600 /etc/rancher/k3s/config.yaml /etc/rancher/k3s/kubelet.config

# 8. Download pinned K3s binary
echo "--> Downloading K3s binary (${K3S_VERSION})..."
ARCH=$(uname -m)
case "$ARCH" in
  x86_64) K3S_ARCH="amd64" ;;
  aarch64) K3S_ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

K3S_BIN_URL="https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s"
if [ "$K3S_ARCH" = "arm64" ]; then
  K3S_BIN_URL="https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s-arm64"
fi

curl -sfL "$K3S_BIN_URL" -o /usr/local/bin/k3s
chmod 755 /usr/local/bin/k3s

# 9. Install OpenRC service
echo "--> Installing K3s OpenRC service..."
cp "${SCRIPT_DIR}/k3s-service" /etc/init.d/k3s
chmod 755 /etc/init.d/k3s
rc-update add cgroups boot || true
rc-update add k3s default || true

# 10. Lock down root account password login (system security)
echo "--> Locking down root password login..."
passwd -l root >/dev/null 2>&1 || true

echo "==> [PASS] Host preparation completed successfully."
