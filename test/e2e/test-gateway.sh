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

# Where the node's ports 80/443 are reachable from the machine running the test
GATEWAY_ADDRESS="${GATEWAY_ADDRESS:-127.0.0.1}"
GATEWAY_HTTP_PORT="${GATEWAY_HTTP_PORT:-80}"
GATEWAY_HTTPS_PORT="${GATEWAY_HTTPS_PORT:-443}"
# Host of an application routed through the gateway, as configured on the node
HOST=$(kubectl get httproute -n argocd argocd-server -o jsonpath='{.spec.hostnames[0]}')

echo "--> [E2E] Verifying platform gateway routing and TLS..."

# 1. The Gateway is programmed and served by a running data plane
kubectl wait --for=condition=Programmed gateway/moderserver-gateway -n nginx-gateway --timeout=120s >/dev/null
DATA_PLANE_READY=$(kubectl get pods -n nginx-gateway -l gateway.networking.k8s.io/gateway-name=moderserver-gateway \
  -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' | grep -c true || true)
if [ "${DATA_PLANE_READY}" -lt 1 ]; then
  echo "FAIL: Gateway reports Programmed but has no ready data plane pod." >&2
  kubectl get pods -n nginx-gateway -o wide >&2 || true
  exit 1
fi
echo "    [PASS] Gateway is programmed and its data plane is running."

# 2. HTTPS on the node's port 443 reaches an application through its HTTPRoute
HTTPS_CODE=""
for _ in $(seq 1 30); do
  HTTPS_CODE=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 \
    --resolve "${HOST}:${GATEWAY_HTTPS_PORT}:${GATEWAY_ADDRESS}" \
    "https://${HOST}:${GATEWAY_HTTPS_PORT}/healthz" || true)
  if [ "${HTTPS_CODE}" = "200" ]; then
    break
  fi
  sleep 3
done
if [ "${HTTPS_CODE}" != "200" ]; then
  echo "FAIL: https://${HOST}/healthz returned '${HTTPS_CODE}' through the gateway (expected 200)." >&2
  exit 1
fi
echo "    [PASS] https://${HOST} is served through the gateway on port 443."

# 3. The certificate is issued by the platform CA
ISSUER=$(echo | openssl s_client -connect "${GATEWAY_ADDRESS}:${GATEWAY_HTTPS_PORT}" -servername "${HOST}" 2>/dev/null \
  | openssl x509 -noout -issuer 2>/dev/null || true)
if ! echo "${ISSUER}" | grep -q "ModerServer Root CA"; then
  echo "FAIL: Gateway certificate is not issued by the ModerServer Root CA (issuer: '${ISSUER}')." >&2
  exit 1
fi
echo "    [PASS] Gateway certificate is issued by the ModerServer Root CA."

# 4. Plain HTTP is never served: port 80 redirects to HTTPS
HTTP_RESULT=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 5 \
  --resolve "${HOST}:${GATEWAY_HTTP_PORT}:${GATEWAY_ADDRESS}" \
  "http://${HOST}:${GATEWAY_HTTP_PORT}/" || true)
case "${HTTP_RESULT}" in
  "301 https://${HOST}"*) ;;
  *)
    echo "FAIL: http://${HOST}/ returned '${HTTP_RESULT}' (expected a 301 redirect to https)." >&2
    exit 1
    ;;
esac
echo "    [PASS] Plain HTTP on port 80 redirects to HTTPS."

echo "--> [PASS] Gateway routing and TLS validation succeeded."
