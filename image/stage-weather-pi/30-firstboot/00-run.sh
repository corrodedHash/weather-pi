#!/bin/bash -e

install -D -m 0755 files/usr/lib/weather-pi/firstboot \
	"${ROOTFS_DIR}/usr/lib/weather-pi/firstboot"
install -D -m 0644 files/etc/systemd/system/weather-pi-firstboot.service \
	"${ROOTFS_DIR}/etc/systemd/system/weather-pi-firstboot.service"
