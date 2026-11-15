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

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../hack" && pwd)/lib/common.sh"
require_tool docker
require_tool kubectl
require_tool python3

NAMESPACE="${1:-default}"
SELECTOR="${2:-}"

TMP_KUBECONFIG=$(mktemp)
kubectl config view --raw > "${TMP_KUBECONFIG}"
chmod 644 "${TMP_KUBECONFIG}"

EXCEPTIONS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/exceptions"

NAMESPACE_ARGS=()
if [[ -n "${NAMESPACE}" && "${NAMESPACE}" != "all" && "${NAMESPACE}" != "--all-namespaces" ]]; then
  NAMESPACE_ARGS=("--include-namespaces" "${NAMESPACE}")
else
  NAMESPACE_ARGS=("--exclude-namespaces" "kube-system,kube-public,kube-node-lease")
fi

log_info "[Conformance:Runtime] Auditing live cluster security with trivy k8s (${TRIVY_VERSION}) in namespace '${NAMESPACE}'..."

REPORT=$(mktemp)
trap 'rm -f "${TMP_KUBECONFIG}" "${REPORT}"' EXIT

docker run --rm \
  --net=host \
  -v "${TMP_KUBECONFIG}:/tmp/kubeconfig" \
  -e KUBECONFIG=/tmp/kubeconfig \
  "${TRIVY_IMAGE}" \
  k8s \
  --kubeconfig /tmp/kubeconfig \
  "${NAMESPACE_ARGS[@]}" \
  --report all \
  --format json \
  --quiet \
  --scanners misconfig \
  --severity CRITICAL,HIGH > "${REPORT}"

# The report is evaluated here rather than with trivy's --exit-code: in cluster
# mode trivy cannot scope an accepted finding to one namespace. A finding is
# accepted only if exceptions/<namespace>.trivyignore lists its ID, so every
# other namespace is held to the checks with no exception at all.
python3 - "${REPORT}" "${EXCEPTIONS_DIR}" <<'PYTHON'
import json
import os
import sys

report_path, exceptions_dir = sys.argv[1], sys.argv[2]

with open(report_path) as report_file:
    report = json.load(report_file)


def accepted_ids(namespace):
    path = os.path.join(exceptions_dir, f"{namespace}.trivyignore")
    if not os.path.isfile(path):
        return set()
    with open(path) as exceptions_file:
        lines = (line.split("#", 1)[0].strip() for line in exceptions_file)
        return {line for line in lines if line}


resources = report.get("Resources") or []
failures = []
accepted = []
for resource in resources:
    namespace = resource.get("Namespace", "")
    target = f"{namespace or '(cluster)'}/{resource.get('Kind', '')}/{resource.get('Name', '')}"
    for result in resource.get("Results") or []:
        for finding in result.get("Misconfigurations") or []:
            if finding.get("Status") != "FAIL":
                continue
            if finding.get("Severity") not in ("CRITICAL", "HIGH"):
                continue
            entry = (target, finding.get("ID", ""), finding.get("Severity", ""), finding.get("Title", ""))
            if entry[1] in accepted_ids(namespace):
                accepted.append(entry)
            else:
                failures.append(entry)

print(f"Scanned {len(resources)} resources.")
for target, check, severity, title in sorted(set(accepted)):
    print(f"  ACCEPTED  {severity:<8} {check:<9} {target}: {title}")
for target, check, severity, title in sorted(set(failures)):
    print(f"  FAILED    {severity:<8} {check:<9} {target}: {title}")

if not resources:
    sys.exit("trivy returned an empty report: nothing was scanned.")
if failures:
    sys.exit(f"{len(set(failures))} CRITICAL/HIGH misconfiguration(s) found.")
PYTHON

log_pass "trivy k8s runtime audit completed successfully."
