#!/bin/bash -e

export DEBIAN_FRONTEND=noninteractive

# apt-get update proves the signed-by keyring and the repository metadata
# agree. Error-Mode=any makes a failed index fatal even when an older list is
# left in the stage; a missing key, bad signature, or expired Valid-Until then
# aborts the image build instead of producing an image with an unverified
# payload.
apt-get -o APT::Update::Error-Mode=any update

apt-config dump | grep -qx 'Acquire::Check-Valid-Until "true";'
apt-config dump | grep -qx 'APT::Keep-Downloaded-Packages "true";'

grep -Rqs '^Origin: weather-pi$' /var/lib/apt/lists/
