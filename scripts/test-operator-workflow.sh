#!/usr/bin/env bash
# Exercise the deploy/status operator scripts with fake ssh and rsync.
#
# These tests do not need a device: they assert the failure path when SSH is
# unreachable, the successful deploy sequence and unchanged-version check, and
# that status reports every required field while the application is stopped.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/weather-pi-operator-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fakebin="$tmp/bin"
state="$tmp/state"
mkdir -p "$fakebin" "$state"

fail() {
    echo "test-operator-workflow.sh: FAIL: $*" >&2
    exit 1
}

reset_state() {
    rm -f "$state"/actions "$state"/version_calls "$state"/rsync_calls "$state"/rsync_* "$state"/ssh_calls
}

cat >"$fakebin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -u

if [[ "${FAKE_SSH_UNREACHABLE:-0}" == "1" ]]; then
    echo "ssh: connect to host ${FAKE_HOST:-weather-pi} port 22: Connection refused" >&2
    exit 255
fi

args="$*"
printf '%s\n' "$args" >>"${FAKE_STATE_DIR}/ssh_calls"
if [[ "$args" == *"bash -s"* ]]; then
    exec bash -s
fi

cmd="${!#}"
case "$cmd" in
    true)
        exit 0
        ;;
    *dpkg-query*)
        count_file="${FAKE_STATE_DIR}/version_calls"
        n=0
        [[ -f "$count_file" ]] && n="$(cat "$count_file")"
        n=$((n + 1))
        printf '%s\n' "$n" >"$count_file"
        if [[ "${FAKE_VERSION_CHANGED:-0}" == "1" && "$n" -ge 2 ]]; then
            printf '%s\n' "${FAKE_VERSION_AFTER:-0.2.0-1}"
        else
            printf '%s\n' "${FAKE_VERSION_BEFORE:-0.1.1-1}"
        fi
        ;;
    *"systemctl restart"*)
        printf '%s\n' "$cmd" >>"${FAKE_STATE_DIR}/actions"
        ;;
    *"systemctl is-active"*)
        exit "${FAKE_ACTIVE_CODE:-0}"
        ;;
    *"systemctl status"*)
        echo "fake weather-pi.service diagnostic"
        ;;
    *)
        printf '%s\n' "$cmd" >>"${FAKE_STATE_DIR}/actions"
        ;;
esac
FAKE_SSH

cat >"$fakebin/rsync" <<'FAKE_RSYNC'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >>"${FAKE_STATE_DIR}/rsync_calls"
count=0
[[ -f "${FAKE_STATE_DIR}/rsync_calls" ]] && count="$(wc -l <"${FAKE_STATE_DIR}/rsync_calls")"
touch "${FAKE_STATE_DIR}/rsync_${count}"
exit 0
FAKE_RSYNC

cat >"$fakebin/systemctl" <<'FAKE_SYSTEMCTL'
#!/usr/bin/env bash
set -u
case "$*" in
    "is-active weather-pi-tunnel.service") echo active ;;
    "is-enabled weather-pi-tunnel.service") echo enabled ;;
    "show -p ActiveState --value weather-pi.service") echo "${FAKE_APP_ACTIVE:-inactive}" ;;
    "show -p SubState --value weather-pi.service") echo "${FAKE_APP_SUBSTATE:-dead}" ;;
    "show -p NRestarts --value weather-pi.service") echo "${FAKE_NRESTARTS:-3}" ;;
    "is-active apt-daily-upgrade.timer") echo active ;;
    "is-enabled apt-daily-upgrade.timer") echo enabled ;;
    list-timers*) printf 'NEXT                        LEFT\n'; printf 'n/a                         n/a\n' ;;
    *) echo active ;;
esac
FAKE_SYSTEMCTL

cat >"$fakebin/dpkg-query" <<'FAKE_DPKG'
#!/usr/bin/env bash
echo "install ok installed 0.1.1-1"
FAKE_DPKG

cat >"$fakebin/apt-cache" <<'FAKE_APT'
#!/usr/bin/env bash
printf 'weather-pi:\n'
printf '  Installed: 0.1.1-1\n'
printf '  Candidate: 0.2.0-1\n'
FAKE_APT

cat >"$fakebin/sudo" <<'FAKE_SUDO'
#!/usr/bin/env bash
set -u
[[ "${1:-}" == "-n" ]] && shift
exec "$@"
FAKE_SUDO

cat >"$fakebin/tail" <<'FAKE_TAIL'
#!/usr/bin/env bash
echo "2026-11-27 06:00:00,000 INFO Packages that will be upgraded: weather-pi"
FAKE_TAIL

chmod +x "$fakebin"/*

run_deploy() {
    env PATH="$fakebin:$PATH" \
        WEATHER_PI_HOST=weather-pi \
        FAKE_STATE_DIR="$state" \
        "$@" \
        bash "$repo_root/scripts/deploy.sh"
}

run_status() {
    env PATH="$fakebin:$PATH" \
        WEATHER_PI_HOST=weather-pi \
        FAKE_STATE_DIR="$state" \
        "$@" \
        bash "$repo_root/scripts/status.sh"
}

# 1. Unreachable device: clear failure, no rsync or remote changes.
reset_state
set +e
output="$(run_deploy FAKE_SSH_UNREACHABLE=1 2>&1)"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "deploy succeeded with an unreachable device"
grep -Fq "cannot reach 'weather-pi'" <<<"$output" || fail "unreachable error is not clear"
[[ ! -e "$state/rsync_1" ]] || fail "deploy ran rsync after a failed preflight"
[[ ! -e "$state/actions" ]] || fail "deploy changed remote state after a failed preflight"

# 2. Successful deploy: two rsync calls, restart, unchanged package version.
reset_state
output="$(run_deploy 2>&1)" || fail "deploy failed against the fake reachable host: $output"
grep -Fq "Deploy succeeded" <<<"$output" || fail "deploy did not report success"
grep -Fq "0.1.1-1 (unchanged, package-managed)" <<<"$output" || fail "deploy did not report the unchanged version"
grep -Fq "systemctl restart weather-pi.service" "$state/actions" || fail "deploy did not restart the service"
[[ "$(wc -l <"$state/rsync_calls")" -eq 2 ]] || fail "deploy did not copy both TOML and BMP assets"
grep -Fq "/etc/weather-pi/" "$state/rsync_calls" || fail "deploy did not target /etc/weather-pi/"
grep -Fq "/usr/share/weather-pi/" "$state/rsync_calls" || fail "deploy did not target /usr/share/weather-pi/"
grep -Fq "assets/greeter.toml" "$state/rsync_calls" || fail "deploy did not include the TOML assets"
grep -Fq "assets/countdown.toml" "$state/rsync_calls" || fail "deploy did not include countdown.toml"
if grep -Fq "assets/tunnel.toml" "$state/rsync_calls"; then
    fail "deploy copied the tunnel provisioning template"
fi
grep -Fq "assets/heart.bmp" "$state/rsync_calls" || fail "deploy did not include the BMP assets"
if grep -Fq "target/release/weather-pi" "$state/rsync_calls"; then fail "deploy tried to copy the application binary"; fi

# 3. A version change is rejected even after a successful restart.
reset_state
set +e
output="$(run_deploy FAKE_VERSION_CHANGED=1 2>&1)"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "deploy accepted a changed package version"
grep -Fq "version changed" <<<"$output" || fail "changed-version error is not clear"

# 4. A service that does not become active fails the deploy.
reset_state
set +e
output="$(run_deploy FAKE_ACTIVE_CODE=1 2>&1)"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "deploy accepted an inactive service"
grep -Fq "not active after restart" <<<"$output" || fail "inactive-service error is not clear"

# 5. Status works with a stopped application and labels every required field.
reset_state
output="$(run_status FAKE_APP_ACTIVE=inactive FAKE_APP_SUBSTATE=dead 2>&1)" || fail "status failed with a stopped application"
for label in \
    "Tunnel unit:" \
    "Application unit:" \
    "Application restarts:" \
    "Installed package:" \
    "Candidate package:" \
    "apt-daily-upgrade.timer:" \
    "unattended-upgrades.log"; do
    grep -Fq "$label" <<<"$output" || fail "status output is missing '$label'"
done
grep -Fq "Application unit:           inactive/dead" <<<"$output" || fail "status did not report the stopped application"
grep -Fq "Candidate package:         0.2.0-1" <<<"$output" || fail "status did not report the candidate version"
grep -Fq "2026-11-27 06:00:00" <<<"$output" || fail "status did not report the unattended-upgrades log tail"
[[ "$(wc -l <"$state/ssh_calls")" -eq 1 ]] || fail "status used more than one SSH invocation"

# 6. WEATHER_PI_DEPLOY_ASSETS=0 skips rsync but still restarts and verifies.
reset_state
output="$(run_deploy WEATHER_PI_DEPLOY_ASSETS=0 2>&1)" || fail "restart-only deploy failed: $output"
grep -Fq "skipping configuration and asset copy" <<<"$output" || fail "restart-only deploy did not report skipping assets"
[[ ! -e "$state/rsync_calls" ]] || fail "restart-only deploy still ran rsync"
grep -Fq "systemctl restart weather-pi.service" "$state/actions" || fail "restart-only deploy did not restart the service"

echo "test-operator-workflow.sh: all checks passed"
