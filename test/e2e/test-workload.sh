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

echo "--> [E2E] Verifying workload execution and cluster DNS..."

TEST_POD="e2e-dns-check"
kubectl delete pod "${TEST_POD}" --ignore-not-found=true >/dev/null 2>&1

kubectl run "${TEST_POD}" \
  --image="alpine:3.21" \
  --restart=Never \
  --overrides='{"spec":{"automountServiceAccountToken":false,"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"dns","image":"alpine:3.21","command":["sh","-c","nslookup kubernetes.default.svc.cluster.local && sleep 3600"],"securityContext":{"readOnlyRootFilesystem":true,"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' \
  >/dev/null 2>&1

# Wait for pod to reach Running state
kubectl wait --for=condition=Ready pod/"${TEST_POD}" --timeout=60s

# Verify DNS resolution in pod logs
sleep 2
LOGS=$(kubectl logs "${TEST_POD}")
if echo "${LOGS}" | grep -q "10.43.0.1"; then
  echo "    [PASS] Cluster DNS resolved kubernetes.default to 10.43.0.1"
else
  echo "FAIL: Unexpected DNS resolution output: ${LOGS}" >&2
  kubectl delete pod "${TEST_POD}" >/dev/null 2>&1 || true
  exit 1
fi

kubectl delete pod "${TEST_POD}" >/dev/null 2>&1
echo "--> [PASS] Workload execution and DNS validation succeeded."
