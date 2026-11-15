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


use_test_cluster

# The gateway publishes the node's ports 80/443, forwarded by QEMU to these host ports
export GATEWAY_ADDRESS="127.0.0.1"
export GATEWAY_HTTP_PORT="${PORT_HTTP:-18080}"
export GATEWAY_HTTPS_PORT="${PORT_HTTPS:-18443}"

log_info "Executing E2E node, security, workload isolation and gateway suite..."
"${CORE_ROOT}/test/e2e/run.sh" --kubeconfig "${KUBECONFIG}"

if [[ "${TEST_CLUSTER_STARTED}" == "true" ]]; then
  log_info "=========================================================="
  log_info "  Stage 5: Persistence Across Reboot"
  log_info "=========================================================="
  NODE_UID_BEFORE=$(kubectl get node -o jsonpath='{.items[0].metadata.uid}')
  "${SCRIPT_DIR}/run-qemu.sh" --reboot
  "${SCRIPT_DIR}/run-qemu.sh" --wait
  NODE_UID_AFTER=$(kubectl get node -o jsonpath='{.items[0].metadata.uid}')
  if [[ "${NODE_UID_BEFORE}" != "${NODE_UID_AFTER}" ]]; then
    log_error "The node did not rejoin its own cluster after reboot (cluster state was lost)."
    exit 1
  fi
  "${CORE_ROOT}/test/e2e/test-node.sh"
  "${CORE_ROOT}/test/e2e/test-gateway.sh"
  log_pass "Node, cluster state and platform survived a reboot."
fi

log_pass "E2E infrastructure assertions executed successfully."
