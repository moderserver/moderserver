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
ALPINE_VERSION="3.24.4"

# renovate: datasource=docker depName=alpine
ALPINE_ISO_VERSION="3.24.4"

# renovate: datasource=github-releases depName=k3s-io/k3s
K3S_VERSION="v1.37.2+k3s1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${CORE_ROOT}/_output"
mkdir -p "${OUTPUT_DIR}"

if [ ! -d "${OUTPUT_DIR}/images" ] || [ -z "$(ls -A "${OUTPUT_DIR}/images" 2>/dev/null)" ]; then
  echo "--> Staging platform component images in ${OUTPUT_DIR}/images..."
  "${CORE_ROOT}/hack/build-components.sh" --save-dir "${OUTPUT_DIR}/images"
fi

IMAGE_OUT="${OUTPUT_DIR}/moderserver-alpine-${ALPINE_VERSION}.iso"

echo "==> Building ModerServer Alpine Appliance ISO (v${ALPINE_VERSION})..."

docker run --rm --privileged \
  -v "${CORE_ROOT}:${CORE_ROOT}" \
  -v "${OUTPUT_DIR}:/output" \
  -e "CORE_ROOT=${CORE_ROOT}" \
  -e "IMAGE_OUT=/output/moderserver-alpine-${ALPINE_VERSION}.iso" \
  -e "ALPINE_ISO_VERSION=${ALPINE_ISO_VERSION}" \
  -e "K3S_VERSION=${K3S_VERSION}" \
  -w "${CORE_ROOT}" \
  "alpine:${ALPINE_VERSION}" \
  "${SCRIPT_DIR}/build-iso-internal.sh"

echo "==> [PASS] Generated bootable appliance ISO at: ${IMAGE_OUT}"
