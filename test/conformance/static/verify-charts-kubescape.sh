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
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TARGET_DIR="${1:-.}"

log_info "[Conformance:Static] Auditing NSA-CISA compliance with kubescape (${KUBESCAPE_VERSION})..."

render_charts "${TARGET_DIR}"
if [[ ${#MANIFESTS[@]} -eq 0 ]]; then
  log_info "No Helm chart found in ${TARGET_DIR}, skipping."
  exit 0
fi

for MANIFEST in "${MANIFESTS[@]}"; do
  APP_NAME=$(basename "${MANIFEST}" .yaml)
  # kubescape exits non-zero both on findings and on its own failures: capture
  # the report, then require either a result summary or the explicit
  # "nothing to scan" message so a crashed scan is never read as a pass.
  SCAN_STATUS=0
  SCAN_OUTPUT=$(run_tool_or_docker kubescape "${KUBESCAPE_IMAGE}" scan framework nsa "${MANIFEST}" --severity-threshold high 2>&1) || SCAN_STATUS=$?
  if echo "${SCAN_OUTPUT}" | grep -q "no resources found to scan"; then
    log_info "No standard workload resources in ${APP_NAME} to scan with kubescape, skipping."
  elif echo "${SCAN_OUTPUT}" | grep -E -q "│ *(Critical|High) │ [1-9]"; then
    echo "${SCAN_OUTPUT}" >&2
    log_error "kubescape detected compliance failures in ${APP_NAME}."
    exit 1
  elif ! echo "${SCAN_OUTPUT}" | grep -E -q "│ *(Critical|High) │ +0"; then
    echo "${SCAN_OUTPUT}" >&2
    log_error "kubescape did not produce a result summary for ${APP_NAME} (exit code ${SCAN_STATUS})."
    exit 1
  fi
done

log_pass "kubescape compliance verified."
