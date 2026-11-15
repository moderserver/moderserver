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

# run_static <directory>: static conformance of one directory, inside the
# conformance image. The Docker socket lets the suite build and scan the
# component's images with the host's Docker daemon.
run_static() {
  local target workspace relative
  target="$(cd "$1" && pwd)"
  case "${target}" in
    "${CORE_ROOT}"/*)
      workspace="${CORE_ROOT}"
      relative="${target#"${CORE_ROOT}"/}"
      ;;
    *)
      workspace="${target}"
      relative="."
      ;;
  esac

  CONFORMANCE_SKIP_BUILD="${CONFORMANCE_SKIP_BUILD:-${IMAGE_READY:-false}}" run_conformance \
    -v "${workspace}:/workspace" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    --group-add "$(stat -c '%g' /var/run/docker.sock)" \
    -e "REGISTRY=${REGISTRY}" \
    -- --static "${relative}"
  IMAGE_READY=true
}

if [[ -n "${COMPONENT}" ]]; then
  TARGET="${COMPONENT}"
  if [[ ! -d "${TARGET}" && -d "${CORE_ROOT}/platform/components/${COMPONENT}" ]]; then
    TARGET="${CORE_ROOT}/platform/components/${COMPONENT}"
  fi

  log_info "Executing Conformance Suite for component: ${COMPONENT} (${TARGET})..."
  run_static "${TARGET}"
else
  log_info "Executing Conformance Suite across all platform components..."
  for comp in "${CORE_ROOT}/platform/components"/*; do
    if [[ -d "${comp}" ]]; then
      log_info "Component: $(basename "${comp}")"
      run_static "${comp}"
    fi
  done
fi

log_pass "Platform conformance verification completed successfully."
