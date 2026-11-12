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

# 1. Test Secrets CRUD and access control
echo "    Checking Secrets management and access control..."
TEST_SECRET_NAME="e2e-secret-test"
kubectl delete secret "${TEST_SECRET_NAME}" --ignore-not-found=true >/dev/null 2>&1
kubectl create secret generic "${TEST_SECRET_NAME}" --from-literal=plaintext-token="my-super-secret-token-2026"

# Verify secret can be read back through authorized API access
RECOVERED=$(kubectl get secret "${TEST_SECRET_NAME}" -o jsonpath='{.data.plaintext-token}' | base64 -d)
if [ "${RECOVERED}" != "my-super-secret-token-2026" ]; then
  echo "FAIL: Could not retrieve secret from API." >&2
  exit 1
fi
kubectl delete secret "${TEST_SECRET_NAME}" >/dev/null 2>&1
echo "    [PASS] Secrets management verified."

# 2. Verify Anonymous Authentication is strictly rejected (CIS 1.2.1 / 4.2.1)
echo "    Checking unauthenticated anonymous access..."
if kubectl --as=system:anonymous get pods -A >/dev/null 2>&1; then
  echo "FAIL: Anonymous user was permitted to list pods." >&2
  exit 1
fi
if kubectl --as=system:anonymous get secrets -A >/dev/null 2>&1; then
  echo "FAIL: Anonymous user was permitted to read secrets." >&2
  exit 1
fi
echo "    [PASS] Anonymous access rejected."

# 3. Verify default ServiceAccount has no cluster permissions
echo "    Checking default ServiceAccount privilege restrictions..."
if kubectl auth can-i create pods --as=system:serviceaccount:default:default >/dev/null 2>&1; then
  echo "FAIL: Default service account has unauthorized pod creation permissions." >&2
  exit 1
fi
echo "    [PASS] Default service account permissions properly restricted."

echo "--> [PASS] All security assertions passed."
