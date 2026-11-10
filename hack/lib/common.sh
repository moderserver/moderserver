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

HACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_ROOT="$(cd "${HACK_DIR}/.." && pwd)"
OUTPUT_DIR="${CORE_ROOT}/_output"
OUTPUT_BIN="${OUTPUT_DIR}/bin"

export PATH="${OUTPUT_BIN}:${PATH}"

# renovate: datasource=docker depName=rhysd/actionlint
ACTIONLINT_VERSION="1.7.12"
ACTIONLINT_IMAGE="rhysd/actionlint:${ACTIONLINT_VERSION}"

# renovate: datasource=docker depName=koalaman/shellcheck
SHELLCHECK_VERSION="v0.11.0"
SHELLCHECK_IMAGE="koalaman/shellcheck:${SHELLCHECK_VERSION}"

# renovate: datasource=pypi depName=yamllint
YAMLLINT_VERSION="1.38.0"

# renovate: datasource=github-releases depName=k3s-io/k3s
K3S_VERSION="v1.37.2+k3s1"

# Colors for terminal output
COLOR_INFO="\033[36m"
COLOR_SUCCESS="\033[32m"
COLOR_WARN="\033[33m"
COLOR_ERROR="\033[31m"
COLOR_RESET="\033[0m"

log_info() {
  echo -e "${COLOR_INFO}==> INFO:${COLOR_RESET} $*"
}

log_pass() {
  echo -e "${COLOR_SUCCESS}==> [PASS]:${COLOR_RESET} $*"
}

log_warn() {
  echo -e "${COLOR_WARN}==> WARN:${COLOR_RESET} $*"
}

log_error() {
  echo -e "${COLOR_ERROR}==> ERROR:${COLOR_RESET} $*" >&2
}

require_tool() {
  local tool="$1"
  if ! command -v "${tool}" >/dev/null 2>&1; then
    log_error "Required tool '${tool}' is not installed or not in PATH."
    exit 1
  fi
}

run_tool_or_docker() {
  local tool="$1"
  local image="$2"
  shift 2
  if command -v "${tool}" >/dev/null 2>&1; then
    "${tool}" "$@"
  elif command -v docker >/dev/null 2>&1; then
    local sock_mount=()
    if [[ -S /var/run/docker.sock ]]; then
      sock_mount=("-v" "/var/run/docker.sock:/var/run/docker.sock")
    fi
    docker run --rm \
      -v "${CORE_ROOT}:${CORE_ROOT}" \
      -v /tmp:/tmp \
      "${sock_mount[@]}" \
      -w "${CORE_ROOT}" \
      "${image}" "$@"
  else
    log_error "Neither '${tool}' nor 'docker' is installed."
    exit 1
  fi
}
