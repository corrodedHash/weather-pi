#!/usr/bin/env bash
# Exercise the first-boot provisioner against throwaway roots.
#
#   scripts/test-firstboot.sh
#
# The test is intentionally offline and unprivileged: it uses --no-commands and
# --root so nmcli, systemctl, and the host's real /etc are never touched.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
firstboot="$repo_root/image/stage-weather-pi/30-firstboot/files/usr/lib/weather-pi/firstboot"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "test-firstboot.sh: required tool '$1' is not installed" >&2
        exit 1
    }
}

need python3
need ssh-keygen

tmp="$(mktemp -d "${TMPDIR:-/tmp}/weather-pi-firstboot-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_file() {
    [[ -f "$1" ]] || fail "expected file $1"
}

assert_mode() {
    local actual
    actual="$(stat -c '%a' "$1")"
    [[ "$actual" == "$2" ]] || fail "$1 has mode $actual, expected $2"
}

assert_no_group_world() {
    local actual
    actual="$(stat -c '%a' "$1")"
    (( (8#$actual & 077) == 0 )) ||
        fail "$1 is accessible by group or others (mode $actual)"
}

assert_contains() {
    grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"
}

assert_not_contains() {
    if grep -Fq -- "$2" "$1"; then
        fail "$1 still contains: $2"
    fi
}

snapshot() {
    # Path, mode, mtime, and content hash for every file. The second run must
    # not change any of them, including the sentinel.
    (
        cd "$1"
        find . -type f -printf '%P\t%m\t%T@\t' -exec sha256sum {} \; | sort
    )
}

make_root() {
    local root="$1"
    mkdir -p \
        "$root/boot/firmware" \
        "$root/etc/NetworkManager/system-connections" \
        "$root/home/weather-pi" \
        "$root/var/lib"
    printf 'console=serial0,115200 root=PARTUUID=test rootwait\n' >"$root/boot/firmware/cmdline.txt"
}

# Two throwaway keypairs: one becomes the tunnel identity, one is the pinned
# host key. Both are generated locally so no fixture contains a real secret.
ssh-keygen -q -t ed25519 -N '' -C test-tunnel -f "$tmp/tunnel_key"
ssh-keygen -q -t ed25519 -N '' -C test-host -f "$tmp/host_key"
tunnel_public="$(cat "$tmp/tunnel_key.pub")"
host_public="$(cat "$tmp/host_key.pub")"

write_config() {
    local path="$1"
    {
        cat <<EOF
hostname = "unit-pi"

[wifi]
ssid = "Test Net"
password = "correct horse battery staple"
country = "DE"

[ssh]
authorized_keys = ["${tunnel_public}"]

[tunnel]
host = "vps.example.com"
port = 2222
user = "tunnel"
remote_port = 2200
host_key = "${host_public}"
private_key = """
EOF
        cat "$tmp/tunnel_key"
        cat <<'EOF'
"""
EOF
    } >"$path"
}

root="$tmp/root"
make_root "$root"
config="$root/boot/firmware/weather-pi.cfg"
write_config "$config"
mkdir -p "$root/home/weather-pi/.ssh"
printf '%s\n' "$host_public" >"$root/home/weather-pi/.ssh/authorized_keys"
chmod 600 "$root/home/weather-pi/.ssh/authorized_keys"

echo "==> first run"
python3 "$firstboot" --root "$root" --config "$config" --no-commands

assert_file "$root/etc/hostname"
[[ "$(cat "$root/etc/hostname")" == "unit-pi" ]] || fail "hostname was not applied"
assert_contains "$root/etc/hosts" "127.0.1.1	unit-pi"

keyfile="$root/etc/NetworkManager/system-connections/weather-pi-Test_Net.nmconnection"
assert_file "$keyfile"
assert_mode "$keyfile" 600
assert_contains "$keyfile" "ssid=Test Net"
assert_contains "$keyfile" "psk=correct horse battery staple"

assert_file "$root/home/weather-pi/.ssh/authorized_keys"
assert_mode "$root/home/weather-pi/.ssh" 700
assert_mode "$root/home/weather-pi/.ssh/authorized_keys" 600
assert_contains "$root/home/weather-pi/.ssh/authorized_keys" "$tunnel_public"
assert_contains "$root/home/weather-pi/.ssh/authorized_keys" "$host_public"

assert_file "$root/etc/weather-pi/tunnel.toml"
assert_file "$root/etc/weather-pi/tunnel.env"
assert_file "$root/etc/weather-pi/tunnel_key"
assert_file "$root/etc/weather-pi/tunnel_key.pub"
assert_file "$root/etc/weather-pi/known_hosts"
assert_file "$root/boot/firmware/weather-pi-tunnel.pub"
assert_mode "$root/etc/weather-pi/tunnel.env" 640
assert_mode "$root/etc/weather-pi/tunnel.toml" 644
assert_mode "$root/etc/weather-pi/tunnel_key" 600
assert_no_group_world "$root/etc/weather-pi/tunnel_key"
assert_mode "$root/etc/weather-pi/tunnel_key.pub" 644
assert_mode "$root/etc/weather-pi/known_hosts" 640
assert_mode "$root/boot/firmware/weather-pi-tunnel.pub" 644

assert_not_contains "$root/etc/weather-pi/tunnel.toml" "PRIVATE KEY"
assert_not_contains "$root/etc/weather-pi/tunnel.toml" "private_key"

expected_env="$tmp/expected.env"
cat >"$expected_env" <<'EOF'
TUNNEL_HOST=vps.example.com
TUNNEL_PORT=2222
TUNNEL_USER=tunnel
TUNNEL_REMOTE_PORT=2200
EOF
diff -u "$expected_env" "$root/etc/weather-pi/tunnel.env" ||
    fail "tunnel.env does not contain exactly the four expected variables"

assert_contains "$root/etc/weather-pi/known_hosts" "[vps.example.com]:2222 ssh-ed25519 "
[[ "$(awk '{print $1, $2}' "$root/etc/weather-pi/tunnel_key.pub")" == \
    "$(awk '{print $1, $2}' "$tmp/tunnel_key.pub")" ]] ||
    fail "tunnel_key.pub does not match the supplied private key"
cmp -s "$root/etc/weather-pi/tunnel_key" "$tmp/tunnel_key" ||
    fail "tunnel_key does not match the supplied private key"

assert_contains "$config" 'hostname = "unit-pi"'
assert_contains "$config" 'ssid = "Test Net"'
assert_contains "$config" 'country = "DE"'
assert_contains "$config" 'host = "vps.example.com"'
assert_contains "$config" 'host_key = "'
assert_not_contains "$config" "correct horse battery staple"
assert_not_contains "$config" "private_key"
assert_not_contains "$config" "OPENSSH PRIVATE KEY"
assert_contains "$root/boot/firmware/cmdline.txt" "cfg80211.ieee80211_regdom=DE"

python3 - "$config" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as handle:
    data = tomllib.load(handle)
assert "password" not in data["wifi"], data
assert "private_key" not in data["tunnel"], data
assert data["hostname"] == "unit-pi"
PY

assert_file "$root/var/lib/weather-pi/firstboot.done"

echo "==> second run must be a no-op"
before="$(snapshot "$root")"
second_output="$(python3 "$firstboot" --root "$root" --config "$config" --no-commands 2>&1)"
after="$(snapshot "$root")"
[[ "$before" == "$after" ]] || fail "the second run changed files"
grep -Fq "already completed" <<<"$second_output" ||
    fail "the second run did not report the sentinel"

echo "==> a retry after secret removal preserves the WiFi profile and fixes modes"
rm -f "$root/var/lib/weather-pi/firstboot.done"
chmod 0644 "$root/etc/weather-pi/tunnel_key"
chmod 0600 "$root/etc/weather-pi/tunnel.env"
chmod 0644 "$root/etc/weather-pi/known_hosts"
python3 "$firstboot" --root "$root" --config "$config" --no-commands \
    >"$tmp/retry.out" 2>&1
assert_contains "$keyfile" "psk=correct horse battery staple"
assert_not_contains "$keyfile" "key-mgmt=none"
assert_mode "$root/etc/weather-pi/tunnel_key" 600
assert_no_group_world "$root/etc/weather-pi/tunnel_key"
assert_mode "$root/etc/weather-pi/tunnel.env" 640
assert_mode "$root/etc/weather-pi/known_hosts" 640

echo "==> invalid tunnel port fails closed"
bad_root="$tmp/bad-port"
make_root "$bad_root"
bad_config="$bad_root/boot/firmware/weather-pi.cfg"
cat >"$bad_config" <<'EOF'
hostname = "bad-pi"

[tunnel]
host = "vps.example.com"
port = "not-a-port"
user = "tunnel"
remote_port = 2200
host_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKg5D5l8J8l8J8l8J8l8J8l8J8l8J8l8J8l8J8l8J8l8"
private_key = """
-----BEGIN OPENSSH PRIVATE KEY-----
not-a-key
-----END OPENSSH PRIVATE KEY-----
"""
EOF
if python3 "$firstboot" --root "$bad_root" --config "$bad_config" --no-commands; then
    fail "invalid tunnel port was accepted"
fi
[[ ! -e "$bad_root/var/lib/weather-pi/firstboot.done" ]] ||
    fail "invalid config wrote the sentinel"
[[ ! -e "$bad_root/etc/hostname" ]] || fail "invalid config wrote a hostname"
assert_contains "$bad_config" "not-a-port"

echo "==> malformed TOML fails closed"
bad_toml_root="$tmp/bad-toml"
make_root "$bad_toml_root"
bad_toml="$bad_toml_root/boot/firmware/weather-pi.cfg"
printf 'hostname = "unterminated\n[wifi\n' >"$bad_toml"
if python3 "$firstboot" --root "$bad_toml_root" --config "$bad_toml" --no-commands; then
    fail "malformed TOML was accepted"
fi
[[ ! -e "$bad_toml_root/var/lib/weather-pi/firstboot.done" ]] ||
    fail "malformed TOML wrote the sentinel"

echo "==> absent provisioning file is a successful no-op"
absent_root="$tmp/absent"
make_root "$absent_root"
python3 "$firstboot" --root "$absent_root" --no-commands
[[ ! -e "$absent_root/var/lib/weather-pi/firstboot.done" ]] ||
    fail "absent config wrote the sentinel"

echo "==> dry run changes nothing"
dry_root="$tmp/dry"
make_root "$dry_root"
dry_config="$dry_root/boot/firmware/weather-pi.cfg"
write_config "$dry_config"
dry_before="$(sha256sum "$dry_config")"
WEATHER_PI_ROOT="$dry_root" python3 "$firstboot" --config "$dry_config" --dry-run --no-commands
[[ "$(sha256sum "$dry_config")" == "$dry_before" ]] ||
    fail "dry run modified the provisioning file"
[[ ! -e "$dry_root/etc/hostname" ]] || fail "dry run wrote a hostname"
[[ ! -e "$dry_root/var/lib/weather-pi/firstboot.done" ]] ||
    fail "dry run wrote the sentinel"

echo "==> a tunnel without a supplied key generates an ed25519 identity"
generated_root="$tmp/generated"
make_root "$generated_root"
generated_config="$generated_root/boot/firmware/weather-pi.cfg"
cat >"$generated_config" <<EOF
hostname = "generated-pi"

[tunnel]
host = "vps.example.com"
port = 22
user = "tunnel"
remote_port = 2200
host_key = "${host_public}"
EOF
python3 "$firstboot" --root "$generated_root" --config "$generated_config"
assert_file "$generated_root/etc/weather-pi/tunnel_key"
assert_mode "$generated_root/etc/weather-pi/tunnel_key" 600
assert_no_group_world "$generated_root/etc/weather-pi/tunnel_key"
assert_file "$generated_root/etc/weather-pi/tunnel_key.pub"
assert_mode "$generated_root/etc/weather-pi/tunnel_key.pub" 644
assert_file "$generated_root/etc/weather-pi/tunnel.env"
assert_mode "$generated_root/etc/weather-pi/tunnel.env" 640
assert_file "$generated_root/etc/weather-pi/known_hosts"
assert_mode "$generated_root/etc/weather-pi/known_hosts" 640
assert_file "$generated_root/boot/firmware/weather-pi-tunnel.pub"
assert_contains "$generated_root/etc/weather-pi/known_hosts" "[vps.example.com]:22 ssh-ed25519 "
assert_contains "$generated_root/etc/weather-pi/known_hosts" "vps.example.com ssh-ed25519 "
generated_public="$(ssh-keygen -y -f "$generated_root/etc/weather-pi/tunnel_key")"
[[ "$(awk '{print $1, $2}' "$generated_root/etc/weather-pi/tunnel_key.pub")" == \
    "$(awk '{print $1, $2}' <<<"$generated_public")" ]] ||
    fail "generated tunnel public key does not match its private key"
assert_not_contains "$generated_config" "private_key"

echo "all firstboot tests passed"
