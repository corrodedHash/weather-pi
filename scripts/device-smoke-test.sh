#!/usr/bin/env bash
# On-device smoke test for a freshly provisioned weather-pi image.
#
# Run as root on the device:
#
#   sudo scripts/device-smoke-test.sh
#
# The script checks service state, network reachability, SPI, the application
# version, the optional tunnel, and an unattended-upgrades dry run. It exits
# nonzero if any check fails. --root and WEATHER_PI_SMOKE_ALLOW_NONROOT exist
# only for the test harness in scripts/test-device-smoke-test.sh.
set -uo pipefail

root="${WEATHER_PI_ROOT:-/}"
network_target="${SMOKE_TEST_NETWORK_TARGET:-}"
allow_nonroot="${WEATHER_PI_SMOKE_ALLOW_NONROOT:-0}"

usage() {
    cat <<'EOF'
Usage: device-smoke-test.sh [--root DIR] [--network-target HOST] [--allow-nonroot]

Environment:
  SMOKE_TEST_NETWORK_TARGET  Host to ping instead of the default gateway
  WEATHER_PI_ROOT            Filesystem prefix for tests (default: /)
  WEATHER_PI_SMOKE_ALLOW_NONROOT
                             Permit a non-root test run (harness only)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            [[ $# -ge 2 ]] || {
                usage >&2
                exit 2
            }
            root="$2"
            shift 2
            ;;
        --network-target)
            [[ $# -ge 2 ]] || {
                usage >&2
                exit 2
            }
            network_target="$2"
            shift 2
            ;;
        --allow-nonroot)
            allow_nonroot=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ "$root" != "/" ]]; then
    root="${root%/}"
fi

prefix() {
    if [[ "$root" == "/" ]]; then
        printf '%s' "$1"
    else
        printf '%s%s' "$root" "$1"
    fi
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/weather-pi-smoke.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

failures=0
checks=0

pass() {
    checks=$((checks + 1))
    printf 'PASS: %s\n' "$1"
}

fail() {
    checks=$((checks + 1))
    failures=$((failures + 1))
    printf 'FAIL: %s\n' "$1" >&2
}

check_command() {
    local description="$1"
    shift
    if "$@" >"$tmp/output" 2>&1; then
        pass "$description"
    else
        fail "$description"
        sed 's/^/      /' "$tmp/output" >&2
    fi
}

if [[ "$(id -u)" -ne 0 && "$allow_nonroot" != "1" ]]; then
    echo "device-smoke-test.sh: run as root (or use --allow-nonroot in the test harness)" >&2
    exit 2
fi

echo "==> weather-pi service"
if systemctl is-active --quiet weather-pi.service; then
    pass "weather-pi.service is active"
else
    fail "weather-pi.service is not active"
fi

echo "==> network"
if ip route show default 2>/dev/null | grep -q '^default'; then
    pass "a default route is present"
    if [[ -z "$network_target" ]]; then
        network_target="$(ip route show default 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "via") { print $(i + 1); exit } }')"
    fi
    if [[ -n "$network_target" ]]; then
        check_command "network reaches $network_target" ping -c 1 -W 5 "$network_target"
    else
        fail "could not determine a network target to ping"
    fi
else
    fail "no default route is present"
fi

echo "==> SPI"
# The e-ink panel has no framebuffer, so a present spidev plus an active
# service is the practical proxy for display initialisation.
spidev="$(find "$(prefix /dev)" -maxdepth 1 -name 'spidev*' -print -quit 2>/dev/null || true)"
if [[ -n "$spidev" ]]; then
    pass "SPI device present: $spidev"
else
    fail "no /dev/spidev* device is present (is dtparam=spi=on active?)"
fi

echo "==> application"
binary="$(prefix /usr/bin/weather-pi)"
if [[ -x "$binary" ]]; then
    if version_output="$("$binary" --version 2>&1)"; then
        if grep -q '^weather-pi ' <<<"$version_output"; then
            pass "$version_output"
        else
            fail "unexpected weather-pi --version output: $version_output"
        fi
    else
        fail "weather-pi --version exited nonzero: $version_output"
    fi
else
    fail "$binary is missing or not executable"
fi

echo "==> tunnel"
tunnel_env="$(prefix /etc/weather-pi/tunnel.env)"
tunnel_toml="$(prefix /etc/weather-pi/tunnel.toml)"
if [[ -f "$tunnel_env" || -f "$tunnel_toml" ]]; then
    for path in \
        "$(prefix /etc/weather-pi/tunnel.env)" \
        "$(prefix /etc/weather-pi/tunnel_key)" \
        "$(prefix /etc/weather-pi/known_hosts)"; do
        if [[ -e "$path" ]]; then
            pass "tunnel file present: $path"
        else
            fail "tunnel file missing: $path"
        fi
    done
    if systemctl is-active --quiet weather-pi-tunnel.service; then
        pass "weather-pi-tunnel.service is active"
    else
        fail "weather-pi-tunnel.service is not active although a tunnel is configured"
    fi
else
    echo "SKIP: no tunnel configuration"
fi

echo "==> unattended upgrades"
if ! command -v unattended-upgrade >/dev/null 2>&1; then
    fail "unattended-upgrade is not installed"
elif command -v timeout >/dev/null 2>&1; then
    check_command "unattended-upgrade dry run succeeds" \
        timeout 300 unattended-upgrade --dry-run -d
else
    check_command "unattended-upgrade dry run succeeds" \
        unattended-upgrade --dry-run -d
fi

echo
if ((failures > 0)); then
    echo "$failures of $checks checks failed" >&2
    exit 1
fi
echo "all $checks checks passed"
