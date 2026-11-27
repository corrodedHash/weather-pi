#!/usr/bin/env bash
# Exercise device-smoke-test.sh with command stubs and a temporary filesystem
# prefix. This is not a hardware test; it only proves the smoke test fails when
# each required condition is broken.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
smoke="$repo_root/scripts/device-smoke-test.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/weather-pi-smoke-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

stubs="$tmp/bin"
mkdir -p "$stubs"

cat >"$stubs/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    "is-active --quiet weather-pi.service")
        [[ "${SMOKE_TEST_FAIL:-}" == "service" ]] && exit 3
        exit 0
        ;;
    "is-active --quiet weather-pi-tunnel.service")
        [[ "${SMOKE_TEST_FAIL:-}" == "tunnel" ]] && exit 3
        exit 0
        ;;
esac
exit 1
EOF

cat >"$stubs/ip" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "route show default" ]]; then
    if [[ "${SMOKE_TEST_FAIL:-}" == "network" ]]; then
        exit 1
    fi
    echo "default via 192.0.2.1 dev eth0 proto dhcp src 192.0.2.10 metric 600"
    exit 0
fi
exit 1
EOF

cat >"$stubs/ping" <<'EOF'
#!/usr/bin/env bash
[[ "${SMOKE_TEST_FAIL:-}" == "network" ]] && exit 1
exit 0
EOF

cat >"$stubs/unattended-upgrade" <<'EOF'
#!/usr/bin/env bash
[[ "${SMOKE_TEST_FAIL:-}" == "unattended" ]] && exit 1
echo "No packages found that can be upgraded unattended"
exit 0
EOF
chmod +x "$stubs/systemctl" "$stubs/ip" "$stubs/ping" "$stubs/unattended-upgrade"

make_root() {
    local root="$1"
    mkdir -p \
        "$root/dev" \
        "$root/etc/weather-pi" \
        "$root/usr/bin" \
        "$root/etc/systemd/system"
    : >"$root/dev/spidev0.0"
    cat >"$root/etc/weather-pi/tunnel.env" <<'EOF'
TUNNEL_HOST=vps.example.com
TUNNEL_PORT=22
TUNNEL_USER=tunnel
TUNNEL_REMOTE_PORT=2200
EOF
    : >"$root/etc/weather-pi/tunnel_key"
    : >"$root/etc/weather-pi/known_hosts"
    cat >"$root/etc/weather-pi/tunnel.toml" <<'EOF'
[tunnel]
host = "vps.example.com"
port = 22
EOF
    cat >"$root/usr/bin/weather-pi" <<'EOF'
#!/usr/bin/env bash
echo "${SMOKE_TEST_VERSION:-weather-pi 9.9.9 (test)}"
EOF
    chmod +x "$root/usr/bin/weather-pi"
}

run_smoke() {
    local root="$1"
    shift
    PATH="$stubs:$PATH" WEATHER_PI_SMOKE_ALLOW_NONROOT=1 \
        "$smoke" --root "$root" "$@"
}

expect_pass() {
    local root="$1" description="$2"
    shift 2
    if ! run_smoke "$root" "$@" >"$tmp/output" 2>&1; then
        cat "$tmp/output" >&2
        echo "FAIL: smoke test rejected $description" >&2
        exit 1
    fi
    grep -q 'all .* checks passed' "$tmp/output" ||
        {
            cat "$tmp/output" >&2
            echo "FAIL: smoke test did not report success for $description" >&2
            exit 1
        }
}

expect_fail() {
    local root="$1" description="$2"
    shift 2
    if run_smoke "$root" "$@" >"$tmp/output" 2>&1; then
        cat "$tmp/output" >&2
        echo "FAIL: smoke test accepted $description" >&2
        exit 1
    fi
    grep -q '^FAIL:' "$tmp/output" ||
        {
            cat "$tmp/output" >&2
            echo "FAIL: smoke test failed without a FAIL line for $description" >&2
            exit 1
        }
}

root="$tmp/root"
make_root "$root"

echo "==> all conditions healthy"
expect_pass "$root" "a healthy device"

echo "==> no tunnel is not a failure"
no_tunnel="$tmp/no-tunnel"
make_root "$no_tunnel"
rm -f "$no_tunnel/etc/weather-pi/tunnel.env" "$no_tunnel/etc/weather-pi/tunnel.toml"
expect_pass "$no_tunnel" "a device without a tunnel"

echo "==> app unit failure is fatal"
SMOKE_TEST_FAIL=service expect_fail "$root" "an inactive weather-pi.service"

echo "==> tunnel unit failure is fatal"
SMOKE_TEST_FAIL=tunnel expect_fail "$root" "an inactive weather-pi-tunnel.service"

echo "==> missing SPI is fatal"
no_spi="$tmp/no-spi"
make_root "$no_spi"
rm -f "$no_spi/dev/spidev0.0"
expect_fail "$no_spi" "a device without SPI"

echo "==> network failure is fatal"
SMOKE_TEST_FAIL=network expect_fail "$root" "a device without a default route"

echo "==> unattended-upgrade failure is fatal"
SMOKE_TEST_FAIL=unattended expect_fail "$root" "a failing unattended-upgrade dry run"

echo "==> wrong version output is fatal"
SMOKE_TEST_VERSION="not-weather-pi" expect_fail "$root" "a wrong --version output"

echo "all device smoke test harness checks passed"
