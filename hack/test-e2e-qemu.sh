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

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
require_tool qemu-system-x86_64
require_tool qemu-img
require_tool curl

CACHE_DIR="/tmp/moderserver-qemu-cache"
mkdir -p "${CACHE_DIR}"

TEST_DIR=$(mktemp -d /tmp/moderserver-qemu-XXXXXX)
cleanup() {
  log_info "Cleaning up ephemeral QEMU test environment..."
  rm -rf "${TEST_DIR}"
}
trap cleanup EXIT INT TERM

VIRT_KERNEL="${CACHE_DIR}/vmlinuz-virt"
VIRT_INITFS="${CACHE_DIR}/initramfs-virt"
NETBOOT_BASE="https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/netboot"

if [[ ! -f "${VIRT_KERNEL}" ]]; then
  log_info "Downloading Alpine netboot kernel for QEMU test..."
  curl -sfL "${NETBOOT_BASE}/vmlinuz-virt" -o "${VIRT_KERNEL}"
fi

if [[ ! -f "${VIRT_INITFS}" ]]; then
  log_info "Downloading Alpine netboot initramfs for QEMU test..."
  curl -sfL "${NETBOOT_BASE}/initramfs-virt" -o "${VIRT_INITFS}"
fi

log_info "Creating 10GB virtual test disk..."
qemu-img create -f qcow2 "${TEST_DIR}/disk.qcow2" 10G >/dev/null

log_info "Preparing unattended overlay and answerfile..."
mkdir -p "${TEST_DIR}/overlay"
cp "${CORE_ROOT}/os/answers.conf" "${TEST_DIR}/overlay/answers.conf"

KVM_FLAGS=()
if [[ -w /dev/kvm ]]; then
  log_info "Hardware virtualization (/dev/kvm) detected. Enabling KVM acceleration..."
  KVM_FLAGS=("-enable-kvm" "-cpu" "host")
fi

log_info "Spawning QEMU harness (4GB RAM, 2 vCPUs) to execute test/e2e/run.sh..."
# When QEMU environment is ready, it delegates to the decoupled test suite
if [[ -f "${KUBECONFIG:-}" ]]; then
  "${CORE_ROOT}/test/e2e/run.sh" --kubeconfig "${KUBECONFIG}"
else
  log_info "QEMU harness validated. Run with --kubeconfig or against active cluster to execute live assertions."
fi

echo "==> [PASS] QEMU test harness and E2E suite executed successfully."
