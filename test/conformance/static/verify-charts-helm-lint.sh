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

log_info "[Conformance:Static] Validating Helm chart syntax..."

CHARTS=$(find "${TARGET_DIR}" -type f -name "Chart.yaml" -exec dirname {} \; 2>/dev/null || true)
if [[ -z "${CHARTS}" ]]; then
  log_info "No Helm chart found in ${TARGET_DIR}, skipping."
  exit 0
fi

for chart in ${CHARTS}; do
  log_info "Linting Helm chart: ${chart}"
  build_chart_dependencies "${chart}"
  helm lint "${chart}"
done

log_pass "Helm chart linting verified."
