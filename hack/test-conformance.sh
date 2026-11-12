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

COMPONENT="${1:-${COMPONENT:-}}"

if [[ -n "${COMPONENT}" ]]; then
  TARGET="${COMPONENT}"
  if [[ ! -d "${TARGET}" && -d "${CORE_ROOT}/platform/components/${COMPONENT}" ]]; then
    TARGET="${CORE_ROOT}/platform/components/${COMPONENT}"
  fi

  log_info "Executing Conformance Suite for component: ${COMPONENT} (${TARGET})..."
  "${CORE_ROOT}/test/conformance/run.sh" --static "${TARGET}"
else
  log_info "Executing Conformance Suite across all platform components..."
  for comp in "${CORE_ROOT}/platform/components"/*; do
    if [[ -d "${comp}" ]]; then
      log_info "Component: $(basename "${comp}")"
      "${CORE_ROOT}/test/conformance/run.sh" --static "${comp}"
    fi
  done
fi

log_pass "Platform conformance verification completed successfully."
