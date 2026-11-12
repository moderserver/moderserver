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
source "${SCRIPT_DIR}/lib/common.sh"

CLUSTER_NAME="moderserver-e2e-cluster"
export CLUSTER_NAME

STOP_ON_EXIT=false

cleanup() {
  if [[ "${STOP_ON_EXIT}" == "true" ]]; then
    log_info "Stopping E2E test cluster..."
    "${SCRIPT_DIR}/run-qemu.sh" --stop >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

if [[ ! -f "${KUBECONFIG:-}" ]]; then
  log_info "Bootstrapping ModerServer cluster via hack/run-qemu.sh..."
  "${SCRIPT_DIR}/run-qemu.sh" --daemon
  KUBECONFIG_PATH=$("${SCRIPT_DIR}/run-qemu.sh" --kubeconfig)
  export KUBECONFIG="${KUBECONFIG_PATH}"
  STOP_ON_EXIT=true
fi

log_info "Executing E2E node, security, and workload isolation suite..."
"${CORE_ROOT}/test/e2e/run.sh" --kubeconfig "${KUBECONFIG}"

log_pass "E2E infrastructure assertions executed successfully."
