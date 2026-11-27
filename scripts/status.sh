#!/usr/bin/env bash
# Read-only weather-pi status: tunnel, application, package versions, update
# timer, and the last unattended-upgrades log lines.
#
# Everything runs in one SSH invocation so status still works when the
# application is stopped and the device is otherwise unresponsive.
set -euo pipefail

HOST="${WEATHER_PI_HOST:-weather-pi}"

die() {
    echo "status.sh: $*" >&2
    exit 1
}

command -v ssh >/dev/null 2>&1 || die "required tool 'ssh' is not installed"

ssh_opts=()
if [[ -n "${WEATHER_PI_SSH_OPTS:-}" ]]; then
    read -r -a ssh_opts <<<"$WEATHER_PI_SSH_OPTS"
fi

ssh_cmd=(ssh -T -o BatchMode=yes -o ConnectTimeout=10 "${ssh_opts[@]}" "$HOST" 'bash -s')

if ! "${ssh_cmd[@]}" <<'REMOTE'
export LC_ALL=C

printf '=== weather-pi status ===\n'

tunnel_active="$(systemctl is-active weather-pi-tunnel.service 2>/dev/null || true)"
tunnel_enabled="$(systemctl is-enabled weather-pi-tunnel.service 2>/dev/null || true)"
printf 'Tunnel unit:                %s (%s)\n' "${tunnel_active:-unknown}" "${tunnel_enabled:-unknown}"

app_active="$(systemctl show -p ActiveState --value weather-pi.service 2>/dev/null || true)"
app_substate="$(systemctl show -p SubState --value weather-pi.service 2>/dev/null || true)"
app_restarts="$(systemctl show -p NRestarts --value weather-pi.service 2>/dev/null || true)"
printf 'Application unit:           %s/%s\n' "${app_active:-unknown}" "${app_substate:-unknown}"
printf 'Application restarts:      %s\n' "${app_restarts:-unknown}"

installed="$(dpkg-query -W -f='${Status} ${Version}' weather-pi 2>/dev/null || true)"
printf 'Installed package:         %s\n' "${installed:-not installed}"

candidate="$(apt-cache policy weather-pi 2>/dev/null | awk '/Candidate:/ {print $2; exit}' || true)"
printf 'Candidate package:         %s\n' "${candidate:-unknown}"

timer_active="$(systemctl is-active apt-daily-upgrade.timer 2>/dev/null || true)"
timer_enabled="$(systemctl is-enabled apt-daily-upgrade.timer 2>/dev/null || true)"
timer_next="$(systemctl list-timers --all --no-pager apt-daily-upgrade.timer 2>/dev/null | sed -n '2p' || true)"
printf 'apt-daily-upgrade.timer:   %s (%s)\n' "${timer_active:-unknown}" "${timer_enabled:-unknown}"
if [[ -n "$timer_next" ]]; then
  printf 'Timer next:                %s\n' "$timer_next"
fi

log_file=/var/log/unattended-upgrades/unattended-upgrades.log
printf '\n--- unattended-upgrades.log (tail) ---\n'
if log_tail="$(sudo -n tail -n 20 "$log_file" 2>&1)"; then
  printf '%s\n' "$log_tail"
elif log_tail="$(tail -n 20 "$log_file" 2>&1)"; then
  printf '%s\n' "$log_tail"
else
  printf '(unavailable: %s; use sudo on the device to read it)\n' "$log_file"
fi

# Keep the remote script's status zero even when the application is stopped.
true
REMOTE
then
    echo "status.sh: cannot collect status from '$HOST'" >&2
    exit 1
fi
