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

# renovate: datasource=docker depName=ghcr.io/gitleaks/gitleaks
GITLEAKS_VERSION="v8.30.1"
GITLEAKS_IMAGE="ghcr.io/gitleaks/gitleaks:${GITLEAKS_VERSION}"

# renovate: datasource=docker depName=koalaman/shellcheck
SHELLCHECK_VERSION="v0.11.0"
SHELLCHECK_IMAGE="koalaman/shellcheck:${SHELLCHECK_VERSION}"

# renovate: datasource=docker depName=renovate/renovate
RENOVATE_VERSION="44.239.1"
RENOVATE_IMAGE="renovate/renovate:${RENOVATE_VERSION}"

# renovate: datasource=docker depName=alpine
ALPINE_VERSION="3.24.4"

# renovate: datasource=pypi depName=yamllint
YAMLLINT_VERSION="1.38.0"

# renovate: datasource=github-releases depName=k3s-io/k3s
K3S_VERSION="v1.37.2+k3s1"

# renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
GATEWAY_API_CRD_VERSION="v1.7.0"

# renovate: datasource=github-releases depName=kubernetes/kubernetes
K8S_TARGET_VERSION="1.37.2"

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

# Registry all platform component images are published to
REGISTRY="${REGISTRY:-ghcr.io/moderserver}"

# Conformance suite image: the single toolchain every conformance check runs in
CONFORMANCE_IMAGE="${CONFORMANCE_IMAGE:-${REGISTRY}/conformance:latest}"

# component_image_tag <component_dir>
#
# Content-addressed tag of a component's images: <appVersion>-<hash of build inputs>.
# The build inputs are the Dockerfile* and *.sh files at the root of the component.
# Must stay in sync with the "common.images.tag" Helm helper
# (platform/common/templates/_images.tpl); hack/verify-image-tags.sh enforces it.
component_image_tag() {
  local comp_dir="$1"
  local app_version="latest"
  if [[ -f "${comp_dir}/Chart.yaml" ]]; then
    app_version=$(awk '/^appVersion:/ {print $2}' "${comp_dir}/Chart.yaml" | tr -d '"' | tr '+' '-')
  fi
  local hash
  hash=$(
    cd "${comp_dir}"
    {
      find . -maxdepth 1 -type f -name 'Dockerfile*' | LC_ALL=C sort
      find . -maxdepth 1 -type f -name '*.sh' | LC_ALL=C sort
    } | while IFS= read -r f; do cat "${f}"; done | sha256sum | cut -c1-12
  )
  echo "${app_version}-${hash}"
}

# component_image_names <component_dir>
#
# Prints one image name per Dockerfile of the component:
#   Dockerfile        -> <component>
#   Dockerfile.<sub>  -> <component>-<sub>
component_image_names() {
  local comp_dir="$1"
  local comp_name df suffix
  comp_name=$(basename "${comp_dir}")
  find "${comp_dir}" -maxdepth 1 -type f -name 'Dockerfile*' ! -name '*.dockerignore' | LC_ALL=C sort | while IFS= read -r df; do
    suffix=$(basename "${df}")
    if [[ "${suffix}" == Dockerfile.* ]]; then
      echo "${comp_name}-${suffix#Dockerfile.}"
    else
      echo "${comp_name}"
    fi
  done
}

# use_test_cluster
#
# Gives a test script a cluster to run against. When KUBECONFIG already points
# at one it is used as is; otherwise a ModerServer QEMU machine is installed,
# started and waited for, and stopped again when the calling script exits.
# Sets TEST_CLUSTER_STARTED to "true" when the machine was started here.
use_test_cluster() {
  TEST_CLUSTER_STARTED=false
  if [[ -f "${KUBECONFIG:-}" ]]; then
    return 0
  fi

  TEST_CLUSTER_STARTED=true
  trap 'log_info "Stopping test cluster..."; "${HACK_DIR}/run-qemu.sh" --stop >/dev/null 2>&1 || true' EXIT INT TERM
  log_info "Bootstrapping ModerServer cluster via hack/run-qemu.sh..."
  "${HACK_DIR}/run-qemu.sh" --daemon
  "${HACK_DIR}/run-qemu.sh" --wait
  KUBECONFIG=$("${HACK_DIR}/run-qemu.sh" --kubeconfig)
  export KUBECONFIG
}

# run_conformance <extra docker run arguments...> -- <conformance suite arguments...>
#
# Runs the conformance suite inside the conformance image, as the calling user
# so files written to the mounted workspace keep their owner. The image is
# built from the working tree first, unless CONFORMANCE_SKIP_BUILD=true (CI
# loads the image built once for the whole pipeline).
run_conformance() {
  require_tool docker
  if [[ "${CONFORMANCE_SKIP_BUILD:-false}" != "true" ]]; then
    "${HACK_DIR}/build-conformance.sh" >/dev/null
  fi

  local docker_args=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do
    docker_args+=("$1")
    shift
  done
  shift

  # Scanner databases are cached between runs
  local cache_dir="${OUTPUT_DIR}/conformance-cache"
  mkdir -p "${cache_dir}"

  docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -e USER=conformance \
    -e TRIVY_CACHE_DIR=/cache/trivy \
    -v "${cache_dir}:/cache" \
    "${docker_args[@]}" \
    "${CONFORMANCE_IMAGE}" "$@"
}

# build_chart_dependencies <chart_dir>
#
# Packages the chart's local dependencies (the common library) into its charts/
# directory. The archives are build outputs, not sources: they are ignored by
# Git and rebuilt from platform/common whenever a chart is rendered.
build_chart_dependencies() {
  local chart="$1"
  if grep -q '^dependencies:' "${chart}/Chart.yaml"; then
    helm dependency build "${chart}" >/dev/null
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
