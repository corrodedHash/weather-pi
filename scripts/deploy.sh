#!/usr/bin/env bash
# Copy configuration and BMP assets to a weather-pi over SSH, restart the
# application, and verify that the package-managed binary was not touched.
#
# This script never installs, upgrades, downgrades or replaces a package. The
# installed binary belongs to dpkg; application releases arrive through apt.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

HOST="${WEATHER_PI_HOST:-weather-pi}"
DEPLOY_ASSETS="${WEATHER_PI_DEPLOY_ASSETS:-1}"

die() {
    echo "deploy.sh: $*" >&2
    exit 1
}

for tool in ssh rsync; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool '$tool' is not installed"
done

case "$DEPLOY_ASSETS" in
    0 | 1) ;;
    *) die "WEATHER_PI_DEPLOY_ASSETS must be 0 or 1 (got '$DEPLOY_ASSETS')" ;;
esac

ssh_opts=()
if [[ -n "${WEATHER_PI_SSH_OPTS:-}" ]]; then
    read -r -a ssh_opts <<<"$WEATHER_PI_SSH_OPTS"
fi

ssh_cmd=(ssh -o BatchMode=yes -o ConnectTimeout=10 "${ssh_opts[@]}" "$HOST")

rsh_opts=(-o BatchMode=yes -o ConnectTimeout=10 "${ssh_opts[@]}")
rsync_rsh="ssh"
for opt in "${rsh_opts[@]}"; do
    printf -v quoted '%q' "$opt"
    rsync_rsh+=" $quoted"
done
rsync_cmd=(rsync -a '--chmod=D755,F644' --chown=root:root --rsync-path="sudo -n rsync" -e "$rsync_rsh")

toml_files=()
bmp_files=()
if [[ "$DEPLOY_ASSETS" == "1" ]]; then
    shopt -s nullglob
    toml_files=(assets/*.toml)
    bmp_files=(assets/*.bmp)
    shopt -u nullglob
    [[ ${#toml_files[@]} -gt 0 ]] || die "no TOML assets found under assets/"
    [[ ${#bmp_files[@]} -gt 0 ]] || die "no BMP assets found under assets/"
fi

echo "==> Checking $HOST over SSH"
if ! "${ssh_cmd[@]}" true; then
    die "cannot reach '$HOST' over SSH; check ~/.ssh/config (ProxyJump), the weather-pi-tunnel unit, and that the device is online"
fi

version_cmd="dpkg-query -W -f='\${Version}' weather-pi 2>/dev/null"
before="$("${ssh_cmd[@]}" "$version_cmd" || true)"
before="${before//$'\r'/}"
before="${before//$'\n'/}"
[[ -n "$before" ]] || die "the weather-pi package is not installed on '$HOST'; deploy does not install packages"

if [[ "$DEPLOY_ASSETS" == "1" ]]; then
    echo "==> Copying TOML configuration to $HOST:/etc/weather-pi/"
    "${rsync_cmd[@]}" "${toml_files[@]}" "$HOST:/etc/weather-pi/"

    echo "==> Copying BMP assets to $HOST:/usr/share/weather-pi/"
    "${rsync_cmd[@]}" "${bmp_files[@]}" "$HOST:/usr/share/weather-pi/"
else
    echo "==> WEATHER_PI_DEPLOY_ASSETS=0; skipping configuration and asset copy"
fi

echo "==> Restarting weather-pi.service"
"${ssh_cmd[@]}" "sudo -n systemctl restart weather-pi.service"

if ! "${ssh_cmd[@]}" "sudo -n systemctl is-active --quiet weather-pi.service"; then
    "${ssh_cmd[@]}" "sudo -n systemctl status --no-pager --lines=15 weather-pi.service" || true
    die "weather-pi.service is not active after restart; configuration may have been copied"
fi

after="$("${ssh_cmd[@]}" "$version_cmd" || true)"
after="${after//$'\r'/}"
after="${after//$'\n'/}"
[[ -n "$after" ]] || die "could not read the installed weather-pi version after restart"
[[ "$after" == "$before" ]] || die "installed weather-pi version changed from '$before' to '$after'; deploy must not replace the package"

echo "==> Deploy succeeded"
printf '    host:    %s\n' "$HOST"
printf '    version: %s (unchanged, package-managed)\n' "$before"
printf '    service: active\n'
