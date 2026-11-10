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

# renovate: datasource=docker depName=alpine
ALPINE_VERSION="3.24"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${CORE_ROOT}/_output"
mkdir -p "${OUTPUT_DIR}"

IMAGE_OUT="${OUTPUT_DIR}/moderserver-alpine-${ALPINE_VERSION}.iso"

echo "==> Building ModerServer Alpine Installer ISO (v${ALPINE_VERSION})..."

# Use official Alpine builder container
docker run --rm --privileged \
  -v "${CORE_ROOT}:${CORE_ROOT}" \
  -v "${OUTPUT_DIR}:/output" \
  -w "${CORE_ROOT}" \
  "alpine:${ALPINE_VERSION}" sh -c '
    apk add --no-cache xorriso mtools
    echo "--> Packaging unattended answers and bootstrap into overlay..."
    mkdir -p /tmp/overlay/etc /tmp/overlay/root
    cp "'"${SCRIPT_DIR}"'/answers.conf" /tmp/overlay/etc/answers.conf
    cp -r "'"${CORE_ROOT}"'/bootstrap" /tmp/overlay/root/bootstrap
    echo "--> Generating bootable installer ISO..."
    xorriso -as mkisofs \
      -r -V "MODERSERVER" \
      -o "/output/moderserver-alpine-'"${ALPINE_VERSION}"'.iso" \
      /tmp/overlay
    echo "==> [PASS] Installer rootfs and ISO prepared."
  '

echo "==> [PASS] Generated installer ISO at: ${IMAGE_OUT}"
