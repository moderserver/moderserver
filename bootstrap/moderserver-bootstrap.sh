#!/bin/sh
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

# ModerServer GitOps bootstrap, run at every boot by the moderserver-bootstrap
# OpenRC service once K3s is started.
#
#   1. First boot only: installs Argo CD from the manifests shipped with the
#      OS image. From then on Argo CD manages itself from Git and this script
#      never touches it again, so the cluster has a single owner per resource.
#   2. Every boot: applies the root Application generated from
#      /etc/moderserver/moderserver.conf, the one piece of GitOps configuration
#      that cannot come from Git (it says which Git repository to follow).

set -eu

CONF="/etc/moderserver/moderserver.conf"
MANIFESTS_DIR="/usr/share/moderserver/bootstrap"
STATE_DIR="/var/lib/moderserver"
INSTALLED_MARKER="${STATE_DIR}/argocd-installed"
KUBECONFIG_FILE="/etc/rancher/k3s/k3s.yaml"
FIELD_MANAGER="argocd-controller"

GITOPS_REPO_URL=""
GITOPS_REVISION=""
DOMAIN=""
# shellcheck disable=SC1090
. "${CONF}"

log() {
  echo "$(date '+%Y-%m-%dT%H:%M:%S%z') $*"
}

kubectl() {
  /usr/local/bin/k3s kubectl --kubeconfig "${KUBECONFIG_FILE}" "$@"
}

# Development options passed by a hypervisor as SMBIOS OEM strings
# (QEMU: -smbios type=11,value=moderserver.dev.<name>=<value>).
# Physical machines never carry these strings, so on real hardware every
# option below is off and the node only follows moderserver.conf.
dev_option() {
  for entry in /sys/firmware/dmi/entries/11-*/raw; do
    [ -r "${entry}" ] || continue
    strings "${entry}"
  done 2>/dev/null | sed -n "s/^moderserver\.dev\.$1=//p" | head -n 1
}

apply() {
  kubectl apply --server-side --force-conflicts --field-manager="${FIELD_MANAGER}" "$@"
}

install_argocd() {
  apply -f "${MANIFESTS_DIR}/argocd-crds.yaml" &&
    kubectl wait --for=condition=Established --timeout=120s \
      crd/applications.argoproj.io crd/appprojects.argoproj.io &&
    apply -f "${MANIFESTS_DIR}/argocd.yaml"
}

apply_root_application() {
  apply -f - <<MANIFEST
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: "${GITOPS_REPO_URL}"
    targetRevision: "${GITOPS_REVISION}"
    path: platform/system
    helm:
      releaseName: moderserver-platform
      valuesObject:
        global:
          domain: "${DOMAIN}"
        gitops:
          repoURL: "${GITOPS_REPO_URL}"
          targetRevision: "${GITOPS_REVISION}"
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    retry:
      limit: 10
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 3m
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
MANIFEST
}

DEV_REPO_URL="$(dev_option gitops-repo-url)"
if [ -n "${DEV_REPO_URL}" ]; then
  log "Development override: following GitOps repository ${DEV_REPO_URL}"
  GITOPS_REPO_URL="${DEV_REPO_URL}"
fi

DEV_DOMAIN="$(dev_option domain)"
if [ -n "${DEV_DOMAIN}" ]; then
  log "Development override: serving applications under ${DEV_DOMAIN}"
  DOMAIN="${DEV_DOMAIN}"
fi

log "Waiting for the Kubernetes API..."
until kubectl get --raw /readyz >/dev/null 2>&1; do
  sleep 2
done

# Development only: hand the admin kubeconfig to the hypervisor over the serial
# console so test tooling can reach the cluster without any login on the node.
if [ "$(dev_option serial-kubeconfig)" = "true" ]; then
  {
    echo "===BEGIN_MODERSERVER_KUBECONFIG==="
    cat "${KUBECONFIG_FILE}"
    echo "===END_MODERSERVER_KUBECONFIG==="
  } > /dev/ttyS0
fi

mkdir -p "${STATE_DIR}"
if [ ! -f "${INSTALLED_MARKER}" ]; then
  log "First boot: installing Argo CD from the OS image..."
  until install_argocd; do
    log "Argo CD installation not complete yet, retrying..."
    sleep 5
  done
  touch "${INSTALLED_MARKER}"
  log "Argo CD installed; it is now reconciled from Git."
fi

log "Applying root Application (${GITOPS_REPO_URL} @ ${GITOPS_REVISION})..."
until apply_root_application; do
  sleep 5
done
log "GitOps bootstrap complete."
