#!/usr/bin/env bash
# Build and verify a weather-pi Debian package without Docker or a device.
#
#   scripts/test-package.sh
#       Build the host (x86_64-unknown-linux-gnu) package and keyring package
#       with a throwaway archive keyring, then inspect them.
#
#   scripts/test-package.sh --deb DIR --arch ARCH --version VERSION
#       Inspect packages that already exist in DIR, for example the artifacts
#       uploaded by a CI matrix job. A cross-compiled binary is not executed.
#
# Required tools are reported as SKIP instead of silently passing. The script
# only writes to a temporary directory and to the normal cargo target tree.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

usage() {
    cat <<'EOF'
Usage:
  scripts/test-package.sh
  scripts/test-package.sh --deb DIR --arch ARCH --version VERSION

Options:
  --deb DIR        Inspect an existing package directory instead of building
  --arch ARCH      Package architecture to inspect (amd64, armhf or arm64)
  --version VER    Debian package version to inspect
  -h, --help       Show this help
EOF
}

die() {
    echo "test-package.sh: $*" >&2
    exit 1
}

skip() {
    echo "SKIP: $*" >&2
    exit 0
}

need() {
    command -v "$1" >/dev/null 2>&1 || skip "required tool '$1' is not installed"
}

assert_eq() {
    local expected="$1" actual="$2" what="$3"
    [[ "$actual" == "$expected" ]] ||
        die "$what: expected '$expected', got '$actual'"
}

assert_member() {
    local deb="$1" path="$2" mode="$3" line prefix
    case "$mode" in
        755) prefix="-rwxr-xr-x" ;;
        644) prefix="-rw-r--r--" ;;
        *) die "unsupported expected mode '$mode' for ./$path" ;;
    esac
    line="$(dpkg-deb -c "$deb" | awk -v p="./$path" '$NF == p { print; found = 1 } END { if (!found) exit 1 }')" ||
        die "$deb does not contain ./$path"
    [[ "$line" == "$prefix "* ]] || die "./$path has unexpected mode: $line"
}

mode="build"
deb_dir=""
arch=""
version=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --deb)
            [[ $# -ge 2 ]] || die "--deb requires a directory"
            mode="inspect"
            deb_dir="$2"
            shift 2
            ;;
        --arch)
            [[ $# -ge 2 ]] || die "--arch requires a value"
            arch="$2"
            shift 2
            ;;
        --version)
            [[ $# -ge 2 ]] || die "--version requires a value"
            version="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

need dpkg-deb
need md5sum
need find
need grep
need awk
need sed

work="$(mktemp -d "${TMPDIR:-/tmp}/weather-pi-package-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

if [[ "$mode" == "build" ]]; then
    need cargo
    need mise
    need rustc
    mise x -- cargo deb --version >/dev/null 2>&1 ||
        skip "cargo-deb is not available through mise"

    version="${WEATHER_PI_VERSION:-0.0.0-1}"
    arch="amd64"
    deb_dir="$work/dist"

    keyring="${WEATHER_PI_ARCHIVE_KEYRING:-}"
    if [[ -z "$keyring" && -s packaging/keyring/weather-pi-archive.gpg ]]; then
        keyring="packaging/keyring/weather-pi-archive.gpg"
    fi
    if [[ -z "$keyring" ]]; then
        need gpg
        export GNUPGHOME="$work/gnupg"
        mkdir -p "$GNUPGHOME"
        chmod 700 "$GNUPGHOME"
        gpg --batch --passphrase '' --quick-generate-key \
            'weather-pi package test <test@example.invalid>' rsa2048 sign 1d \
            >/dev/null 2>&1
        keyring="$work/weather-pi-archive.gpg"
        gpg --batch --export >"$keyring"
    fi
    [[ -s "$keyring" ]] || skip "no usable archive keyring is available"

    echo "==> Building host package $version ($arch)"
    WEATHER_PI_VERSION="$version" \
        DIST_DIR="$deb_dir" \
        WEATHER_PI_ARCHIVE_KEYRING="$keyring" \
        scripts/build-packages.sh x86_64-unknown-linux-gnu
else
    [[ -n "$deb_dir" ]] || die "--deb requires a directory"
    [[ -n "$arch" ]] || die "--arch is required with --deb"
    [[ -n "$version" ]] || die "--version is required with --deb"
    [[ "$arch" =~ ^(amd64|armhf|arm64)$ ]] || die "unsupported architecture '$arch'"
    deb_dir="$(cd "$deb_dir" && pwd)" || die "package directory '$deb_dir' not found"
    keyring="${WEATHER_PI_ARCHIVE_KEYRING:-}"
fi

app_deb="$deb_dir/weather-pi_${version}_${arch}.deb"
keyring_deb="$deb_dir/weather-pi-archive-keyring_${version}_${arch}.deb"
[[ -f "$app_deb" ]] || die "missing $app_deb"
[[ -f "$keyring_deb" ]] || die "missing $keyring_deb"

echo "==> Inspecting $(basename "$app_deb")"
assert_eq "weather-pi" "$(dpkg-deb -f "$app_deb" Package)" "package name"
assert_eq "$version" "$(dpkg-deb -f "$app_deb" Version)" "package version"
assert_eq "$arch" "$(dpkg-deb -f "$app_deb" Architecture)" "package architecture"
[[ -n "$(dpkg-deb -f "$app_deb" Installed-Size)" ]] || die "Installed-Size is missing"
[[ -n "$(dpkg-deb -f "$app_deb" Maintainer)" ]] || die "Maintainer is missing"
[[ -n "$(dpkg-deb -f "$app_deb" Description)" ]] || die "Description is missing"
dpkg-deb -I "$app_deb" >/dev/null
echo "ok: control metadata"

for spec in \
    "usr/bin/weather-pi 755" \
    "etc/weather-pi/greeter.toml 644" \
    "etc/weather-pi/countdown.toml 644" \
    "usr/share/weather-pi/heart.bmp 644" \
    "usr/share/weather-pi/heart_full.bmp 644" \
    "usr/share/weather-pi/dickbutt.bmp 644" \
    "usr/lib/sysusers.d/weather-pi.conf 644" \
    "usr/lib/systemd/system/weather-pi.service 644" \
    "usr/lib/systemd/system/weather-pi-tunnel.service 644"; do
    read -r path expected_mode <<<"$spec"
    assert_member "$app_deb" "$path" "$expected_mode"
done
echo "ok: expected binary, unit, config and asset paths"

if dpkg-deb -c "$app_deb" | grep -Eq '\./(usr|etc)/(share/)?(skyscreen|.*weather-pi-updater)'; then
    die "package still contains a legacy skyscreen or updater path"
fi
echo "ok: no legacy skyscreen or updater paths"

root="$work/root"
control="$work/control"
mkdir -p "$root" "$control"
dpkg-deb -x "$app_deb" "$root"
dpkg-deb -e "$app_deb" "$control"

[[ -f "$control/conffiles" ]] || die "conffiles is missing"
for required_conffile in \
    /etc/weather-pi/greeter.toml \
    /etc/weather-pi/countdown.toml; do
    grep -Fxq "$required_conffile" "$control/conffiles" ||
        die "$required_conffile is not a conffile"
done

# The remote-access change adds tunnel.toml as a third conffile. Accept either
# layout so this test keeps passing on both sides of that merge, but never let
# an unexpected extra conffile through.
expected_conffiles=2
if [[ -f "$root/etc/weather-pi/tunnel.toml" ]]; then
    grep -Fxq '/etc/weather-pi/tunnel.toml' "$control/conffiles" ||
        die "tunnel.toml is present but is not a conffile"
    expected_conffiles=3
fi
assert_eq "$expected_conffiles" "$(wc -l <"$control/conffiles" | tr -d ' ')" "conffile count"
echo "ok: conffiles"

[[ -s "$control/md5sums" ]] || die "md5sums is missing or empty"
grep -q ' usr/bin/weather-pi$' "$control/md5sums" || die "md5sums does not cover the binary"
grep -q ' etc/weather-pi/greeter.toml$' "$control/md5sums" ||
    die "md5sums does not cover greeter.toml"
(cd "$root" && md5sum -c "$control/md5sums" >/dev/null) ||
    die "md5sums do not match the package payload"
echo "ok: md5sums"

for script in postinst prerm postrm; do
    [[ -s "$control/$script" ]] || die "maintainer script $script is missing"
    [[ -x "$control/$script" ]] || die "maintainer script $script is not executable"
    if grep -q '#DEBHELPER#' "$control/$script"; then
        die "maintainer script $script still contains #DEBHELPER#"
    fi
done
grep -q 'systemd-sysusers' "$control/postinst" || die "postinst does not create the service user"
echo "ok: maintainer scripts"

if command -v systemd-analyze >/dev/null 2>&1; then
    if [[ ! -f "$root/etc/passwd" ]]; then
        mkdir -p "$root/etc"
        printf 'root:x:0:0:root:/root:/bin/sh\nweather-pi:x:1000:1000::/:/usr/sbin/nologin\n' \
            >"$root/etc/passwd"
        printf 'root:x:0:\nweather-pi:x:1000:\nspi:x:998:\ngpio:x:997:\n' >"$root/etc/group"
    fi
    if ! output="$(systemd-analyze verify --root="$root" \
        usr/lib/systemd/system/weather-pi.service 2>&1)"; then
        if grep -Eqi 'user .*not (found|valid)|unknown user|Failed to resolve user' <<<"$output"; then
            echo "warning: systemd-analyze reported a missing user (expected in the test root):"
            printf '%s\n' "$output"
        else
            printf '%s\n' "$output" >&2
            die "systemd-analyze verify failed"
        fi
    fi
    echo "ok: systemd unit"
else
    echo "SKIP: systemd-analyze is not installed; unit file was not verified"
fi

if [[ "$mode" == "build" ]]; then
    output="$("$root/usr/bin/weather-pi" --version)"
    assert_eq "weather-pi $version (x86_64-unknown-linux-gnu)" "$output" "--version output"
    echo "ok: weather-pi --version"
else
    echo "SKIP: not executing the $arch package binary"
fi

echo "==> Inspecting $(basename "$keyring_deb")"
assert_eq "weather-pi-archive-keyring" "$(dpkg-deb -f "$keyring_deb" Package)" "keyring package name"
assert_eq "$version" "$(dpkg-deb -f "$keyring_deb" Version)" "keyring package version"
assert_eq "$arch" "$(dpkg-deb -f "$keyring_deb" Architecture)" "keyring package architecture"
assert_member "$keyring_deb" "usr/share/keyrings/weather-pi-archive.gpg" 644

keyring_root="$work/keyring-root"
keyring_control="$work/keyring-control"
mkdir -p "$keyring_root" "$keyring_control"
dpkg-deb -x "$keyring_deb" "$keyring_root"
dpkg-deb -e "$keyring_deb" "$keyring_control"
[[ -s "$keyring_control/md5sums" ]] || die "keyring md5sums is missing or empty"
(cd "$keyring_root" && md5sum -c "$keyring_control/md5sums" >/dev/null) ||
    die "keyring md5sums do not match the package payload"
if [[ -n "$keyring" ]]; then
    cmp -s "$keyring" "$keyring_root/usr/share/keyrings/weather-pi-archive.gpg" ||
        die "keyring package does not contain the supplied public keyring"
fi
echo "ok: keyring package"

echo
echo "PASS: package checks passed for weather-pi $version ($arch)"
