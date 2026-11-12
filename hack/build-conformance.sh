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

IMAGE_TAG="${REGISTRY:-ghcr.io/moderserver}/conformance:${CONFORMANCE_TAG:-latest}"

log_info "Building ModerServer Conformance container image (${IMAGE_TAG})..."

docker build \
  -f "${CORE_ROOT}/test/conformance/Dockerfile" \
  -t "${IMAGE_TAG}" \
  "${CORE_ROOT}"

log_pass "Successfully built Conformance image: ${IMAGE_TAG}"
