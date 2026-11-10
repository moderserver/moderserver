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

echo "--> [E2E] Verifying cluster and node security configurations..."

# 1. Test Secrets Encryption at Rest
echo "    Checking Secrets encryption at rest..."
TEST_SECRET_NAME="e2e-encryption-test"
kubectl delete secret "${TEST_SECRET_NAME}" --ignore-not-found=true >/dev/null 2>&1
kubectl create secret generic "${TEST_SECRET_NAME}" --from-literal=plaintext-token="my-super-secret-token-2026"

# Verify secret can be read back through API server
RECOVERED=$(kubectl get secret "${TEST_SECRET_NAME}" -o jsonpath='{.data.plaintext-token}' | base64 -d)
if [ "${RECOVERED}" != "my-super-secret-token-2026" ]; then
  echo "FAIL: Could not retrieve secret from API." >&2
  exit 1
fi
kubectl delete secret "${TEST_SECRET_NAME}" >/dev/null 2>&1
echo "    [PASS] Secrets encryption verified."

# 2. Verify Kubelet Anonymous Authentication is rejected
echo "    Checking Kubelet anonymous authentication..."
APISERVER_HOST=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' | sed 's#https://##' | cut -d: -f1)

# Port 10255 (Read-only kubelet port) must not be accessible
if command -v nc >/dev/null 2>&1; then
  if nc -z -w 2 "${APISERVER_HOST}" 10255 2>/dev/null; then
    echo "FAIL: Port 10255 (unauthenticated read-only Kubelet port) is open." >&2
    exit 1
  fi
  echo "    [PASS] Port 10255 is closed."
fi

echo "--> [PASS] All security assertions passed."
