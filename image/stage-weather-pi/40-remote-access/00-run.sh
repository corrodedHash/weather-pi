#!/bin/bash -e

install -D -m 0644 files/etc/ssh/sshd_config.d/10-weather-pi.conf \
	"${ROOTFS_DIR}/etc/ssh/sshd_config.d/10-weather-pi.conf"
