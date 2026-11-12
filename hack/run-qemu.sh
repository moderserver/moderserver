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
require_tool helm
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
    --kubeconfig)
      echo "${KUBECONFIG_OUT}"
      exit 0
      ;;
    -h|--help)
      echo "ModerServer QEMU Appliance & Demo Runner"
      echo ""
      echo "Usage:"
      echo "  $0                  Start interactive ModerServer QEMU machine (Ctrl+C to stop)"
      echo "  $0 --daemon         Start ModerServer QEMU machine in background and export kubeconfig"
      echo "  $0 --stop           Stop and clean up running ModerServer QEMU machine"
      echo "  $0 --status         Check status of the ModerServer QEMU machine"
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
  rm -rf "${RUN_DIR}"
  log_pass "ModerServer QEMU machine stopped cleanly."
}

if [[ "${MODE}" == "stop" ]]; then
  stop_vm
  exit 0
fi

if [[ "${MODE}" == "status" ]]; then
  if [[ -f "${PID_FILE}" ]]; then
    pid=$(cat "${PID_FILE}" 2>/dev/null || true)
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      log_info "ModerServer QEMU machine is RUNNING (PID: ${pid})."
      log_info "Kubeconfig: ${KUBECONFIG_OUT}"
      exit 0
    fi
  fi
  log_info "ModerServer QEMU machine is NOT running."
  exit 0
fi

# Ensure previous instance is stopped
if [[ -f "${PID_FILE}" ]]; then
  stop_vm
fi

# 1. Ensure project appliance ISO exists
# renovate: datasource=docker depName=alpine
ALPINE_VERSION="3.24.4"
IMAGE_ISO="${OUTPUT_DIR}/moderserver-alpine-${ALPINE_VERSION}.iso"
if [[ ! -f "${IMAGE_ISO}" ]]; then
  log_error "ModerServer appliance image not found: ${IMAGE_ISO}"
  log_error "Please run 'make build-image' first before starting the QEMU machine."
  exit 1
fi

# 2. Prepare ephemeral virtual test disk
rm -rf "${RUN_DIR}"
mkdir -p "${RUN_DIR}"

VM_DISK="${RUN_DIR}/disk.qcow2"
qemu-img create -f qcow2 "${VM_DISK}" 10G >/dev/null

SERIAL_LOG="${RUN_DIR}/serial.log"
touch "${SERIAL_LOG}"

# 3. Determine KVM hardware acceleration
KVM_FLAGS=()
if [[ -w /dev/kvm ]]; then
  log_info "Hardware virtualization (/dev/kvm) detected. Enabling KVM acceleration..."
  KVM_FLAGS=("-enable-kvm" "-cpu" "host")
fi

# 4. Launch ModerServer Appliance ISO in QEMU
log_info "Spawning ModerServer QEMU Virtual Machine (4GB RAM, 2 vCPUs)..."
qemu-system-x86_64 \
  "${KVM_FLAGS[@]}" \
  -m 4096 -smp 2 \
  -boot d \
  -cdrom "${IMAGE_ISO}" \
  -drive file="${VM_DISK}",if=virtio,format=qcow2 \
  -netdev user,id=net0,hostfwd=tcp::${PORT_API}-:6443,hostfwd=tcp::${PORT_HTTP}-:80,hostfwd=tcp::${PORT_HTTPS}-:443 \
  -device virtio-net-pci,netdev=net0 \
  -serial file:"${SERIAL_LOG}" \
  -nographic >/dev/null 2>&1 &
QEMU_PID=$!
echo "${QEMU_PID}" > "${PID_FILE}"

log_info "Waiting for ModerServer OS to boot and initialize K3s..."
TIMEOUT=120
ELAPSED=0
while [[ "${ELAPSED}" -lt "${TIMEOUT}" ]]; do
  if grep -q "===BEGIN_MODERSERVER_KUBECONFIG===" "${SERIAL_LOG}" 2>/dev/null && grep -q "===END_MODERSERVER_KUBECONFIG===" "${SERIAL_LOG}" 2>/dev/null; then
    break
  fi
  if ! kill -0 "${QEMU_PID}" 2>/dev/null; then
    log_error "QEMU process exited unexpectedly."
    cat "${SERIAL_LOG}" >&2
    exit 1
  fi
  sleep 1
  ELAPSED=$((ELAPSED + 1))
done

if [[ "${ELAPSED}" -ge "${TIMEOUT}" ]]; then
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
# Ensure server URL points to forwarded host port
sed -i -E "s#server: https://.*:6443#server: https://127.0.0.1:${PORT_API}#" "${KUBECONFIG_OUT}"
chmod 600 "${KUBECONFIG_OUT}"
export KUBECONFIG="${KUBECONFIG_OUT}"

log_info "Waiting for Kubernetes API server to become responsive on port ${PORT_API}..."
API_READY=false
for _ in $(seq 1 45); do
  if kubectl --kubeconfig "${KUBECONFIG_OUT}" --request-timeout=2s get nodes >/dev/null 2>&1; then
    API_READY=true
    break
  fi
  sleep 1
done

if [[ "${API_READY}" != "true" ]]; then
  log_error "Kubernetes API server in ModerServer VM did not respond in time."
  stop_vm
  exit 1
fi

log_pass "ModerServer QEMU Virtual Machine is online!"
sleep 5

# Deploy platform layer
log_info "Deploying ModerServer Platform Layer (platform/system)..."
PLATFORM_SYSTEM="${CORE_ROOT}/platform/system"
(
  cd "${PLATFORM_SYSTEM}"
  helm dependency update >/dev/null 2>&1 || true
)

DEPLOY_OK=false
for _ in $(seq 1 5); do
  if helm upgrade --install moderserver-platform "${PLATFORM_SYSTEM}" \
    --kubeconfig "${KUBECONFIG_OUT}" \
    --namespace moderserver-system \
    --create-namespace \
    --force-conflicts; then
    DEPLOY_OK=true
    break
  fi
  sleep 3
done

if [[ "${DEPLOY_OK}" != "true" ]]; then
  log_error "Failed to deploy ModerServer platform layer."
  stop_vm
  exit 1
fi

log_pass "ModerServer Platform Layer deployed."

if [[ "${MODE}" == "daemon" ]]; then
  log_pass "ModerServer QEMU virtual machine running in background (PID: ${QEMU_PID})."
  echo "KUBECONFIG=${KUBECONFIG_OUT}"
  exit 0
fi

# Interactive Demo Banner
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
echo ""
echo -e "  ${COLOR_INFO}How to deploy an application:${COLOR_RESET}"
echo -e "    helm install mealie ../apps/catalog/mealie"
echo ""
echo -e "  ${COLOR_WARN}To shut down the cluster:${COLOR_RESET}"
echo -e "    Press [Ctrl+C] in this terminal, or run: ./hack/run-qemu.sh --stop"
echo -e "${COLOR_SUCCESS}=====================================================================${COLOR_RESET}"
echo ""

cleanup_interactive() {
  echo ""
  stop_vm
  exit 0
}
trap cleanup_interactive INT TERM

while kill -0 "${QEMU_PID}" 2>/dev/null; do
  sleep 2
done
