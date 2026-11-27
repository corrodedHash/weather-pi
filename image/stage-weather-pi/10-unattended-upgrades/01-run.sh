#!/bin/bash -e

install -D -m 0644 files/etc/apt/apt.conf.d/20auto-upgrades \
	"${ROOTFS_DIR}/etc/apt/apt.conf.d/20auto-upgrades"
install -D -m 0644 files/etc/apt/apt.conf.d/51weather-pi-unattended \
	"${ROOTFS_DIR}/etc/apt/apt.conf.d/51weather-pi-unattended"
