#!/bin/bash -e

# Install the update-configuration verifier. The script is read-only and is
# also invoked from 02-run-chroot.sh with --no-dry-run, so the image build
# checks the static configuration without depending on a live candidate.
install -D -m 0755 files/usr/lib/weather-pi/check-update-config.sh \
	"${ROOTFS_DIR}/usr/lib/weather-pi/check-update-config.sh"
