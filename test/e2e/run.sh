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
CORE_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${CORE_ROOT}/hack/lib/common.sh"
require_tool kubectl

KUBECONFIG_PATH="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kubeconfig)
      KUBECONFIG_PATH="$2"
      shift 2
      ;;
    *)
      log_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

export KUBECONFIG="${KUBECONFIG_PATH}"

if [[ ! -f "${KUBECONFIG}" ]]; then
  log_error "Kubeconfig file not found at: ${KUBECONFIG}"
  exit 1
fi

log_info "Connecting to cluster using kubeconfig: ${KUBECONFIG}..."
kubectl cluster-info >/dev/null

log_info "=========================================================="
log_info "  Stage 1: Node & Cluster Infrastructure Assertions"
log_info "=========================================================="
"${SCRIPT_DIR}/test-node.sh"

log_info "=========================================================="
log_info "  Stage 2: Kubelet & CIS Security Profile Assertions"
log_info "=========================================================="
"${SCRIPT_DIR}/test-security.sh"

log_info "=========================================================="
log_info "  Stage 3: Workload Isolation & DNS Assertions"
log_info "=========================================================="
"${SCRIPT_DIR}/test-workload.sh"

log_pass "End-to-End infrastructure and security assertions PASSED."
