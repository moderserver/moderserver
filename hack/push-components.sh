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
require_tool docker

# Publishes platform component images from the archives produced by
# `hack/build-components.sh --save-dir`. Pushing the saved archives (instead of
# rebuilding) guarantees the registry receives exactly the images that were
# tested.

LOAD_DIR="${1:-${OUTPUT_DIR}/images}"

if [[ -z "$(ls -A "${LOAD_DIR}"/*.tar 2>/dev/null)" ]]; then
  log_error "No image archives found in ${LOAD_DIR}."
  exit 1
fi

PUSHED=0
for archive in "${LOAD_DIR}"/*.tar; do
  ref=$(docker load -i "${archive}" | sed -n 's/^Loaded image: //p')
  case "${ref}" in
    "${REGISTRY}"/*)
      log_info "Pushing image: ${ref}..."
      docker push "${ref}"
      PUSHED=$((PUSHED + 1))
      ;;
    *)
      log_info "Skipping ${ref:-$(basename "${archive}")} (not a ${REGISTRY} image)."
      ;;
  esac
done

if [[ "${PUSHED}" -eq 0 ]]; then
  log_error "No ${REGISTRY} image found in ${LOAD_DIR}."
  exit 1
fi

log_pass "Published ${PUSHED} platform component image(s) to ${REGISTRY}."
