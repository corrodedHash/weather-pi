#!/bin/bash -e

export DEBIAN_FRONTEND=noninteractive

version_file=/etc/weather-pi/image-version
[[ -r "$version_file" ]] || {
	echo "20-packages: missing $version_file" >&2
	exit 1
}
# shellcheck disable=SC1090
source "$version_file"

[[ -n "${IMAGE_VERSION:-}" ]] || {
	echo "20-packages: IMAGE_VERSION is empty in $version_file" >&2
	exit 1
}
[[ -n "${PIGEN_REV:-}" ]] || {
	echo "20-packages: PIGEN_REV is empty in $version_file" >&2
	exit 1
}

die() {
	echo "20-packages: $*" >&2
	exit 1
}

apt-get update
apt-get install -y --no-install-recommends \
	"weather-pi=${IMAGE_VERSION}" \
	"weather-pi-archive-keyring=${IMAGE_VERSION}"

installed_version() {
	dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
}

[[ "$(installed_version weather-pi)" == "$IMAGE_VERSION" ]] ||
	die "weather-pi version is '$(installed_version weather-pi)', expected '$IMAGE_VERSION'"
[[ "$(installed_version weather-pi-archive-keyring)" == "$IMAGE_VERSION" ]] ||
	die "weather-pi-archive-keyring version is '$(installed_version weather-pi-archive-keyring)', expected '$IMAGE_VERSION'"

# Verify the project packages' payload against their md5sums. A full dpkg -V
# also reports files that pi-gen deliberately changes in base packages (the
# boot configuration, for example), so limit the assertion to the payload
# whose integrity this stage controls.
if ! dpkg -V weather-pi weather-pi-archive-keyring; then
	die "dpkg -V reported differences in the project packages"
fi
[[ -z "$(dpkg -V weather-pi weather-pi-archive-keyring)" ]] ||
	die "dpkg -V reported differences in the project packages"

for path in \
	/usr/bin/weather-pi \
	/etc/weather-pi/greeter.toml \
	/usr/share/keyrings/weather-pi-archive.gpg \
	/usr/lib/systemd/system/weather-pi.service; do
	[[ -e "$path" ]] || die "required path is missing: $path"
done

# The package's generated maintainer scripts may skip enabling units in an
# offline chroot. Do it explicitly, then assert the enablement that a booted
# device relies on.
systemctl enable weather-pi.service >/dev/null 2>&1 || true
wants=/etc/systemd/system/multi-user.target.wants/weather-pi.service
[[ -L "$wants" ]] || die "weather-pi.service is not enabled ($wants missing)"
[[ -e "$wants" ]] || die "weather-pi.service enablement symlink is dangling"

groups="$(id -nG weather-pi)"
for group in spi gpio; do
	grep -qw "$group" <<<"$groups" || die "weather-pi is not a member of group '$group'"
done

version_output="$(weather-pi --version)" || die "weather-pi --version failed"
grep -q '^weather-pi ' <<<"$version_output" || die "unexpected weather-pi --version output: $version_output"

# build-info is a stable, documented key=value file. Values are written raw
# (REPO_DATE contains spaces); consumers split on the first '='.
# shellcheck disable=SC1091 # provided by the base image
. /etc/os-release
base_release="${VERSION_CODENAME:-trixie}"
[[ "$base_release" == "trixie" ]] ||
	die "base release is '$base_release', expected 'trixie'"

repo_date=""
for release in /var/lib/apt/lists/*InRelease; do
	[[ -f "$release" ]] || continue
	repo_date="$(sed -n 's/^Date:[[:space:]]*//p' "$release" | head -n1)"
	[[ -n "$repo_date" ]] && break
done
[[ -n "$repo_date" ]] ||
	repo_date="$(date -u '+%a, %d %b %Y %H:%M:%S UTC')"

weather_pi_version="$(installed_version weather-pi)"
keyring_version="$(installed_version weather-pi-archive-keyring)"

build_info=/etc/weather-pi/build-info
build_info_tmp="${build_info}.tmp"
mkdir -p /etc/weather-pi
cat >"$build_info_tmp" <<EOF
# Installed image metadata. Stable key=value format; split on the first '='.
BASE_RELEASE=${base_release}
PIGEN_REV=${PIGEN_REV}
REPO_DATE=${repo_date}
IMAGE_VERSION=${IMAGE_VERSION}
WEATHER_PI_VERSION=${weather_pi_version}
WEATHER_PI_ARCHIVE_KEYRING_VERSION=${keyring_version}
EOF
chmod 0644 "$build_info_tmp"
mv "$build_info_tmp" "$build_info"

grep -qx "BASE_RELEASE=${base_release}" "$build_info"
grep -qx "PIGEN_REV=${PIGEN_REV}" "$build_info"
grep -q '^REPO_DATE=' "$build_info"
grep -qx "IMAGE_VERSION=${IMAGE_VERSION}" "$build_info"
grep -qx "WEATHER_PI_VERSION=${weather_pi_version}" "$build_info"
grep -qx "WEATHER_PI_ARCHIVE_KEYRING_VERSION=${keyring_version}" "$build_info"
