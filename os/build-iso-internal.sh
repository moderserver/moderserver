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

set -eu

apk add --no-cache xorriso mtools curl ca-certificates

CACHE_DIR="/output/.cache"
mkdir -p "${CACHE_DIR}"

ALPINE_BRANCH="${ALPINE_ISO_VERSION%.*}"
BASE_ISO="${CACHE_DIR}/alpine-virt-${ALPINE_ISO_VERSION}.iso"
if [ ! -f "${BASE_ISO}" ]; then
  echo "--> Fetching Alpine virt base image (${ALPINE_ISO_VERSION})..."
  curl -sL "https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_BRANCH}/releases/x86_64/alpine-virt-${ALPINE_ISO_VERSION}-x86_64.iso" -o "${BASE_ISO}"
fi

K3S_CACHE="${CACHE_DIR}/k3s"
if [ ! -f "${K3S_CACHE}" ]; then
  echo "--> Caching pinned K3s binary (${K3S_VERSION})..."
  curl -sfL "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s" -o "${K3S_CACHE}"
  chmod 755 "${K3S_CACHE}"
fi

echo "--> Extracting base ISO contents..."
WORK_DIR=$(mktemp -d)
chmod 755 "${WORK_DIR}"
mkdir -p "${WORK_DIR}/iso-extract" "${WORK_DIR}/ovl/etc/runlevels/default"

xorriso -osirrox on -indev "${BASE_ISO}" -extract / "${WORK_DIR}/iso-extract" >/dev/null 2>&1
chmod -R u+w "${WORK_DIR}/iso-extract"

echo "--> Pre-baking host runtime packages into bootstrap..."
mkdir -p "${WORK_DIR}/iso-extract/root/bootstrap/apks"
apk fetch --no-cache -R -o "${WORK_DIR}/iso-extract/root/bootstrap/apks" \
  curl ca-certificates iptables ebtables ip6tables cgroup-tools wireguard-tools chrony acpid zram-init >/dev/null 2>&1 || true

echo "--> Injecting ModerServer OS unattended answerfile and bootstrap manifests..."
mkdir -p "${WORK_DIR}/iso-extract/etc" "${WORK_DIR}/iso-extract/root/bootstrap" "${WORK_DIR}/iso-extract/root/os/sysctl.d"
cp "${CORE_ROOT}/os/answers.conf" "${WORK_DIR}/iso-extract/etc/answers.conf"
cp -r "${CORE_ROOT}/bootstrap"/* "${WORK_DIR}/iso-extract/root/bootstrap/"
cp -r "${CORE_ROOT}/os/sysctl.d"/* "${WORK_DIR}/iso-extract/root/os/sysctl.d/"
cp "${K3S_CACHE}" "${WORK_DIR}/iso-extract/root/bootstrap/k3s"

echo "--> Packaging ModerServer automated startup overlay..."
cp -r "${CORE_ROOT}/os/overlay"/* "${WORK_DIR}/ovl/"
ln -s /etc/init.d/local "${WORK_DIR}/ovl/etc/runlevels/default/local"
(cd "${WORK_DIR}/ovl" && tar -czf "${WORK_DIR}/iso-extract/localhost.apkovl.tar.gz" .)

# Configure syslinux timeout to 1 and route console to serial
sed -i "s/timeout .*/timeout 1/" "${WORK_DIR}/iso-extract/boot/syslinux/syslinux.cfg" || true
sed -i "s/prompt .*/prompt 0/I" "${WORK_DIR}/iso-extract/boot/syslinux/syslinux.cfg" || true
sed -i "s#APPEND .*#APPEND modules=loop,squashfs,sd-mod,usb-storage console=ttyS0,115200 quiet#" "${WORK_DIR}/iso-extract/boot/syslinux/syslinux.cfg" || true
echo "SERIAL 0 115200" >> "${WORK_DIR}/iso-extract/boot/syslinux/syslinux.cfg"

echo "--> Generating bootable ModerServer appliance ISO..."
xorriso -as mkisofs \
  -r -V "MODERSERVER" \
  -o "${IMAGE_OUT}" \
  -b boot/syslinux/isolinux.bin \
  -c boot/syslinux/boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table \
  "${WORK_DIR}/iso-extract" >/dev/null 2>&1

rm -rf "${WORK_DIR}"
echo "==> [PASS] ModerServer ISO created successfully."
