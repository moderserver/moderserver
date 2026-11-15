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
require_tool python3

KUBECONFIG_OUT="${OUTPUT_DIR}/kubeconfig.yaml"
PID_FILE="${OUTPUT_DIR}/run-qemu.pid"
RUN_DIR="/tmp/moderserver-qemu-run"
STATE_FILE="${RUN_DIR}/state.env"
VM_DISK="${RUN_DIR}/disk.qcow2"
SERIAL_LOG="${RUN_DIR}/serial.log"
INSTALL_LOG="${RUN_DIR}/install.log"
MONITOR_SOCK="${RUN_DIR}/monitor.sock"
mkdir -p "${OUTPUT_DIR}"

PORT_API="${PORT_API:-16443}"
PORT_HTTP="${PORT_HTTP:-18080}"
PORT_HTTPS="${PORT_HTTPS:-18443}"

# bios (default) or uefi: firmware the virtual machine installs and boots with
FIRMWARE="${FIRMWARE:-bios}"
OVMF_DIR="${OVMF_DIR:-/usr/share/edk2/ovmf}"

# Seconds to wait for the unattended installation and for a boot to reach K3s
INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-900}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-420}"

MODE="interactive"
LOCAL_DEV="${LOCAL_DEV:-true}"
GITOPS_MIRROR_PORT=19418
GITOPS_MIRROR_URL="git://10.0.2.2:${GITOPS_MIRROR_PORT}/moderserver.git"

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
    --reboot|reboot)
      MODE="reboot"
      shift
      ;;
    --sync|sync)
      MODE="sync"
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
      echo "Boots the installer ISO on a blank virtual disk (unattended, offline"
      echo "installation), then boots the installed system from that disk alone."
      echo ""
      echo "Usage:"
      echo "  $0                  Install and start an interactive ModerServer QEMU machine (Ctrl+C to stop)"
      echo "  $0 --daemon         Install and start the machine in background and export kubeconfig"
      echo "  $0 --wait           Wait until the platform of the running machine is fully reconciled"
      echo "  $0 --reboot         Gracefully power the running machine off and boot it again from its disk"
      echo "  $0 --sync           Publish the current working tree to the running machine's GitOps mirror"
      echo "  $0 --stop           Stop and clean up the running ModerServer QEMU machine"
      echo "  $0 --status         Check status of the ModerServer QEMU machine"
      echo "  $0 --dev / --local  Follow a local GitOps mirror of this working tree (default)"
      echo "  $0 --prod           Follow the Git repository configured in bootstrap/moderserver.conf"
      echo "  $0 --kubeconfig     Print path to the generated kubeconfig file"
      echo ""
      echo "Environment:"
      echo "  FIRMWARE=bios|uefi  Firmware to install and boot with (default: bios)"
      echo "  DEV_DOMAIN=<domain> Domain applications are served under in --dev mode (default: localhost)"
      exit 0
      ;;
    *)
      log_error "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Revision the node follows (and therefore the branch the local mirror must serve)
GITOPS_REVISION=$(sed -n 's/^GITOPS_REVISION="\(.*\)"$/\1/p' "${CORE_ROOT}/bootstrap/moderserver.conf")
DOMAIN=$(sed -n 's/^DOMAIN="\(.*\)"$/\1/p' "${CORE_ROOT}/bootstrap/moderserver.conf")
# In --dev mode applications are served under *.localhost, which browsers and
# curl resolve to this machine on their own: no DNS or /etc/hosts change needed.
DEV_DOMAIN="${DEV_DOMAIN:-localhost}"
if [[ "${LOCAL_DEV}" == "true" ]]; then
  DOMAIN="${DEV_DOMAIN}"
fi

vm_pid() {
  local pid=""
  if [[ -f "${PID_FILE}" ]]; then
    pid=$(cat "${PID_FILE}" 2>/dev/null || true)
  fi
  if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
    echo "${pid}"
  fi
}

save_logs() {
  if [[ -f "${INSTALL_LOG}" ]]; then
    cp -f "${INSTALL_LOG}" "${OUTPUT_DIR}/install.log"
  fi
  if [[ -f "${SERIAL_LOG}" ]]; then
    cp -f "${SERIAL_LOG}" "${OUTPUT_DIR}/serial.log"
  fi
}

kill_vm() {
  local pid
  pid=$(vm_pid)
  if [[ -n "${pid}" ]]; then
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
}

stop_vm() {
  docker rm -f moderserver-git-mirror >/dev/null 2>&1 || true
  if [[ -n "$(vm_pid)" ]]; then
    log_info "Stopping ModerServer QEMU virtual machine (PID: $(vm_pid))..."
  fi
  kill_vm
  pkill -f "${RUN_DIR}" 2>/dev/null || true
  save_logs
  rm -rf "${RUN_DIR}"
  log_pass "ModerServer QEMU machine stopped cleanly."
}

prepare_vm_storage() {
  log_info "Preparing virtual machine storage..."
  IMAGE_ISO="${OUTPUT_DIR}/moderserver-alpine-${ALPINE_VERSION}.iso"
  if [[ ! -f "${IMAGE_ISO}" ]]; then
    log_error "ModerServer installer image not found: ${IMAGE_ISO}"
    log_error "Please run 'make build-image' first before starting the QEMU machine."
    exit 1
  fi

  rm -rf "${RUN_DIR}"
  mkdir -p "${RUN_DIR}"
  qemu-img create -f qcow2 "${VM_DISK}" 20G >/dev/null

  if [[ "${FIRMWARE}" == "uefi" ]]; then
    if [[ ! -f "${OVMF_DIR}/OVMF_CODE_4M.qcow2" || ! -f "${OVMF_DIR}/OVMF_VARS_4M.qcow2" ]]; then
      log_error "UEFI firmware (OVMF_CODE_4M.qcow2, OVMF_VARS_4M.qcow2) not found in ${OVMF_DIR}; set OVMF_DIR."
      exit 1
    fi
    cp "${OVMF_DIR}/OVMF_VARS_4M.qcow2" "${RUN_DIR}/uefi-vars.qcow2"
  fi
}

# Snapshot the current working tree (committed or not) into the bare mirror, on
# the branch the node follows, without touching the host index or working tree
snapshot_working_tree() {
  local mirror="${RUN_DIR}/git/moderserver.git"
  if [[ ! -d "${mirror}" ]]; then
    log_error "No local GitOps mirror found (is a machine running in --dev mode?)."
    exit 1
  fi
  local tmp_git_idx="${RUN_DIR}/temp-git-index"
  local parent local_tree local_commit
  parent=$(GIT_DIR="${mirror}" git rev-parse --verify --quiet "refs/heads/${GITOPS_REVISION}" || GIT_DIR="${mirror}" git rev-parse HEAD)
  local_tree=$(GIT_DIR="${mirror}" GIT_INDEX_FILE="${tmp_git_idx}" git --work-tree="${CORE_ROOT}" add -A && GIT_DIR="${mirror}" GIT_INDEX_FILE="${tmp_git_idx}" git write-tree)
  # The snapshot commit only lives in the throwaway mirror: give it a fixed
  # identity so it works on machines with no Git identity configured (CI runners)
  local_commit=$(GIT_DIR="${mirror}" git \
    -c user.name="ModerServer Dev Snapshot" -c user.email="dev-snapshot@moderserver.invalid" \
    commit-tree "${local_tree}" -p "${parent}" -m "ModerServer Local Dev Snapshot")
  rm -f "${tmp_git_idx}"
  GIT_DIR="${mirror}" git update-ref "refs/heads/${GITOPS_REVISION}" "${local_commit}"
}

prepare_git_mirror() {
  if [[ "${LOCAL_DEV}" != "true" ]]; then
    return 0
  fi
  require_tool docker

  log_info "Preparing local GitOps mirror..."
  local local_git_dir="${RUN_DIR}/git"
  mkdir -p "${local_git_dir}"
  git clone --bare "${CORE_ROOT}" "${local_git_dir}/moderserver.git" >/dev/null 2>&1
  touch "${local_git_dir}/moderserver.git/git-daemon-export-ok"
  snapshot_working_tree

  docker rm -f moderserver-git-mirror >/dev/null 2>&1 || true
  docker run -d --name moderserver-git-mirror \
    --net=host \
    -v "${local_git_dir}":/git \
    "alpine:${ALPINE_VERSION}" sh -c "apk add --no-cache git git-daemon >/dev/null 2>&1 && git config --global --add safe.directory '*' && exec git daemon --verbose --export-all --port=${GITOPS_MIRROR_PORT} --base-path=/git /git" >/dev/null

  log_info "Waiting for local GitOps mirror to become responsive on port ${GITOPS_MIRROR_PORT}..."
  local mirror_ready=false
  for _ in $(seq 1 60); do
    if (echo > "/dev/tcp/127.0.0.1/${GITOPS_MIRROR_PORT}") 2>/dev/null; then
      mirror_ready=true
      break
    fi
    sleep 1
  done
  if [[ "${mirror_ready}" != "true" ]]; then
    log_error "Local GitOps mirror did not start."
    docker logs moderserver-git-mirror >&2 || true
    exit 1
  fi
  log_pass "Local GitOps mirror initialized (${GITOPS_MIRROR_URL}, branch ${GITOPS_REVISION})."
}

# Common QEMU arguments (machine, CPU, firmware, system disk) in QEMU_ARGS
qemu_base_args() {
  local smp_cpus
  smp_cpus=$(nproc 2>/dev/null || echo 2)
  if [[ "${smp_cpus}" -gt 4 ]]; then
    smp_cpus=4
  fi

  QEMU_ARGS=("-accel" "tcg,thread=multi" "-cpu" "max")
  if [[ -e /dev/kvm ]] && [[ -w /dev/kvm ]]; then
    QEMU_ARGS=("-enable-kvm" "-cpu" "host")
  fi
  QEMU_ARGS+=("-m" "4096" "-smp" "${smp_cpus}" "-display" "none")
  QEMU_ARGS+=("-drive" "file=${VM_DISK},if=virtio,format=qcow2,cache=unsafe")

  if [[ "${FIRMWARE}" == "uefi" ]]; then
    QEMU_ARGS+=("-machine" "q35")
    QEMU_ARGS+=("-drive" "if=pflash,format=qcow2,unit=0,readonly=on,file=${OVMF_DIR}/OVMF_CODE_4M.qcow2")
    QEMU_ARGS+=("-drive" "if=pflash,format=qcow2,unit=1,file=${RUN_DIR}/uefi-vars.qcow2")
  fi
}

# Stage 1: boot the installer ISO on the blank disk. The installer runs
# unattended and powers the machine off when done. The network card is present
# but isolated (restrict=on), which proves the installation is fully offline.
install_vm() {
  qemu_base_args
  if [[ -e /dev/kvm ]] && [[ -w /dev/kvm ]]; then
    log_info "Hardware virtualization (/dev/kvm) detected. KVM acceleration enabled."
  else
    log_info "Hardware acceleration not available. Using multi-threaded TCG emulation."
  fi

  log_info "Installing ModerServer from ${IMAGE_ISO} (${FIRMWARE}, offline, unattended)..."
  : > "${INSTALL_LOG}"
  qemu-system-x86_64 \
    "${QEMU_ARGS[@]}" \
    -boot d \
    -cdrom "${IMAGE_ISO}" \
    -nic user,model=virtio-net-pci,restrict=on \
    -no-reboot \
    -serial file:"${INSTALL_LOG}" >/dev/null 2>&1 &
  local pid=$!
  echo "${pid}" > "${PID_FILE}"

  local elapsed=0
  while kill -0 "${pid}" 2>/dev/null; do
    if grep -q "===MODERSERVER_INSTALL_FAILED===" "${INSTALL_LOG}" 2>/dev/null; then
      break
    fi
    if [[ "${elapsed}" -ge "${INSTALL_TIMEOUT}" ]]; then
      log_error "Timed out after ${INSTALL_TIMEOUT}s waiting for the installation to finish."
      break
    fi
    if (( elapsed > 0 && elapsed % 30 == 0 )); then
      log_info "Installation in progress (${elapsed}s)..."
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if kill -0 "${pid}" 2>/dev/null || ! grep -q "===MODERSERVER_INSTALL_COMPLETE===" "${INSTALL_LOG}"; then
    log_error "ModerServer installation did not complete. Installer console:"
    cat "${INSTALL_LOG}" >&2
    kill_vm
    save_logs
    exit 1
  fi
  rm -f "${PID_FILE}"
  log_pass "ModerServer installed on the virtual disk in ${elapsed}s."
}

# Stage 2: boot the installed system from its disk alone (no installation media)
start_vm() {
  qemu_base_args

  # Development options read by bootstrap/moderserver-bootstrap.sh on the node
  local dev_options="value=moderserver.dev.serial-kubeconfig=true"
  if [[ "${LOCAL_DEV}" == "true" ]]; then
    dev_options+=",value=moderserver.dev.gitops-repo-url=${GITOPS_MIRROR_URL}"
    dev_options+=",value=moderserver.dev.domain=${DEV_DOMAIN}"
  fi

  log_info "Booting ModerServer from its disk (4GB RAM)..."
  : > "${SERIAL_LOG}"
  rm -f "${MONITOR_SOCK}"
  qemu-system-x86_64 \
    "${QEMU_ARGS[@]}" \
    -smbios "type=11,${dev_options}" \
    -netdev "user,id=net0,hostfwd=tcp::${PORT_API}-:6443,hostfwd=tcp::${PORT_HTTP}-:80,hostfwd=tcp::${PORT_HTTPS}-:443" \
    -device virtio-net-pci,netdev=net0 \
    -monitor "unix:${MONITOR_SOCK},server,nowait" \
    -serial file:"${SERIAL_LOG}" >/dev/null 2>&1 &
  QEMU_PID=$!
  echo "${QEMU_PID}" > "${PID_FILE}"

  log_info "Waiting for ModerServer OS to boot and initialize K3s..."
  local elapsed=0
  while [[ "${elapsed}" -lt "${BOOT_TIMEOUT}" ]]; do
    if grep -q "===END_MODERSERVER_KUBECONFIG===" "${SERIAL_LOG}" 2>/dev/null; then
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

  if [[ "${elapsed}" -ge "${BOOT_TIMEOUT}" ]]; then
    log_error "Timed out after ${BOOT_TIMEOUT}s waiting for ModerServer to boot. Serial console:"
    tail -n 60 "${SERIAL_LOG}" >&2
    stop_vm
    exit 1
  fi

  # Extract kubeconfig emitted by the node (development option serial-kubeconfig)
  awk '
    /===BEGIN_MODERSERVER_KUBECONFIG===/ { flag=1; block=""; next }
    /===END_MODERSERVER_KUBECONFIG===/   { flag=0; if (length(block) > 100) { printf "%s", block; exit } }
    flag { block = block $0 "\n" }
  ' "${SERIAL_LOG}" | tr -d '\r' > "${KUBECONFIG_OUT}"
  sed -i -E "s#server: https://.*:6443#server: https://127.0.0.1:${PORT_API}#" "${KUBECONFIG_OUT}"
  chmod 600 "${KUBECONFIG_OUT}"
  export KUBECONFIG="${KUBECONFIG_OUT}"

  log_info "Waiting for Kubernetes API server to become responsive on port ${PORT_API}..."
  local api_ready=false
  for _ in $(seq 1 60); do
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

  log_pass "ModerServer QEMU Virtual Machine is online (booted in ${elapsed}s)!"
}

# Graceful power-off (ACPI power button, handled by acpid on the node)
power_off_vm() {
  local pid
  pid=$(vm_pid)
  if [[ -z "${pid}" ]]; then
    log_error "ModerServer QEMU machine is not running."
    exit 1
  fi
  log_info "Powering off ModerServer gracefully..."
  python3 -c '
import socket, sys, time
s = socket.socket(socket.AF_UNIX)
s.connect(sys.argv[1])
time.sleep(0.5)
s.sendall(b"system_powerdown\n")
time.sleep(1)
' "${MONITOR_SOCK}"
  for _ in $(seq 1 120); do
    if ! kill -0 "${pid}" 2>/dev/null; then
      rm -f "${PID_FILE}"
      log_pass "ModerServer powered off cleanly."
      return 0
    fi
    sleep 1
  done
  log_error "ModerServer did not power off within 120s."
  exit 1
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
  local kubectl=(kubectl --kubeconfig "${KUBECONFIG_OUT}")

  # 1. The node installs Argo CD from the OS image at first boot
  log_info "Waiting for Argo CD to be installed and started by the node..."
  local dep
  for dep in argocd-redis argocd-repo-server argocd-application-controller; do
    for _ in $(seq 1 90); do
      if "${kubectl[@]}" get deployment -n argocd "${dep}" >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done
    if ! "${kubectl[@]}" rollout status deployment -n argocd "${dep}" --timeout=180s; then
      log_error "Argo CD deployment '${dep}' failed to reach ready state. This indicates an OS/bootstrap packaging defect."
      "${kubectl[@]}" describe deployment -n argocd "${dep}" >&2 || true
      "${kubectl[@]}" get pods -n argocd -o wide >&2 || true
      exit 1
    fi
  done
  log_pass "Argo CD control plane deployments are ready."

  # 2. Argo CD reconciles the root Application and every component it declares.
  #    The list of components comes from the cluster (platform/system), not from here.
  log_info "Waiting for Argo CD to reconcile the platform applications..."
  local states pending=""
  for i in $(seq 1 240); do
    states=$("${kubectl[@]}" get applications -n argocd \
      -o jsonpath='{range .items[*]}{.metadata.name}={.status.sync.status}/{.status.health.status}{"\n"}{end}' 2>/dev/null || true)
    pending=$(echo "${states}" | grep -v -e '=Synced/Healthy$' -e '^$' | tr '\n' ' ' || true)
    # The root Application creates the others once it is synced
    if echo "${states}" | grep -q '^root=Synced/Healthy$' && [[ "$(echo "${states}" | grep -c .)" -gt 1 && -z "${pending}" ]]; then
      log_pass "All platform applications are synced and healthy in Argo CD: $(echo "${states}" | cut -d= -f1 | tr '\n' ' ')"
      break
    fi
    if (( i % 10 == 0 )); then
      log_info "Sync in progress, waiting on: ${pending:-root application}..."
      "${kubectl[@]}" annotate application -n argocd --all argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
    fi
    pending="${pending:-root application}"
    sleep 2
  done

  if [[ -n "${pending}" ]]; then
    log_error "Platform applications failed to reach Synced/Healthy state within timeout: ${pending}"
    "${kubectl[@]}" get applications -n argocd -o yaml >&2 || true
    "${kubectl[@]}" logs -n argocd -l app.kubernetes.io/component=application-controller --tail=50 >&2 || true
    "${kubectl[@]}" logs -n argocd -l app.kubernetes.io/component=repo-server --tail=50 >&2 || true
    "${kubectl[@]}" get pods -A >&2 || true
    exit 1
  fi

  # 3. The Gateway must be programmed by its data plane, not merely declared
  log_info "Waiting for the platform Gateway to be programmed..."
  if ! "${kubectl[@]}" wait --for=condition=Programmed gateway/moderserver-gateway -n nginx-gateway --timeout=180s; then
    log_error "Gateway 'moderserver-gateway' was not programmed within timeout."
    "${kubectl[@]}" describe gateway -n nginx-gateway moderserver-gateway >&2 || true
    "${kubectl[@]}" get pods -n nginx-gateway -o wide >&2 || true
    exit 1
  fi

  # 4. Ensure all platform pods have reached Ready state
  log_info "Ensuring all platform pods have reached Ready state..."
  if ! "${kubectl[@]}" wait --for=condition=Ready pods --field-selector=status.phase!=Succeeded --all-namespaces --timeout=180s; then
    log_error "Not all platform pods reached Ready state within timeout. Pod status:"
    "${kubectl[@]}" get pods -A -o wide >&2 || true
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
  echo -e "  ${COLOR_INFO}Gateway HTTPS:${COLOR_RESET}     port ${PORT_HTTPS} (HTTP on ${PORT_HTTP} only redirects to HTTPS)"
  echo -e "  ${COLOR_INFO}Argo CD:${COLOR_RESET}           https://argocd.${DOMAIN}:${PORT_HTTPS}"
  echo -e "  ${COLOR_INFO}Kubeconfig:${COLOR_RESET}        ${KUBECONFIG_OUT}"
  echo ""
  echo -e "  The gateway routes by hostname: open the application URL above, not"
  echo -e "  https://localhost:${PORT_HTTPS} (which matches no application and answers 404)."
  if [[ "${DOMAIN}" != "localhost" ]]; then
    echo -e "  Make the application names resolve to this machine first:"
    echo -e "    echo '127.0.0.1 argocd.${DOMAIN}' | sudo tee -a /etc/hosts"
  fi
  echo -e "  The certificate is issued by the server's own CA, so a browser warns once."
  echo -e "  Argo CD admin password:"
  echo -e "    kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
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
  if [[ -n "$(vm_pid)" ]]; then
    log_info "ModerServer QEMU machine is RUNNING (PID: $(vm_pid))."
    log_info "Kubeconfig: ${KUBECONFIG_OUT}"
    exit 0
  fi
  log_info "ModerServer QEMU machine is NOT running."
  exit 0
fi

if [[ "${MODE}" == "wait" ]]; then
  wait_for_platform
  exit 0
fi

if [[ "${MODE}" == "sync" ]]; then
  snapshot_working_tree
  kubectl --kubeconfig "${KUBECONFIG_OUT}" annotate application -n argocd --all argocd.argoproj.io/refresh=hard --overwrite >/dev/null
  log_pass "Working tree published to the GitOps mirror; Argo CD is reconciling it."
  exit 0
fi

if [[ "${MODE}" == "reboot" ]]; then
  if [[ ! -f "${STATE_FILE}" ]]; then
    log_error "No ModerServer QEMU machine to reboot (start one with '$0 --daemon')."
    exit 1
  fi
  # shellcheck disable=SC1090
  source "${STATE_FILE}"
  power_off_vm
  start_vm
  wait_for_k8s_node
  exit 0
fi

# Ensure previous instance is stopped
if [[ -f "${PID_FILE}" || -d "${RUN_DIR}" ]]; then
  stop_vm
fi

# --- Main Bootstrapping Pipeline ---

prepare_vm_storage
prepare_git_mirror
install_vm
cat > "${STATE_FILE}" <<STATE
LOCAL_DEV="${LOCAL_DEV}"
FIRMWARE="${FIRMWARE}"
STATE
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
