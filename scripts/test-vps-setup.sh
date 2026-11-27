#!/usr/bin/env bash
# Exercise scripts/vps-setup.sh without changing the host.
#
# The real script needs root to create the forwarding account and reload sshd.
# These tests cover argument validation, the fail-closed public-key checks, and
# the exact authorized_keys line printed by --dry-run.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/vps-setup.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/weather-pi-vps-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail() {
    echo "test-vps-setup.sh: FAIL: $*" >&2
    exit 1
}

dummy_key="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB testdevice"
if command -v ssh-keygen >/dev/null 2>&1; then
    ssh-keygen -q -t ed25519 -N '' -C testdevice -f "$tmp/device_key"
    cp "$tmp/device_key.pub" "$tmp/device.pub"
else
    printf '%s\n' "$dummy_key" >"$tmp/device.pub"
fi

port=2207
user="weatherpi-test-$$"
sshd_dir="$tmp/sshd_config.d"

output="$(
    bash "$script" --dry-run --port "$port" --serial testdev --user "$user" \
        --pubkey-file "$tmp/device.pub" --sshd-config "$sshd_dir" 2>&1
)" || fail "dry run exited non-zero: $output"

grep -Fq "restrict,port-forwarding,permitlisten=\"127.0.0.1:$port\"" <<<"$output" ||
    fail "authorized_keys line lacks the forwarding restriction"
grep -Fq "weatherpi-testdev" <<<"$output" || fail "authorized_keys line lacks the serial comment"
grep -Fq "$sshd_dir/00-weatherpi-tunnel.conf" <<<"$output" ||
    fail "dry run did not report the sshd drop-in path"
grep -Fq "GatewayPorts no" <<<"$output" || fail "dry run did not report GatewayPorts no"
[[ ! -e "$sshd_dir" ]] || fail "dry run created the sshd drop-in directory"
[[ ! -e "/home/$user" ]] || fail "dry run created the account home"

second="$(
    bash "$script" --dry-run --port "$port" --serial testdev --user "$user" \
        --pubkey-file "$tmp/device.pub" --sshd-config "$sshd_dir" 2>&1
)" || fail "second dry run exited non-zero"
[[ "$(grep -Fc "authorized_keys += " <<<"$second")" -eq 1 ]] ||
    fail "second dry run did not print exactly one enrollment line"

if bash "$script" --dry-run --port 70000 --serial testdev --user "$user" \
    --pubkey-file "$tmp/device.pub" --sshd-config "$sshd_dir" >"$tmp/out" 2>&1; then
    fail "out-of-range port was accepted"
fi
grep -Fq "between 1 and 65535" "$tmp/out" || fail "out-of-range port error is not clear"

if bash "$script" --dry-run --port "$port" --serial testdev --user "$user" \
    --pubkey-file "$tmp/missing.pub" --sshd-config "$sshd_dir" >"$tmp/out" 2>&1; then
    fail "missing public key file was accepted"
fi
grep -Fq "not readable" "$tmp/out" || fail "missing public key error is not clear"

printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' >"$tmp/private"
if bash "$script" --dry-run --port "$port" --serial testdev --user "$user" \
    --pubkey-file "$tmp/private" --sshd-config "$sshd_dir" >"$tmp/out" 2>&1; then
    fail "private key material was accepted as a public key"
fi
grep -Fq "private key" "$tmp/out" || fail "private key rejection is not clear"

echo "test-vps-setup.sh: all dry-run checks passed"
