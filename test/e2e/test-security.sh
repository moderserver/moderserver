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

# 4. Verify namespaces without Pod Security labels still enforce the baseline profile
echo "    Checking cluster-wide Pod Security defaults..."
if kubectl run e2e-privileged-test --image=alpine --restart=Never --privileged -- true >/dev/null 2>&1; then
  kubectl delete pod e2e-privileged-test --ignore-not-found=true >/dev/null 2>&1
  echo "FAIL: A privileged pod was admitted in a namespace without Pod Security labels." >&2
  exit 1
fi
echo "    [PASS] Privileged pods are rejected by default."

# 5. Verify platform credentials are generated per install, never shipped in Git
echo "    Checking Argo CD credentials are generated on the node..."
REDIS_PASSWORD=$(kubectl get secret -n argocd argocd-redis -o jsonpath='{.data.auth}' | base64 -d)
SERVER_KEY=$(kubectl get secret -n argocd argocd-secret -o jsonpath='{.data.server\.secretkey}' | base64 -d)
if [ "${#REDIS_PASSWORD}" -lt 16 ] || [ "${#SERVER_KEY}" -lt 16 ]; then
  echo "FAIL: Argo CD Redis password or server secret key is missing or too short." >&2
  exit 1
fi
if grep -rqF -e "${REDIS_PASSWORD}" -e "${SERVER_KEY}" "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/platform"; then
  echo "FAIL: Argo CD credentials found in the platform sources." >&2
  exit 1
fi
echo "    [PASS] Argo CD credentials are unique to this install."

# 6. Verify network isolation: an arbitrary pod cannot reach platform internals
echo "    Checking network isolation of platform services..."
NP_POD="e2e-netpol-check"
# renovate: datasource=docker depName=alpine
NP_ALPINE_VERSION="3.24.4"
NP_IMAGE="alpine:${NP_ALPINE_VERSION}"
NP_SCRIPT='for t in argocd-redis.argocd:6379 argocd-server.argocd:80 argocd-repo-server.argocd:8081 moderserver-gateway-nginx.nginx-gateway:443; do if nc -w 3 -z ${t%:*} ${t#*:} 2>/dev/null; then echo "OPEN $t"; else echo "BLOCKED $t"; fi; done'
kubectl delete pod "${NP_POD}" --ignore-not-found=true >/dev/null 2>&1
kubectl run "${NP_POD}" \
  --image="${NP_IMAGE}" \
  --restart=Never \
  --overrides='{"spec":{"automountServiceAccountToken":false,"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"check","image":"'"${NP_IMAGE}"'","command":["sh","-c",'"$(printf '%s' "${NP_SCRIPT}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"'],"securityContext":{"readOnlyRootFilesystem":true,"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' \
  >/dev/null
if ! kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/"${NP_POD}" --timeout=120s >/dev/null; then
  echo "FAIL: Network isolation probe pod did not complete." >&2
  kubectl describe pod "${NP_POD}" >&2 || true
  kubectl delete pod "${NP_POD}" >/dev/null 2>&1 || true
  exit 1
fi
NP_RESULT=$(kubectl logs "${NP_POD}")
kubectl delete pod "${NP_POD}" >/dev/null 2>&1
EXPECTED_RESULT="BLOCKED argocd-redis.argocd:6379
BLOCKED argocd-server.argocd:80
BLOCKED argocd-repo-server.argocd:8081
OPEN moderserver-gateway-nginx.nginx-gateway:443"
if [ "${NP_RESULT}" != "${EXPECTED_RESULT}" ]; then
  echo "FAIL: Unexpected network reachability from an unprivileged pod:" >&2
  echo "${NP_RESULT}" >&2
  exit 1
fi
echo "    [PASS] Platform internals are isolated; only the gateway is reachable."

echo "--> [PASS] All security assertions passed."
