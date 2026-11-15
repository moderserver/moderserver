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

# Remasters the upstream Alpine Linux ISO into the ModerServer installer.
# Runs inside an Alpine container started by os/build-image.sh.
#
# Added to the upstream image:
#   /moderserver/bootstrap   host configuration, K3s binary, platform images and
#                            GitOps bootstrap manifests
#   /moderserver/os          kernel sysctl settings
#   /moderserver/apks        signed apk repository with everything an offline
#                            disk installation needs (kernel, bootloaders,
#                            firmware, host packages)
#   /localhost.apkovl.tar.gz live-environment overlay that starts the installer
#
# The upstream boot records are replayed unchanged, so the result boots from
# USB sticks and optical media, in BIOS and UEFI mode, like the original.

set -eu

apk add --no-cache xorriso curl ca-certificates abuild openssl >/dev/null

ARCH="x86_64"
CACHE_DIR="/output/.cache"
mkdir -p "${CACHE_DIR}"

# fetch_verified <url> <checksum-file-url> <name-in-checksum-file> <destination>
# Downloads a release artifact and checks it against the checksum file
# published next to it. Cached downloads are verified again on every build.
fetch_verified() {
  url="$1"
  sums_url="$2"
  sums_name="$3"
  dest="$4"
  expected="$(curl -sfL "${sums_url}" | awk -v f="${sums_name}" '$2 == f || $2 == "*" f {print $1}')"
  if [ -z "${expected}" ]; then
    echo "No published checksum for ${sums_name} at ${sums_url}" >&2
    exit 1
  fi
  if [ ! -f "${dest}" ] || [ "$(sha256sum "${dest}" | cut -d' ' -f1)" != "${expected}" ]; then
    echo "--> Fetching ${url}..."
    curl -sfL "${url}" -o "${dest}.tmp"
    mv "${dest}.tmp" "${dest}"
  fi
  actual="$(sha256sum "${dest}" | cut -d' ' -f1)"
  if [ "${actual}" != "${expected}" ]; then
    echo "Checksum mismatch for ${url}: expected ${expected}, got ${actual}" >&2
    rm -f "${dest}"
    exit 1
  fi
}

# The standard image carries the LTS kernel with drivers for physical hardware
# (the virt flavour only boots virtual machines).
ALPINE_BRANCH="${ALPINE_ISO_VERSION%.*}"
BASE_ISO_NAME="alpine-standard-${ALPINE_ISO_VERSION}-${ARCH}.iso"
BASE_ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_BRANCH}/releases/${ARCH}/${BASE_ISO_NAME}"
BASE_ISO="${CACHE_DIR}/${BASE_ISO_NAME}"
fetch_verified "${BASE_ISO_URL}" "${BASE_ISO_URL}.sha256" "${BASE_ISO_NAME}" "${BASE_ISO}"

K3S_RELEASE_URL="https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}"
K3S_BIN="${CACHE_DIR}/k3s-${K3S_VERSION}"
fetch_verified "${K3S_RELEASE_URL}/k3s" "${K3S_RELEASE_URL}/sha256sum-amd64.txt" "k3s" "${K3S_BIN}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT
PAYLOAD="${WORK_DIR}/moderserver"
OVERLAY="${WORK_DIR}/ovl"
mkdir -p "${PAYLOAD}/bootstrap" "${PAYLOAD}/os" "${PAYLOAD}/apks/${ARCH}" "${OVERLAY}"

echo "--> Assembling host bootstrap payload..."
cp -r "${CORE_ROOT}/bootstrap"/. "${PAYLOAD}/bootstrap/"
cp -r "${CORE_ROOT}/os/sysctl.d" "${PAYLOAD}/os/"
cp "${K3S_BIN}" "${PAYLOAD}/bootstrap/k3s"
chmod 755 "${PAYLOAD}/bootstrap/k3s"

if [ -z "$(ls -A /output/images/*.tar 2>/dev/null)" ]; then
  echo "No platform images in /output/images (run hack/build-components.sh --save-dir)" >&2
  exit 1
fi
mkdir -p "${PAYLOAD}/bootstrap/images" "${PAYLOAD}/bootstrap/manifests"
cp /output/images/*.tar "${PAYLOAD}/bootstrap/images/"
cp /output/manifests/argocd-crds.yaml /output/manifests/argocd.yaml "${PAYLOAD}/bootstrap/manifests/"

# Packages the upstream image does not ship but an offline installation needs:
# the installed kernel, both bootloaders (BIOS and UEFI) and the host packages.
echo "--> Bundling offline package repository..."
HOST_PACKAGES="$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "${CORE_ROOT}/bootstrap/host-packages" | tr '\n' ' ')"
INSTALLER_PACKAGES="alpine-base linux-lts linux-firmware-none mkinitfs syslinux grub-efi efibootmgr dosfstools e2fsprogs sfdisk"
# shellcheck disable=SC2086
apk fetch --quiet --recursive --output "${PAYLOAD}/apks/${ARCH}" ${INSTALLER_PACKAGES} ${HOST_PACKAGES}

# The index is signed with a key generated for this build only. Its public half
# is trusted by the live installer environment and removed from the installed
# system; the private half never leaves this container.
KEY_NAME="moderserver-installer-$(date +%Y%m%d%H%M%S)"
openssl genrsa -out "${WORK_DIR}/${KEY_NAME}.rsa" 2048 2>/dev/null
openssl rsa -in "${WORK_DIR}/${KEY_NAME}.rsa" -pubout -out "${WORK_DIR}/${KEY_NAME}.rsa.pub" 2>/dev/null
(
  cd "${PAYLOAD}/apks/${ARCH}"
  apk index --quiet --rewrite-arch "${ARCH}" -o APKINDEX.tar.gz ./*.apk
  abuild-sign -q -k "${WORK_DIR}/${KEY_NAME}.rsa" -p "${KEY_NAME}.rsa.pub" APKINDEX.tar.gz
)

echo "--> Packaging installer overlay..."
cp -r "${CORE_ROOT}/os/overlay"/. "${OVERLAY}/"
mkdir -p "${OVERLAY}/etc/apk/keys" "${OVERLAY}/etc/runlevels/default"
cp "${WORK_DIR}/${KEY_NAME}.rsa.pub" "${OVERLAY}/etc/apk/keys/"
ln -s /etc/init.d/local "${OVERLAY}/etc/runlevels/default/local"
# Ask the Alpine init to enable its standard live services (device manager,
# hardware drivers, kernel modules) even though an overlay is present
touch "${OVERLAY}/etc/.default_boot_services"
(cd "${OVERLAY}" && tar -czf "${WORK_DIR}/localhost.apkovl.tar.gz" .)

# Boot menu: no prompt, kernel messages on the first serial port when there is
# one, screen as the main console
echo "--> Adjusting boot configuration..."
xorriso -osirrox on -indev "${BASE_ISO}" \
  -extract /boot/syslinux/syslinux.cfg "${WORK_DIR}/syslinux.cfg" \
  -extract /boot/grub/grub.cfg "${WORK_DIR}/grub.cfg" >/dev/null 2>&1
chmod u+w "${WORK_DIR}/syslinux.cfg" "${WORK_DIR}/grub.cfg"
CONSOLE_OPTS="console=ttyS0,115200 console=tty0"
sed -i \
  -e 's/^TIMEOUT .*/TIMEOUT 10/' \
  -e 's/^PROMPT .*/PROMPT 0/' \
  -e "s#^\(APPEND .*\)\$#\1 ${CONSOLE_OPTS}#" \
  "${WORK_DIR}/syslinux.cfg"
sed -i \
  -e 's/^set timeout=.*/set timeout=1/' \
  -e "s#^\(linux[[:space:]].*\)\$#\1 ${CONSOLE_OPTS}#" \
  "${WORK_DIR}/grub.cfg"
grep -q "${CONSOLE_OPTS}" "${WORK_DIR}/syslinux.cfg"
grep -q "${CONSOLE_OPTS}" "${WORK_DIR}/grub.cfg"

echo "--> Generating bootable ModerServer installer ISO..."
rm -f "${IMAGE_OUT}"
xorriso \
  -indev "${BASE_ISO}" \
  -outdev "${IMAGE_OUT}" \
  -boot_image any replay \
  -map "${PAYLOAD}" /moderserver \
  -map "${WORK_DIR}/localhost.apkovl.tar.gz" /localhost.apkovl.tar.gz \
  -map "${WORK_DIR}/syslinux.cfg" /boot/syslinux/syslinux.cfg \
  -map "${WORK_DIR}/grub.cfg" /boot/grub/grub.cfg \
  >/dev/null 2>"${WORK_DIR}/xorriso.log" || {
    cat "${WORK_DIR}/xorriso.log" >&2
    exit 1
  }

echo "==> [PASS] ModerServer installer ISO created successfully."
