#!/usr/bin/env bash
# Install the secret scanner into the image so the chroot stage can inspect
# the root filesystem with the same implementation used before the build.
set -euo pipefail

install -D -m 0755 files/usr/lib/weather-pi/check-image-secrets \
	"${ROOTFS_DIR}/usr/lib/weather-pi/check-image-secrets"
