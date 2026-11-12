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
require_tool docker

REGISTRY="${REGISTRY:-ghcr.io/moderserver}"
PUSH="${PUSH:-false}"
SAVE_DIR="${SAVE_DIR:-}"
TARGET_COMPONENT=""

# renovate: datasource=docker depName=alpine
ALPINE_VERSION="3.24.4"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --push)
      PUSH="true"
      shift
      ;;
    --save-dir)
      SAVE_DIR="$2"
      shift 2
      ;;
    -h|--help)
      echo "Build platform component container images"
      echo ""
      echo "Usage: $0 [options] [component_name]"
      echo ""
      echo "Options:"
      echo "  --push              Push built images to registry"
      echo "  --save-dir <path>   Save built image tarballs to directory"
      exit 0
      ;;
    *)
      TARGET_COMPONENT="$1"
      shift
      ;;
  esac
done

if [[ -n "${SAVE_DIR}" ]]; then
  mkdir -p "${SAVE_DIR}"
fi

build_component() {
  local comp_dir="$1"
  local comp_name
  comp_name=$(basename "${comp_dir}")

  if [[ ! -f "${comp_dir}/Dockerfile" ]]; then
    return 0
  fi

  local version="latest"
  if [[ -f "${comp_dir}/Chart.yaml" ]]; then
    version=$(awk '/^appVersion:/ {print $2}' "${comp_dir}/Chart.yaml" | tr -d '"' | tr '+' '-')
  fi

  local image_tag="${REGISTRY}/${comp_name}:${version}"
  log_info "Building image: ${image_tag} from ${comp_dir}..."
  docker build -t "${image_tag}" "${comp_dir}"

  if [[ -n "${SAVE_DIR}" ]]; then
    local tar_path="${SAVE_DIR}/${comp_name}.tar"
    log_info "Saving image archive to ${tar_path}..."
    docker save "${image_tag}" -o "${tar_path}"
  fi

  if [[ "${PUSH}" == "true" ]]; then
    log_info "Pushing image: ${image_tag}..."
    docker push "${image_tag}"
  fi

  log_pass "Built component image: ${image_tag}"
}

if [[ -n "${TARGET_COMPONENT}" ]]; then
  comp_path="${CORE_ROOT}/platform/components/${TARGET_COMPONENT}"
  if [[ ! -d "${comp_path}" ]]; then
    comp_path="${TARGET_COMPONENT}"
  fi
  build_component "${comp_path}"
else
  log_info "Building all platform component container images..."
  for comp in "${CORE_ROOT}/platform/components"/*; do
    if [[ -d "${comp}" && -f "${comp}/Dockerfile" ]]; then
      build_component "${comp}"
    fi
  done

  if [[ -n "${SAVE_DIR}" ]]; then
    log_info "Caching base workload image (alpine:${ALPINE_VERSION}) for offline E2E..."
    docker pull "alpine:${ALPINE_VERSION}" >/dev/null 2>&1 || true
    docker save "alpine:${ALPINE_VERSION}" -o "${SAVE_DIR}/alpine.tar" >/dev/null 2>&1 || true
  fi
fi

log_pass "Platform component images built successfully."
