#!/usr/bin/env bash
# Verify the image secret scanner accepts a clean stage and rejects planted
# credentials. No root or Docker is required.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$repo_root/scripts/check-image-secrets.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/weather-pi-secret-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

expect_pass() {
    local directory="$1"
    if ! "$checker" "$directory" >/dev/null 2>&1; then
        "$checker" "$directory" || true
        fail "scanner rejected clean directory $directory"
    fi
}

expect_fail() {
    local directory="$1" description="$2"
    if "$checker" "$directory" >/dev/null 2>&1; then
        fail "scanner accepted $description"
    fi
}

echo "==> clean fixture passes"
clean="$tmp/clean"
mkdir -p "$clean/etc/weather-pi" "$clean/boot/firmware"
cat >"$clean/etc/weather-pi/greeter.toml" <<'EOF'
watched_ips = ["192.0.2.10"]
password = ""
passphrase = ""
EOF
printf 'dtparam=spi=on\n' >"$clean/boot/firmware/config.txt"
expect_pass "$clean"

echo "==> real stage passes"
expect_pass "$repo_root/image/stage-weather-pi"

echo "==> generated Python bytecode is ignored"
pycache="$tmp/pycache"
mkdir -p "$pycache/__pycache__"
printf 'cache for -----BEGIN OPENSSH PRIVATE KEY-----\n' >"$pycache/__pycache__/firstboot.pyc"
expect_pass "$pycache"

echo "==> armored private key fails"
armored="$tmp/armored"
mkdir -p "$armored"
cat >"$armored/leak.txt" <<'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
-----END OPENSSH PRIVATE KEY-----
EOF
expect_fail "$armored" "an OpenSSH private key"

echo "==> PGP private key block fails"
pgp="$tmp/pgp"
mkdir -p "$pgp"
cat >"$pgp/leak.asc" <<'EOF'
-----BEGIN PGP PRIVATE KEY BLOCK-----
Version: test
-----END PGP PRIVATE KEY BLOCK-----
EOF
expect_fail "$pgp" "an OpenPGP private key block"

echo "==> non-empty password assignment fails"
password="$tmp/password"
mkdir -p "$password"
printf 'wifi_password = "hunter2"\n' >"$password/settings.conf"
expect_fail "$password" "a non-empty password assignment"

echo "==> non-empty passphrase assignment fails"
passphrase="$tmp/passphrase"
mkdir -p "$passphrase"
printf 'passphrase: correct horse\n' >"$passphrase/settings.yml"
expect_fail "$passphrase" "a non-empty passphrase assignment"

echo "==> binary OpenPGP secret packet fails"
packet="$tmp/packet"
mkdir -p "$packet"
printf '\305\000\000\000' >"$packet/archive-private.gpg"
expect_fail "$packet" "a binary secret-key packet"

echo "==> missing directory fails"
if "$checker" "$tmp/does-not-exist" >/dev/null 2>&1; then
    fail "scanner accepted a missing directory"
fi

echo "all image secret tests passed"
