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

EXTRA_ARGS=()
if [[ -n "${SELECTOR}" ]]; then
  EXTRA_ARGS+=("-l" "${SELECTOR}")
fi

# Dump the current config
TMP_KUBECONFIG=$(mktemp)
kubectl config view --raw > "${TMP_KUBECONFIG}"
chmod 644 "${TMP_KUBECONFIG}"
trap 'rm -f "${TMP_KUBECONFIG}"' EXIT

log_info "[Conformance:Runtime] Sanitizing active namespace '${NAMESPACE}' with popeye (${POPEYE_VERSION})..."

docker run --rm \
  --net=host \
  -v "${TMP_KUBECONFIG}:/tmp/kubeconfig" \
  -e KUBECONFIG=/tmp/kubeconfig \
  "${POPEYE_IMAGE}" \
  --kubeconfig /tmp/kubeconfig \
  --namespace "${NAMESPACE}" \
  "${EXTRA_ARGS[@]}" \
  --min-score 70 \
  --save=false \
  --out standard

log_pass "popeye runtime sanitization completed."
