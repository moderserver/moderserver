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

log_info "[Conformance:Static] Auditing NSA-CISA compliance with kubescape (${KUBESCAPE_VERSION})..."

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

  # Run kubescape; ignore if chart has no workload pods/deployments to evaluate
  SCAN_OUTPUT=$(run_tool_or_docker kubescape "${KUBESCAPE_IMAGE}" scan framework nsa "${MANIFEST}" --severity-threshold high 2>&1 || true)
  if echo "${SCAN_OUTPUT}" | grep -q "no resources found to scan"; then
    log_info "No standard workload resources in ${APP_NAME} to scan with kubescape, skipping."
  elif echo "${SCAN_OUTPUT}" | grep -E -q "│ *(Critical|High) │ [1-9]"; then
    echo "${SCAN_OUTPUT}" >&2
    log_error "kubescape detected compliance failures in ${APP_NAME}."
    exit 1
  fi
done

log_pass "kubescape compliance verified."
