#!/bin/bash -e

dpkg-query -W -f='${Status}\n' unattended-upgrades |
	grep -qx 'install ok installed'

apt-config dump | grep -qx 'APT::Periodic::Update-Package-Lists "1";'
apt-config dump | grep -qx 'APT::Periodic::Unattended-Upgrade "1";'
apt-config dump | grep -qx 'APT::Keep-Downloaded-Packages "true";'

# The project fragment must extend, not replace, the distribution list. Snapshot
# the list without the fragment and assert every entry survives it; this works
# for Debian and Raspberry Pi OS origins alike.
fragment=/etc/apt/apt.conf.d/51weather-pi-unattended
stash=/tmp/51weather-pi-unattended
mv "$fragment" "$stash"
before="$(apt-config dump Unattended-Upgrade::Origins-Pattern)"
mv "$stash" "$fragment"
after="$(apt-config dump Unattended-Upgrade::Origins-Pattern)"

while IFS= read -r line; do
	[[ -z "$line" ]] && continue
	grep -Fqx "$line" <<<"$after" || {
		echo "image stage: project origin replaced distribution entry: $line" >&2
		exit 1
	}
done <<<"$before"

grep -Fq 'origin=weather-pi,archive=trixie' <<<"$after"

systemctl enable apt-daily-upgrade.timer >/dev/null
systemctl is-enabled apt-daily-upgrade.timer | grep -qx enabled
