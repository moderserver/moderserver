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
require_tool python3

RENOVATE_CONFIG="${CORE_ROOT}/.github/renovate.json"

if [[ -f "${RENOVATE_CONFIG}" ]]; then
  log_info "Validating Renovate configuration syntax..."
  python3 -c "
import json
json.load(open('${RENOVATE_CONFIG}'))
"
  log_pass "Renovate configuration is valid JSON."
fi
