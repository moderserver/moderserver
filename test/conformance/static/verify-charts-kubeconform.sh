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

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../hack" && pwd)/lib/common.sh"
require_tool helm

TARGET_DIR="${1:-.}"

# renovate: datasource=github-releases depName=kubernetes/kubernetes
DEFAULT_K8S_VERSION="1.37.2"
K8S_VERSION="${K8S_TARGET_VERSION:-${DEFAULT_K8S_VERSION}}"

log_info "[Conformance:Static] Validating K8s OpenAPI schemas with kubeconform (${KUBECONFORM_VERSION}, K8s ${K8S_VERSION})..."

CHARTS=$(find "${TARGET_DIR}" -type f -name "Chart.yaml" -exec dirname {} \; 2>/dev/null || true)
if [[ -z "${CHARTS}" ]]; then
  log_info "No Helm chart found in ${TARGET_DIR}, skipping."
  exit 0
fi

TMP_DIR=$(mktemp -d)
chmod 755 "${TMP_DIR}"
trap 'rm -rf "${TMP_DIR}"' EXIT

for chart in ${CHARTS}; do
  APP_NAME=$(basename "${chart}")
  MANIFEST="${TMP_DIR}/${APP_NAME}.yaml"
  (
    cd "${chart}"
    helm dependency update >/dev/null 2>&1 || true
    helm template "${APP_NAME}-test" . > "${MANIFEST}"
  )
  chmod 644 "${MANIFEST}"

  run_tool_or_docker kubeconform "${KUBECONFORM_IMAGE}" \
    -summary -strict -ignore-missing-schemas -kubernetes-version "${K8S_VERSION}" \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
    "${MANIFEST}"
done

log_pass "OpenAPI schema validation verified."
