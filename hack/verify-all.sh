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

log_info "==> Step 1: Checking copyright boilerplate..."
"${HACK_DIR}/verify-boilerplate.sh"

log_info "==> Step 2: Checking shell scripts with ShellCheck..."
"${HACK_DIR}/verify-shellcheck.sh"

log_info "==> Step 3: Checking GitHub Actions workflows with actionlint..."
"${HACK_DIR}/verify-actionlint.sh"

log_info "==> Step 4: Checking YAML formatting with yamllint..."
"${HACK_DIR}/verify-yamllint.sh"

log_info "==> Step 5: Checking Renovate configuration..."
"${HACK_DIR}/verify-renovate.sh"

log_info "==> Step 6: Checking for secret leaks with Gitleaks..."
"${HACK_DIR}/verify-gitleaks.sh"

log_pass "All core static verifications passed successfully."
