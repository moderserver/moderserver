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

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

log_info "Verifying shell scripts with ShellCheck (${SHELLCHECK_VERSION})..."

mapfile -t SCRIPTS < <(find "${CORE_ROOT}/hack" "${CORE_ROOT}/bootstrap" "${CORE_ROOT}/os" "${CORE_ROOT}/platform" "${CORE_ROOT}/test" -type f -name "*.sh" -o -name "k3s-service")

if [[ ${#SCRIPTS[@]} -gt 0 ]]; then
  run_tool_or_docker shellcheck "${SHELLCHECK_IMAGE}" --severity=error "${SCRIPTS[@]}"
fi

log_pass "ShellCheck verification passed."
