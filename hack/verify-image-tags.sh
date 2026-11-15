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
require_tool helm

# Image tags are content-addressed (<appVersion>-<hash of the build inputs>) and
# computed twice: by the build scripts (component_image_tag in hack/lib/common.sh)
# and by the charts ("common.images.tag" Helm helper). If the two ever disagree,
# nodes are told to run images that were never built.
log_info "Verifying chart image references match the tags the build produces..."

FAILED=0
for comp in "${CORE_ROOT}/platform/components"/*; do
  [[ -d "${comp}" ]] || continue
  mapfile -t names < <(component_image_names "${comp}")
  [[ ${#names[@]} -gt 0 ]] || continue

  tag=$(component_image_tag "${comp}")
  build_chart_dependencies "${comp}"
  rendered=$(helm template verify "${comp}")
  for name in "${names[@]}"; do
    if echo "${rendered}" | grep -q -F "${REGISTRY}/${name}:${tag}"; then
      continue
    fi
    # Split form used by resources that take repository and tag separately
    if echo "${rendered}" | grep -q -F "repository: \"${REGISTRY}/${name}\"" && echo "${rendered}" | grep -q -F "tag: \"${tag}\""; then
      continue
    fi
    log_error "$(basename "${comp}"): chart does not reference ${REGISTRY}/${name}:${tag}"
    FAILED=$((FAILED + 1))
  done
done

if [[ "${FAILED}" -gt 0 ]]; then
  log_error "Found ${FAILED} image(s) built with a tag the charts do not reference."
  exit 1
fi

log_pass "Chart image references match the built image tags."
