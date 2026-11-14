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
require_tool qemu-system-x86_64
require_tool qemu-img
require_tool kubectl

OUTPUT_DIR="${CORE_ROOT}/_output"
KUBECONFIG_OUT="${OUTPUT_DIR}/kubeconfig.yaml"
PID_FILE="${OUTPUT_DIR}/run-qemu.pid"
RUN_DIR="/tmp/moderserver-qemu-run"
mkdir -p "${OUTPUT_DIR}"

PORT_API="${PORT_API:-16443}"
PORT_HTTP="${PORT_HTTP:-18080}"
PORT_HTTPS="${PORT_HTTPS:-18443}"

MODE="interactive"
LOCAL_DEV="${LOCAL_DEV:-true}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --daemon|--background|-d)
      MODE="daemon"
      shift
      ;;
    --stop|stop)
      MODE="stop"
      shift
      ;;
    --status|status)
      MODE="status"
      shift
      ;;
    --wait|wait)
      MODE="wait"
      shift
      ;;
    --dev|--local)
      LOCAL_DEV="true"
      shift
      ;;
    --prod|--upstream)
      LOCAL_DEV="false"
      shift
      ;;
    --kubeconfig)
      echo "${KUBECONFIG_OUT}"
      exit 0
      ;;
    -h|--help)
      echo "ModerServer QEMU Machine & Demo Runner"
      echo ""
      echo "Usage:"
      echo "  $0                  Start interactive ModerServer QEMU machine (Ctrl+C to stop)"
      echo "  $0 --daemon         Start ModerServer QEMU machine in background and export kubeconfig"
      echo "  $0 --stop           Stop and clean up running ModerServer QEMU machine"
      echo "  $0 --status         Check status of the ModerServer QEMU machine"
      echo "  $0 --dev / --local  Enable local GitOps mirror for offline/dev testing (default)"
      echo "  $0 --prod           Use upstream GitHub repository (https://github.com/moderserver/moderserver.git)"
      echo "  $0 --kubeconfig     Print path to the generated kubeconfig file"
      exit 0
      ;;
    *)
      log_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

stop_vm() {
  docker rm -f moderserver-git-mirror >/dev/null 2>&1 || true
  if [[ -f "${PID_FILE}" ]]; then
    local pid
    pid=$(cat "${PID_FILE}" 2>/dev/null || true)
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      log_info "Stopping ModerServer QEMU virtual machine (PID: ${pid})..."
      kill "${pid}" 2>/dev/null || true
      for _ in $(seq 1 10); do
        if ! kill -0 "${pid}" 2>/dev/null; then
          break
        fi
        sleep 1
      done
      kill -9 "${pid}" 2>/dev/null || true
    fi
    rm -f "${PID_FILE}"
  fi
  pkill -f "${RUN_DIR}" 2>/dev/null || true
  if [[ -f "${SERIAL_LOG:-}" ]]; then
    cp -f "${SERIAL_LOG}" "${OUTPUT_DIR}/serial.log" 2>/dev/null || true
  fi
  rm -rf "${RUN_DIR}"
  log_pass "ModerServer QEMU machine stopped cleanly."
}

prepare_vm_storage() {
  log_info "Preparing virtual machine storage..."
  # 1. Ensure project OS image ISO exists
  # renovate: datasource=docker depName=alpine
  local alpine_version="3.24.4"
  IMAGE_ISO=$(ls -1 "${OUTPUT_DIR}"/moderserver-alpine-*.iso 2>/dev/null | head -n 1 || true)
  if [[ -z "${IMAGE_ISO}" || ! -f "${IMAGE_ISO}" ]]; then
    IMAGE_ISO="${OUTPUT_DIR}/moderserver-alpine-${alpine_version}.iso"
  fi

  if [[ ! -f "${IMAGE_ISO}" ]]; then
    log_error "ModerServer OS image not found: ${IMAGE_ISO}"
    log_error "Please run 'make build-image' first before starting the QEMU machine."
    exit 1
  fi

  # 2. Prepare ephemeral virtual test disk
  mkdir -p "${RUN_DIR}"
  rm -f "${RUN_DIR}"/*

  VM_DISK="${RUN_DIR}/disk.qcow2"
  qemu-img create -f qcow2 "${VM_DISK}" 10G >/dev/null

  SERIAL_LOG="${RUN_DIR}/serial.log"
  touch "${SERIAL_LOG}"
}

prepare_git_mirror() {
  ROOT_REPO_URL="https://github.com/moderserver/moderserver.git"

  if [[ "${LOCAL_DEV}" == "true" ]]; then
    log_info "Preparing local GitOps mirror..."
    local local_git_dir="${RUN_DIR}/git"
    mkdir -p "${local_git_dir}"
    rm -rf "${local_git_dir}/moderserver.git"
    git clone --bare "${CORE_ROOT}" "${local_git_dir}/moderserver.git" >/dev/null 2>&1
    touch "${local_git_dir}/moderserver.git/git-daemon-export-ok"

    # Snapshot current workspace files into the bare mirror without touching host git index or working tree
    local tmp_git_idx="${RUN_DIR}/temp-git-index"
    rm -f "${tmp_git_idx}"
    local local_tree local_commit
    local_tree=$(GIT_DIR="${local_git_dir}/moderserver.git" GIT_INDEX_FILE="${tmp_git_idx}" git --work-tree="${CORE_ROOT}" add -A && GIT_DIR="${local_git_dir}/moderserver.git" GIT_INDEX_FILE="${tmp_git_idx}" git write-tree)
    local_commit=$(GIT_DIR="${local_git_dir}/moderserver.git" git commit-tree "${local_tree}" -p HEAD -m "ModerServer Local Dev Snapshot" 2>/dev/null || true)
    rm -f "${tmp_git_idx}"
    if [[ -n "${local_commit}" ]]; then
      GIT_DIR="${local_git_dir}/moderserver.git" git update-ref refs/heads/main "${local_commit}"
    fi

    docker rm -f moderserver-git-mirror >/dev/null 2>&1 || true
    docker run -d --name moderserver-git-mirror \
      --net=host \
      -v "${local_git_dir}":/git \
      alpine:3.24.4 sh -c "apk add --no-cache git git-daemon >/dev/null 2>&1 && git config --global --add safe.directory '*' && exec git daemon --verbose --export-all --port=19418 --base-path=/git /git" >/dev/null 2>&1

    log_info "Waiting for local GitOps mirror to become responsive on port 19418..."
    for _ in $(seq 1 30); do
      if (echo > /dev/tcp/127.0.0.1/19418) 2>/dev/null; then
        break
      fi
      sleep 1
    done

    ROOT_REPO_URL="git://10.0.2.2:19418/moderserver.git"
    log_pass "Local GitOps mirror initialized (${ROOT_REPO_URL})."
  fi
}

start_vm() {
  local smp_cpus
  smp_cpus=$(nproc 2>/dev/null || echo 2)
  if [[ "${smp_cpus}" -gt 4 ]]; then
    smp_cpus=4
  fi

  local accel_flags=("-accel" "tcg,thread=multi" "-cpu" "max")
  if [[ -e /dev/kvm ]] && [[ -w /dev/kvm ]]; then
    log_info "Hardware virtualization (/dev/kvm) detected. Enabling KVM acceleration..."
    accel_flags=("-enable-kvm" "-cpu" "host")
  else
    log_info "Hardware acceleration not available. Enabling multi-threaded TCG emulation (${smp_cpus} vCPUs, -cpu max)..."
  fi

  local netdev_config="user,id=net0,hostfwd=tcp::${PORT_API}-:6443,hostfwd=tcp::${PORT_HTTP}-:80,hostfwd=tcp::${PORT_HTTPS}-:443"

  local smbios_flags=()
  if [[ "${LOCAL_DEV}" == "true" ]]; then
    smbios_flags=("-smbios" "type=1,serial=${ROOT_REPO_URL}")
  fi

  log_info "Spawning ModerServer QEMU Virtual Machine (4GB RAM, ${smp_cpus} vCPUs)..."
  qemu-system-x86_64 \
    "${accel_flags[@]}" \
    "${smbios_flags[@]}" \
    -m 4096 -smp "${smp_cpus}" \
    -boot d \
    -cdrom "${IMAGE_ISO}" \
    -drive file="${VM_DISK}",if=virtio,format=qcow2,cache=unsafe \
    -netdev "${netdev_config}" \
    -device virtio-net-pci,netdev=net0 \
    -serial file:"${SERIAL_LOG}" \
    -nographic >/dev/null 2>&1 &
  QEMU_PID=$!
  echo "${QEMU_PID}" > "${PID_FILE}"

  log_info "Waiting for ModerServer OS to boot and initialize K3s..."
  local timeout=120
  local elapsed=0
  while [[ "${elapsed}" -lt "${timeout}" ]]; do
    if grep -q "===BEGIN_MODERSERVER_KUBECONFIG===" "${SERIAL_LOG}" 2>/dev/null && grep -q "===END_MODERSERVER_KUBECONFIG===" "${SERIAL_LOG}" 2>/dev/null; then
      break
    fi
    if ! kill -0 "${QEMU_PID}" 2>/dev/null; then
      log_error "QEMU process exited unexpectedly."
      cat "${SERIAL_LOG}" >&2
      exit 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if [[ "${elapsed}" -ge "${timeout}" ]]; then
    log_error "Timed out waiting for ModerServer QEMU VM to initialize."
    stop_vm
    exit 1
  fi

  # Extract kubeconfig emitted by the OS
  awk '
    /===BEGIN_MODERSERVER_KUBECONFIG===/ { flag=1; block=""; next }
    /===END_MODERSERVER_KUBECONFIG===/   { flag=0; if (length(block) > 100) { printf "%s", block; exit } }
    flag { block = block $0 "\n" }
  ' "${SERIAL_LOG}" > "${KUBECONFIG_OUT}"
  sed -i -E "s#server: https://.*:6443#server: https://127.0.0.1:${PORT_API}#" "${KUBECONFIG_OUT}"
  chmod 600 "${KUBECONFIG_OUT}"
  export KUBECONFIG="${KUBECONFIG_OUT}"

  log_info "Waiting for Kubernetes API server to become responsive on port ${PORT_API}..."
  local api_ready=false
  for _ in $(seq 1 45); do
    if kubectl --kubeconfig "${KUBECONFIG_OUT}" --request-timeout=2s get nodes >/dev/null 2>&1; then
      api_ready=true
      break
    fi
    sleep 1
  done

  if [[ "${api_ready}" != "true" ]]; then
    log_error "Kubernetes API server in ModerServer VM did not respond in time."
    stop_vm
    exit 1
  fi

  log_pass "ModerServer QEMU Virtual Machine is online!"
}

wait_for_k8s_node() {
  log_info "Waiting for Kubernetes node registration (importing staged container images)..."
  local node_registered=false
  for i in $(seq 1 180); do
    if [ -n "$(kubectl --kubeconfig "${KUBECONFIG_OUT}" get nodes -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)" ]; then
      node_registered=true
      break
    fi
    if (( i % 15 == 0 )); then
      log_info "Staging in progress, waiting for Kubelet node registration (${i}/180)..."
    fi
    sleep 2
  done

  if [[ "${node_registered}" != "true" ]]; then
    log_error "Kubernetes node failed to register within timeout."
    stop_vm
    exit 1
  fi

  log_info "Waiting for Kubernetes node to reach Ready state..."
  if ! kubectl --kubeconfig "${KUBECONFIG_OUT}" wait --for=condition=Ready nodes --all --timeout=180s; then
    log_error "Kubernetes node failed to become Ready within timeout."
    stop_vm
    exit 1
  fi
  log_pass "Kubernetes node is Ready!"
}

wait_for_platform() {
  log_info "Waiting for Argo CD to reconcile and sync platform applications..."

  # 1. Ensure Argo CD control plane is healthy
  local deps=(argocd-redis argocd-repo-server argocd-application-controller)
  for dep in "${deps[@]}"; do
    for _ in $(seq 1 60); do
      if kubectl --kubeconfig "${KUBECONFIG_OUT}" get deployment -n argocd "${dep}" >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
    if ! kubectl --kubeconfig "${KUBECONFIG_OUT}" rollout status deployment -n argocd "${dep}" --timeout=180s; then
      log_error "Argo CD deployment '${dep}' failed to reach ready state. This indicates an OS/bootstrap packaging defect."
      kubectl --kubeconfig "${KUBECONFIG_OUT}" describe deployment -n argocd "${dep}" >&2 || true
      kubectl --kubeconfig "${KUBECONFIG_OUT}" describe pods -n argocd -l app.kubernetes.io/name="${dep}" >&2 || true
      exit 1
    fi
  done
  log_pass "Argo CD control plane deployments are ready."

  # 2. Wait for root Application to sync and spawn child component applications
  log_info "Waiting for Argo CD root application to reconcile and sync..."
  local root_synced=false
  for i in $(seq 1 90); do
    local root_sync root_health
    root_sync=$(kubectl --kubeconfig "${KUBECONFIG_OUT}" get application -n argocd root -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
    root_health=$(kubectl --kubeconfig "${KUBECONFIG_OUT}" get application -n argocd root -o jsonpath='{.status.health.status}' 2>/dev/null || true)
    if [[ "${root_sync}" == "Synced" && "${root_health}" == "Healthy" ]]; then
      root_synced=true
      log_pass "Argo CD root application successfully synced and healthy."
      break
    fi
    if (( i % 5 == 0 )); then
      log_info "Root application sync in progress (status: ${root_sync:-Pending}/${root_health:-Pending})..."
      kubectl --kubeconfig "${KUBECONFIG_OUT}" annotate application -n argocd root argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
    fi
    sleep 2
  done

  if [[ "${root_synced}" != "true" ]]; then
    log_error "Argo CD root application failed to sync within timeout. Diagnostics:"
    kubectl --kubeconfig "${KUBECONFIG_OUT}" describe application -n argocd root >&2 || true
    kubectl --kubeconfig "${KUBECONFIG_OUT}" logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50 >&2 || true
    kubectl --kubeconfig "${KUBECONFIG_OUT}" logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=50 >&2 || true
    exit 1
  fi

  # 3. Wait for all platform component applications to reconcile and sync
  log_info "Waiting for Argo CD platform component applications to reconcile and sync..."
  local apps=(gateway-api cert-manager cluster-issuers nginx-gateway-fabric system-upgrade-controller argocd)
  local all_ready=false
  local pending=()
  for i in $(seq 1 180); do
    all_ready=true
    pending=()
    for app in "${apps[@]}"; do
      local status health
      status=$(kubectl --kubeconfig "${KUBECONFIG_OUT}" get application -n argocd "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
      health=$(kubectl --kubeconfig "${KUBECONFIG_OUT}" get application -n argocd "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || true)
      if [[ "${status}" != "Synced" || "${health}" != "Healthy" ]]; then
        all_ready=false
        pending+=("${app}(${status:-Pending}/${health:-Pending})")
        if (( i % 10 == 0 )); then
          kubectl --kubeconfig "${KUBECONFIG_OUT}" annotate application -n argocd "${app}" argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
        fi
      fi
    done
    if [[ "${all_ready}" == "true" ]]; then
      log_pass "All platform applications successfully synced and healthy in Argo CD."
      break
    fi
    if (( i % 10 == 0 )); then
      log_info "Sync in progress, waiting on: ${pending[*]}..."
      kubectl --kubeconfig "${KUBECONFIG_OUT}" annotate application -n argocd root argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
    fi
    sleep 2
  done

  if [[ "${all_ready}" != "true" ]]; then
    log_error "Platform applications failed to reach Synced/Healthy state within timeout: ${pending[*]}"
    for app in "${apps[@]}"; do
      echo "=== Application: ${app} ===" >&2
      kubectl --kubeconfig "${KUBECONFIG_OUT}" get application -n argocd "${app}" -o yaml >&2 || true
    done
    kubectl --kubeconfig "${KUBECONFIG_OUT}" get pods -A >&2 || true
    exit 1
  fi

  # 4. Ensure all platform pods have reached Ready state
  log_info "Ensuring all platform pods have reached Ready state..."
  if ! kubectl --kubeconfig "${KUBECONFIG_OUT}" wait --for=condition=Ready pods --field-selector=status.phase!=Succeeded --all-namespaces --timeout=120s; then
    log_error "Not all platform pods reached Ready state within timeout. Pod status:"
    kubectl --kubeconfig "${KUBECONFIG_OUT}" get pods -A -o wide >&2 || true
    exit 1
  fi
  log_pass "All platform components and pods are verified ready!"
}

print_demo_banner() {
  echo ""
  echo -e "${COLOR_SUCCESS}=====================================================================${COLOR_RESET}"
  echo -e "${COLOR_SUCCESS}  ModerServer QEMU Virtual Machine is LIVE (Demo Mode)              ${COLOR_RESET}"
  echo -e "${COLOR_SUCCESS}=====================================================================${COLOR_RESET}"
  echo ""
  echo -e "  ${COLOR_INFO}Kubernetes API:${COLOR_RESET}    https://localhost:${PORT_API}"
  echo -e "  ${COLOR_INFO}Gateway HTTP:${COLOR_RESET}      http://localhost:${PORT_HTTP}"
  echo -e "  ${COLOR_INFO}Gateway HTTPS:${COLOR_RESET}     https://localhost:${PORT_HTTPS}"
  echo -e "  ${COLOR_INFO}Kubeconfig:${COLOR_RESET}        ${KUBECONFIG_OUT}"
  echo ""
  echo -e "  ${COLOR_INFO}How to connect:${COLOR_RESET}"
  echo -e "    export KUBECONFIG=${KUBECONFIG_OUT}"
  echo -e "    kubectl get nodes -o wide"
  echo -e "    kubectl get pods -A"
  echo -e "    kubectl get applications -n argocd"
  echo ""
  echo -e "  ${COLOR_WARN}To shut down the cluster:${COLOR_RESET}"
  echo -e "    Press [Ctrl+C] in this terminal, or run: ./hack/run-qemu.sh --stop"
  echo -e "${COLOR_SUCCESS}=====================================================================${COLOR_RESET}"
  echo ""
}

# --- CLI Command Dispatches ---

if [[ "${MODE}" == "stop" ]]; then
  stop_vm
  exit 0
fi

if [[ "${MODE}" == "status" ]]; then
  if [[ -f "${PID_FILE}" ]]; then
    local_pid=$(cat "${PID_FILE}" 2>/dev/null || true)
    if [[ -n "${local_pid}" ]] && kill -0 "${local_pid}" 2>/dev/null; then
      log_info "ModerServer QEMU machine is RUNNING (PID: ${local_pid})."
      log_info "Kubeconfig: ${KUBECONFIG_OUT}"
      exit 0
    fi
  fi
  log_info "ModerServer QEMU machine is NOT running."
  exit 0
fi

if [[ "${MODE}" == "wait" ]]; then
  wait_for_platform
  exit 0
fi

# Ensure previous instance is stopped
if [[ -f "${PID_FILE}" ]]; then
  stop_vm
fi

# --- Main Bootstrapping Pipeline ---

prepare_vm_storage
prepare_git_mirror
start_vm
wait_for_k8s_node

if [[ "${MODE}" == "daemon" ]]; then
  log_pass "ModerServer QEMU virtual machine running in background (PID: ${QEMU_PID})."
  echo "KUBECONFIG=${KUBECONFIG_OUT}"
  exit 0
fi

# Interactive mode
wait_for_platform
print_demo_banner

cleanup_interactive() {
  echo ""
  stop_vm
  exit 0
}
trap cleanup_interactive INT TERM

while kill -0 "${QEMU_PID}" 2>/dev/null; do
  sleep 2
done
