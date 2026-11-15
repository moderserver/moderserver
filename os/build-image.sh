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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Alpine and K3s versions are pinned once, in hack/lib/common.sh
source "${SCRIPT_DIR}/../hack/lib/common.sh"
require_tool docker
require_tool helm

mkdir -p "${OUTPUT_DIR}"

if [ ! -d "${OUTPUT_DIR}/images" ] || [ -z "$(ls -A "${OUTPUT_DIR}/images" 2>/dev/null)" ]; then
  echo "--> Staging platform component images in ${OUTPUT_DIR}/images..."
  "${CORE_ROOT}/hack/build-components.sh" --save-dir "${OUTPUT_DIR}/images"
fi

# Argo CD is the only component installed from the OS image: the node applies
# these manifests once at first boot (bootstrap/moderserver-bootstrap.sh), then
# Argo CD reconciles itself and every other component from Git.
MANIFESTS_DIR="${OUTPUT_DIR}/manifests"
rm -rf "${MANIFESTS_DIR}"
mkdir -p "${MANIFESTS_DIR}"

echo "--> Pre-rendering Argo CD bootstrap manifests..."
cat "${CORE_ROOT}/platform/components/argocd/crds"/*.yaml > "${MANIFESTS_DIR}/argocd-crds.yaml"

build_chart_dependencies "${CORE_ROOT}/platform/components/argocd"
helm template argocd "${CORE_ROOT}/platform/components/argocd" \
  --namespace argocd > "${MANIFESTS_DIR}/argocd.yaml"

IMAGE_OUT="${OUTPUT_DIR}/moderserver-alpine-${ALPINE_VERSION}.iso"

echo "==> Building ModerServer installer ISO (Alpine v${ALPINE_VERSION})..."

docker run --rm \
  -v "${CORE_ROOT}:${CORE_ROOT}:ro" \
  -v "${OUTPUT_DIR}:/output" \
  -e "CORE_ROOT=${CORE_ROOT}" \
  -e "IMAGE_OUT=/output/moderserver-alpine-${ALPINE_VERSION}.iso" \
  -e "ALPINE_ISO_VERSION=${ALPINE_VERSION}" \
  -e "K3S_VERSION=${K3S_VERSION}" \
  -w "${CORE_ROOT}" \
  "alpine:${ALPINE_VERSION}" \
  "${SCRIPT_DIR}/build-iso-internal.sh"

echo "==> [PASS] Generated bootable installer ISO at: ${IMAGE_OUT}"
