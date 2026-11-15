#!/bin/sh
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

# Turns an Alpine Linux root filesystem into a ModerServer host.
#
#   setup-host.sh                       Configure the running Alpine system
#   setup-host.sh --root /mnt           Configure a root filesystem mounted at /mnt
#                                       (used by the installer, see os/overlay)
#   setup-host.sh --offline-repo DIR    Install packages from local apk repositories
#                                       only (repeatable; no network access)
#
# Every step is required: the script stops at the first failure instead of
# reporting success on a half-configured host.

set -eu

# renovate: datasource=github-releases depName=k3s-io/k3s
DEFAULT_K3S_VERSION="v1.37.2+k3s1"
K3S_VERSION="${K3S_VERSION:-${DEFAULT_K3S_VERSION}}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ROOT=""
OFFLINE_REPOS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      ROOT="${2%/}"
      shift 2
      ;;
    --offline-repo)
      OFFLINE_REPOS="${OFFLINE_REPOS} $2"
      shift 2
      ;;
    -h|--help)
      sed -n '16,24p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Run a command inside the target root filesystem
in_root() {
  if [ -z "${ROOT}" ]; then
    "$@"
  else
    chroot "${ROOT}" "$@"
  fi
}

# enable_service <service> <runlevel>
enable_service() {
  if [ ! -e "${ROOT}/etc/init.d/$1" ]; then
    echo "Service '$1' is not installed in ${ROOT:-/}" >&2
    exit 1
  fi
  if [ ! -L "${ROOT}/etc/runlevels/$2/$1" ]; then
    in_root rc-update add "$1" "$2"
  fi
}

echo "==> Configuring Alpine Linux host for ModerServer (root: ${ROOT:-/})..."

# 1. Package repositories: a host installed from the offline installer has no
#    remote repository yet, and needs one for later GitOps-driven OS upgrades.
if ! grep -q -E '^https?://' "${ROOT}/etc/apk/repositories" 2>/dev/null; then
  ALPINE_BRANCH="$(cut -d. -f1,2 "${ROOT}/etc/alpine-release")"
  echo "--> Pointing package repositories at Alpine v${ALPINE_BRANCH}..."
  cat << EOF_REPOS > "${ROOT}/etc/apk/repositories"
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_BRANCH}/main
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_BRANCH}/community
EOF_REPOS
fi

# 2. Host packages (networking, firmware and tools)
echo "--> Installing host packages..."
PACKAGES="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "${SCRIPT_DIR}/host-packages" | tr '\n' ' ')"
if [ -n "${OFFLINE_REPOS}" ]; then
  REPO_ARGS="--no-network --repositories-file /dev/null"
  for repo in ${OFFLINE_REPOS}; do
    REPO_ARGS="${REPO_ARGS} --repository ${repo}"
  done
  # shellcheck disable=SC2086
  apk add --root "${ROOT:-/}" ${REPO_ARGS} ${PACKAGES}
else
  # shellcheck disable=SC2086
  apk add --root "${ROOT:-/}" --update-cache ${PACKAGES}
fi

# 3. Kernel modules (container networking, WireGuard)
echo "--> Enabling required kernel modules..."
mkdir -p "${ROOT}/etc/modules-load.d"
cat << 'EOF_MODULES' > "${ROOT}/etc/modules-load.d/moderserver.conf"
overlay
br_netfilter
wireguard
EOF_MODULES

# 4. ZRAM compressed swap (2GB in-RAM safety buffer for 4GB hardware)
echo "--> Configuring ZRAM compressed swap..."
cat << 'EOF_ZRAM' > "${ROOT}/etc/conf.d/zram-init"
load_on_start=yes
unload_on_stop=yes
num_devices=1
type0=swap
size0=2048
algo0=lz4
labl0=zram_swap
EOF_ZRAM

# 5. Kernel sysctl tuning
echo "--> Installing hardened sysctl parameters..."
mkdir -p "${ROOT}/etc/sysctl.d"
cp "${CORE_ROOT}/os/sysctl.d/99-moderserver.conf" "${ROOT}/etc/sysctl.d/99-moderserver.conf"

# 6. K3s configuration
echo "--> Installing K3s configuration..."
mkdir -p "${ROOT}/etc/rancher/k3s"
for file in config.yaml kubelet.config pod-security.yaml; do
  cp "${SCRIPT_DIR}/${file}" "${ROOT}/etc/rancher/k3s/${file}"
  chmod 600 "${ROOT}/etc/rancher/k3s/${file}"
done

# 7. Pinned K3s binary: shipped next to this script by the installer image,
#    otherwise downloaded and verified against the release checksums.
echo "--> Installing K3s binary (${K3S_VERSION})..."
mkdir -p "${ROOT}/usr/local/bin"
if [ -f "${SCRIPT_DIR}/k3s" ]; then
  cp "${SCRIPT_DIR}/k3s" "${ROOT}/usr/local/bin/k3s"
else
  ARCH="$(uname -m)"
  case "${ARCH}" in
    x86_64) K3S_ARCH="amd64"; K3S_BIN="k3s" ;;
    aarch64) K3S_ARCH="arm64"; K3S_BIN="k3s-arm64" ;;
    *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;;
  esac
  K3S_RELEASE_URL="https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}"
  K3S_TMP="$(mktemp -d)"
  curl -sfL "${K3S_RELEASE_URL}/${K3S_BIN}" -o "${K3S_TMP}/${K3S_BIN}"
  curl -sfL "${K3S_RELEASE_URL}/sha256sum-${K3S_ARCH}.txt" -o "${K3S_TMP}/sha256sum.txt"
  EXPECTED_SHA="$(awk -v f="${K3S_BIN}" '$2 == f {print $1}' "${K3S_TMP}/sha256sum.txt")"
  ACTUAL_SHA="$(sha256sum "${K3S_TMP}/${K3S_BIN}" | cut -d' ' -f1)"
  if [ -z "${EXPECTED_SHA}" ] || [ "${EXPECTED_SHA}" != "${ACTUAL_SHA}" ]; then
    echo "K3s binary checksum mismatch (expected '${EXPECTED_SHA}', got '${ACTUAL_SHA}')" >&2
    exit 1
  fi
  cp "${K3S_TMP}/${K3S_BIN}" "${ROOT}/usr/local/bin/k3s"
  rm -rf "${K3S_TMP}"
fi
chmod 755 "${ROOT}/usr/local/bin/k3s"

# 8. Pre-baked platform container images (imported by K3s at start)
if [ -d "${SCRIPT_DIR}/images" ]; then
  echo "--> Staging pre-baked platform container images..."
  mkdir -p "${ROOT}/var/lib/rancher/k3s/agent/images"
  cp "${SCRIPT_DIR}/images"/*.tar "${ROOT}/var/lib/rancher/k3s/agent/images/"
fi

# 9. Node configuration and GitOps bootstrap
echo "--> Installing ModerServer node configuration..."
mkdir -p "${ROOT}/etc/moderserver"
if [ ! -f "${ROOT}/etc/moderserver/moderserver.conf" ]; then
  cp "${SCRIPT_DIR}/moderserver.conf" "${ROOT}/etc/moderserver/moderserver.conf"
fi

mkdir -p "${ROOT}/usr/local/sbin"
cp "${SCRIPT_DIR}/moderserver-bootstrap.sh" "${ROOT}/usr/local/sbin/moderserver-bootstrap"
chmod 755 "${ROOT}/usr/local/sbin/moderserver-bootstrap"

GITOPS_BOOTSTRAP="false"
if [ -d "${SCRIPT_DIR}/manifests" ]; then
  echo "--> Installing GitOps bootstrap manifests..."
  mkdir -p "${ROOT}/usr/share/moderserver/bootstrap"
  cp "${SCRIPT_DIR}/manifests"/*.yaml "${ROOT}/usr/share/moderserver/bootstrap/"
  GITOPS_BOOTSTRAP="true"
else
  echo "--> No GitOps bootstrap manifests next to this script: K3s is installed"
  echo "    without the platform. Build them with 'make build-image' (see os/build-image.sh)."
fi

# 10. OpenRC services
echo "--> Installing OpenRC services..."
cp "${SCRIPT_DIR}/k3s-service" "${ROOT}/etc/init.d/k3s"
cp "${SCRIPT_DIR}/moderserver-bootstrap-service" "${ROOT}/etc/init.d/moderserver-bootstrap"
chmod 755 "${ROOT}/etc/init.d/k3s" "${ROOT}/etc/init.d/moderserver-bootstrap"

enable_service cgroups boot
enable_service zram-init boot
enable_service acpid default
enable_service chronyd default
enable_service k3s default
if [ "${GITOPS_BOOTSTRAP}" = "true" ]; then
  enable_service moderserver-bootstrap default
fi

# 11. No password logins: the node is managed through GitOps and the Kubernetes API
echo "--> Locking root password login..."
in_root passwd -l root >/dev/null

# 12. Apply kernel settings immediately when configuring the running system
if [ -z "${ROOT}" ]; then
  modprobe -a overlay br_netfilter wireguard
  sysctl -q -p /etc/sysctl.d/99-moderserver.conf
fi

echo "==> [PASS] Host preparation completed successfully."
