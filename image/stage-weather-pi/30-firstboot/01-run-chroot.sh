#!/bin/bash -e

systemctl enable weather-pi-firstboot.service >/dev/null
systemctl is-enabled weather-pi-firstboot.service | grep -qx enabled
