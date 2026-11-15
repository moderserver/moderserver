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

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../hack" && pwd)/lib/common.sh"
require_tool docker
require_tool trivy

TARGET_DIR="${1:-.}"

log_info "[Conformance:Static] Scanning container images for CVE vulnerabilities with trivy..."

DOCKERFILES=$(find "${TARGET_DIR}" -type f -name "Dockerfile*" ! -name "*.dockerignore" 2>/dev/null || true)
if [[ -z "${DOCKERFILES}" ]]; then
  log_info "No Dockerfiles found in ${TARGET_DIR}, skipping image scan."
  exit 0
fi

for df in ${DOCKERFILES}; do
  COMPONENT_DIR=$(dirname "${df}")
  COMPONENT_NAME=$(basename "${COMPONENT_DIR}")
  df_name=$(basename "${df}")
  if [[ "${df_name}" == Dockerfile.* ]]; then
    COMPONENT_NAME="${COMPONENT_NAME}-${df_name#Dockerfile.}"
  fi
  IMAGE_TAG="${REGISTRY}/${COMPONENT_NAME}:$(component_image_tag "${COMPONENT_DIR}")"

  # An image that cannot be built is a conformance failure, never a skipped scan
  if ! docker image inspect "${IMAGE_TAG}" >/dev/null 2>&1; then
    log_info "Building image locally for vulnerability scanning: ${IMAGE_TAG}..."
    docker build -f "${df}" -t "${IMAGE_TAG}" "${COMPONENT_DIR}" >/dev/null
  fi

  log_info "Scanning image: ${IMAGE_TAG}"
  trivy image --scanners vuln --exit-code 1 --severity CRITICAL,HIGH "${IMAGE_TAG}"
  log_pass "trivy vulnerability scan passed for: ${COMPONENT_NAME}"
done

log_pass "Container image vulnerability conformance verified."
