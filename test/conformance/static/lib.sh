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

# Shared by the static chart checks (verify-charts-*.sh).

# render_charts <target_dir>
#
# Renders every Helm chart found under <target_dir> and stores the manifest
# paths in the MANIFESTS array (empty when the directory holds no chart).
#
# test/conformance/run.sh exports CONFORMANCE_RENDER_DIR so that all checks of a
# run share one render. A check started on its own renders into a temporary
# directory that is removed when the script exits.
render_charts() {
  local target_dir="$1"
  MANIFESTS=()
  require_tool helm

  local charts
  mapfile -t charts < <(find "${target_dir}" -type f -name "Chart.yaml" -exec dirname {} \; 2>/dev/null | LC_ALL=C sort)
  if [[ ${#charts[@]} -eq 0 ]]; then
    return 0
  fi

  if [[ -z "${CONFORMANCE_RENDER_DIR:-}" ]]; then
    CONFORMANCE_RENDER_DIR=$(mktemp -d)
    chmod 755 "${CONFORMANCE_RENDER_DIR}"
    # shellcheck disable=SC2064
    trap "rm -rf '${CONFORMANCE_RENDER_DIR}'" EXIT
  fi

  local chart name manifest
  for chart in "${charts[@]}"; do
    name=$(basename "${chart}")
    manifest="${CONFORMANCE_RENDER_DIR}/${name}.yaml"
    if [[ ! -f "${manifest}" ]]; then
      build_chart_dependencies "${chart}"
      helm template --include-crds "${name}-test" "${chart}" > "${manifest}"
      chmod 644 "${manifest}"
    fi
    MANIFESTS+=("${manifest}")
  done
}
