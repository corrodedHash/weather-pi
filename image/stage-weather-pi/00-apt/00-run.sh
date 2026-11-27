#!/bin/bash -e

install -D -m 0644 files/etc/apt/sources.list.d/weather-pi.list \
	"${ROOTFS_DIR}/etc/apt/sources.list.d/weather-pi.list"
install -D -m 0644 files/etc/apt/preferences.d/weather-pi.pref \
	"${ROOTFS_DIR}/etc/apt/preferences.d/weather-pi.pref"
install -D -m 0644 files/etc/apt/apt.conf.d/90weather-pi \
	"${ROOTFS_DIR}/etc/apt/apt.conf.d/90weather-pi"
install -D -m 0644 files/usr/share/keyrings/weather-pi-archive.gpg \
	"${ROOTFS_DIR}/usr/share/keyrings/weather-pi-archive.gpg"
