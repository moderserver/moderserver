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

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
require_tool docker
require_tool python3

GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || echo '')}"
CACHE_DIR="/tmp/moderserver-renovate-cache"
mkdir -p "${CACHE_DIR}"
chmod 777 "${CACHE_DIR}"

log_info "Running Renovate locally in dry-run mode to check for available updates in core..."

docker run --rm \
  -v "${CORE_ROOT}:/usr/src/app" \
  -v "${CACHE_DIR}:/tmp/renovate/cache" \
  -w /usr/src/app \
  -e RENOVATE_PLATFORM=local \
  -e RENOVATE_DRY_RUN=lookup \
  -e GITHUB_COM_TOKEN="${GITHUB_TOKEN}" \
  -e LOG_LEVEL=debug \
  "${RENOVATE_IMAGE}" 2>&1 | python3 -c '
import sys, json, re

capturing = False
captured = False
json_lines = []

for line in sys.stdin:
    if not captured and "packageFiles with updates" in line:
        capturing = True
        json_lines = ["{"]
        continue
    if capturing:
        if line.startswith("DEBUG:") or line.startswith("INFO:") or line.startswith("WARN:"):
            capturing = False
            captured = True
        else:
            json_lines.append(line)

raw_json = "".join(json_lines).strip()
m = re.search(r"\"config\":\s*(\{.*\})", raw_json, re.DOTALL)

if m:
    data = json.loads(m.group(1))
    header = "{:<32} {:<28} {:<15} {:<25}".format("FILE", "DEPENDENCY", "CURRENT", "STATUS / LATEST")
    print("\n" + header)
    print("=" * 100)
    seen = set()
    up_to_date = 0
    updates_needed = 0

    for mgr, files in data.items():
        for f in files:
            fname = f.get("packageFile", "")
            for dep in f.get("deps", []):
                name = dep.get("depName") or dep.get("packageName") or ""
                cur = dep.get("currentValue") or ""
                key = (fname, name, cur)
                if not name or not cur or key in seen:
                    continue
                seen.add(key)
                updates = dep.get("updates", [])
                if updates:
                    updates_needed += 1
                    new_val = updates[0].get("newValue") or updates[0].get("newVersion") or ""
                    u_type = updates[0].get("updateType") or ""
                    status = f"-> {new_val} ({u_type})"
                else:
                    up_to_date += 1
                    status = "UP TO DATE"
                print("{:<32} {:<28} {:<15} {:<25}".format(fname, name, cur, status))

    print("=" * 100)
    print(f"Summary: {up_to_date} up-to-date, {updates_needed} updates available.\n")
'
