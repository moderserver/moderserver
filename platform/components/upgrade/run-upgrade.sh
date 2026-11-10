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

# This script is executed by system-upgrade-controller inside a privileged
# container mounting the host root filesystem at /host.

HOST_ROOT="${HOST_ROOT:-/host}"
TARGET_OS_VERSION="${TARGET_OS_VERSION:-3.24}"

echo "==> ModerServer GitOps OS Upgrade Runner"
echo "--> Target Alpine OS Version: ${TARGET_OS_VERSION}"

if [ ! -d "${HOST_ROOT}/etc/apk" ]; then
  echo "ERROR: Host root filesystem not found at ${HOST_ROOT}" >&2
  exit 1
fi

# 1. Update host repository pin to target release stream
echo "--> Pinning host repositories to Alpine v${TARGET_OS_VERSION}..."
cat << EOF > "${HOST_ROOT}/etc/apk/repositories"
https://dl-cdn.alpinelinux.org/alpine/v${TARGET_OS_VERSION}/main
https://dl-cdn.alpinelinux.org/alpine/v${TARGET_OS_VERSION}/community
EOF

# 2. Perform package upgrades inside host chroot
echo "--> Updating package indexes on host..."
chroot "${HOST_ROOT}" apk update

echo "--> Upgrading host packages to match GitOps declaration..."
chroot "${HOST_ROOT}" apk upgrade --available

# 3. Check if kernel was upgraded and coordinate reboot
CURRENT_KERNEL=$(chroot "${HOST_ROOT}" uname -r)
LATEST_KERNEL=$(chroot "${HOST_ROOT}" ls /lib/modules 2>/dev/null | sort -V | tail -n1 || echo "")

if [ -n "${LATEST_KERNEL}" ] && [ "${CURRENT_KERNEL}" != "${LATEST_KERNEL}" ]; then
  echo "--> Kernel upgrade detected (${CURRENT_KERNEL} -> ${LATEST_KERNEL}). Scheduling host reboot..."
  # Signal reboot through system-upgrade-controller or OpenRC
  chroot "${HOST_ROOT}" reboot || true
else
  echo "--> No kernel reboot required. OS packages successfully reconciled."
fi

echo "==> [PASS] Host OS upgrade completed successfully."
