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

KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
export KUBECONFIG

echo "--> [E2E] Verifying Kubernetes node readiness..."

# 1. Wait for at least one node to report Ready
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# 2. Assert node details
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
NODE_STATUS=$(kubectl get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}')
KUBELET_VERSION=$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}')
OS_IMAGE=$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.osImage}')

if [ "${NODE_STATUS}" != "True" ]; then
  echo "FAIL: Node ${NODE_NAME} is not in Ready state." >&2
  exit 1
fi

echo "--> [PASS] Node '${NODE_NAME}' is Ready (Kubelet: ${KUBELET_VERSION}, OS: ${OS_IMAGE})"
