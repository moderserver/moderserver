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
require_tool docker
require_tool kubectl

NAMESPACE="${1:-default}"
SELECTOR="${2:-}"

TMP_KUBECONFIG=$(mktemp)
kubectl config view --raw > "${TMP_KUBECONFIG}"
chmod 644 "${TMP_KUBECONFIG}"
trap 'rm -f "${TMP_KUBECONFIG}"' EXIT

NAMESPACE_ARGS=()
if [[ -n "${NAMESPACE}" && "${NAMESPACE}" != "all" && "${NAMESPACE}" != "--all-namespaces" ]]; then
  NAMESPACE_ARGS=("--include-namespaces" "${NAMESPACE}")
else
  NAMESPACE_ARGS=("--exclude-namespaces" "kube-system,kube-public,kube-node-lease")
fi

log_info "[Conformance:Runtime] Auditing live cluster security with trivy k8s (${TRIVY_VERSION}) in namespace '${NAMESPACE}'..."

docker run --rm \
  --net=host \
  -v "${TMP_KUBECONFIG}:/tmp/kubeconfig" \
  -e KUBECONFIG=/tmp/kubeconfig \
  "${TRIVY_IMAGE}" \
  k8s \
  --kubeconfig /tmp/kubeconfig \
  "${NAMESPACE_ARGS[@]}" \
  --report summary \
  --scanners misconfig \
  --severity CRITICAL,HIGH \
  --exit-code 1

log_pass "trivy k8s runtime audit completed successfully."
