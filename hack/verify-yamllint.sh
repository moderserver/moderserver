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

ensure_yamllint() {
  if command -v yamllint >/dev/null 2>&1; then
    return 0
  fi
  log_info "Installing yamllint into _output/bin..."
  mkdir -p "${OUTPUT_BIN}"
  python3 -m venv "${OUTPUT_DIR}/venv"
  "${OUTPUT_DIR}/venv/bin/pip" install --quiet "yamllint==${YAMLLINT_VERSION}"
  ln -sf "${OUTPUT_DIR}/venv/bin/yamllint" "${OUTPUT_BIN}/yamllint"
}

ensure_yamllint

log_info "Verifying YAML files with yamllint..."

CONFIG="{extends: default, ignore: ['_output/**', '.tmp/**', 'platform/**/templates/**', 'platform/**/crds/**', 'platform/**/charts/**'], rules: {line-length: disable, document-start: disable, truthy: disable, comments: disable}}"

yamllint -d "${CONFIG}" bootstrap/ platform/

log_pass "YAML formatting passed yamllint verification."
