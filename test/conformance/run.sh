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
source "${SCRIPT_DIR}/../../hack/lib/common.sh"

MODE="--static"
TARGET="${CORE_ROOT}/platform/components/gateway-api"
NAMESPACE="default"
SELECTOR="app.kubernetes.io/part-of=moderserver"

if [[ $# -gt 0 ]]; then
  case "$1" in
    --static)
      MODE="--static"
      TARGET="${2:-${TARGET}}"
      ;;
    --runtime)
      MODE="--runtime"
      NAMESPACE="${2:-${NAMESPACE}}"
      SELECTOR="${3:-${SELECTOR}}"
      ;;
    --all)
      MODE="--all"
      TARGET="${2:-${TARGET}}"
      NAMESPACE="${3:-${NAMESPACE}}"
      SELECTOR="${4:-${SELECTOR}}"
      ;;
    -h|--help)
      echo "ModerServer Conformance Suite"
      echo ""
      echo "Usage:"
      echo "  $0 --static [target_directory]              Run static compliance checks (hadolint, kubeconform, trivy, polaris...)"
      echo "  $0 --runtime [namespace]                    Run live cluster security checks (popeye, trivy k8s)"
      echo "  $0 --all [target_dir] [namespace]           Run all checks (static + runtime)"
      exit 0
      ;;
    *)
      TARGET="$1"
      ;;
  esac
fi

run_static_conformance() {
  local dir="$1"
  log_info "=========================================================="
  log_info "  Running ModerServer Static Conformance on: ${dir}"
  log_info "=========================================================="

  "${SCRIPT_DIR}/static/verify-image-hadolint.sh" "${dir}"
  "${SCRIPT_DIR}/static/verify-image-trivy.sh" "${dir}"
  "${SCRIPT_DIR}/static/verify-charts-helm-lint.sh" "${dir}"
  "${SCRIPT_DIR}/static/verify-charts-kubeconform.sh" "${dir}"
  "${SCRIPT_DIR}/static/verify-charts-kube-linter.sh" "${dir}"
  "${SCRIPT_DIR}/static/verify-charts-polaris.sh" "${dir}"
  "${SCRIPT_DIR}/static/verify-charts-kubescape.sh" "${dir}"
  "${SCRIPT_DIR}/static/verify-charts-trivy.sh" "${dir}"

  log_pass "Static Conformance PASSED for: ${dir}"
}

run_runtime_conformance() {
  local ns="$1"
  local selector="${2:-}"
  log_info "=========================================================="
  log_info "  Running ModerServer Runtime Conformance on ns: ${ns}"
  log_info "=========================================================="

  "${SCRIPT_DIR}/runtime/verify-runtime-popeye.sh" "${ns}" "${selector}"
  "${SCRIPT_DIR}/runtime/verify-runtime-trivy.sh" "${ns}" "${selector}"

  log_pass "Runtime Conformance PASSED on namespace: ${ns}"
}

case "${MODE}" in
  --static)
    run_static_conformance "${TARGET}"
    ;;
  --runtime)
    run_runtime_conformance "${NAMESPACE}" "${SELECTOR}"
    ;;
  --all)
    run_static_conformance "${TARGET}"
    run_runtime_conformance "${NAMESPACE}" "${SELECTOR}"
    ;;
esac
