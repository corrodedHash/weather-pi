#!/bin/bash -e

# Scan the places a first-boot or operator file could hide a credential. The
# scanner is installed by this stage's 00-run.sh; build.sh copies the host
# implementation into the stage before the Docker build.
/usr/lib/weather-pi/check-image-secrets \
	/boot/firmware \
	/etc/weather-pi \
	/home/weather-pi \
	/root
