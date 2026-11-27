#!/usr/bin/env bash
# Prepare a Debian/Ubuntu VPS for a weather-pi reverse SSH tunnel.
#
# The script is intentionally small and idempotent: it creates one forwarding
# account, enrolls one device key, and enforces GatewayPorts no. It never
# replaces sshd_config and never opens the tunnel port in a firewall.
set -euo pipefail

PROG="vps-setup.sh"
TUNNEL_USER="weatherpi-tunnel"
PORT="2201"
SERIAL="${WEATHER_PI_SERIAL:-device}"
PUBKEY_FILE=""
SSHD_CONFIG_DIR="/etc/ssh/sshd_config.d"
DRY_RUN=0

usage() {
    cat <<'EOF'
Usage: scripts/vps-setup.sh [OPTIONS]

Create the weatherpi-tunnel account and restrict its forwarding to one
loopback port. Run on the VPS, normally with sudo.

Options:
  --port PORT            VPS loopback port assigned to this device (default 2201)
  --serial SERIAL        Device label used in the authorized_keys comment
  --user USER            Forwarding account (default weatherpi-tunnel)
  --pubkey-file FILE     Device public key to enroll (one OpenSSH public key line)
  --sshd-config DIR      sshd drop-in directory (default /etc/ssh/sshd_config.d)
  --dry-run              Print every action without changing the system
  -h, --help             Show this help

Environment:
  WEATHER_PI_SERIAL      Default for --serial
EOF
}

die() {
    echo "$PROG: $*" >&2
    exit 1
}

say() {
    echo "$PROG: $*"
}

run() {
    if ((DRY_RUN)); then
        printf '%s: would run:' "$PROG"
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

need_arg() {
    [[ $# -ge 2 && -n "$2" ]] || die "$1 requires an argument"
}

validate_port() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]] || die "port must be numeric (got '$value')"
    ((1 <= 10#$value && 10#$value <= 65535)) || die "port must be between 1 and 65535 (got '$value')"
}

validate_name() {
    local value="$1" what="$2"
    [[ "$value" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || die "$what '$value' is not a valid lower-case account name"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)
            need_arg "$@"
            PORT="$2"
            validate_port "$PORT"
            shift 2
            ;;
        --serial)
            need_arg "$@"
            SERIAL="$2"
            shift 2
            ;;
        --user)
            need_arg "$@"
            TUNNEL_USER="$2"
            validate_name "$TUNNEL_USER" "user"
            shift 2
            ;;
        --pubkey-file)
            need_arg "$@"
            PUBKEY_FILE="$2"
            shift 2
            ;;
        --sshd-config)
            need_arg "$@"
            SSHD_CONFIG_DIR="${2%/}"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument '$1' (try --help)"
            ;;
    esac
done

SERIAL="${SERIAL:-device}"
[[ "$SERIAL" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "serial '$SERIAL' may contain only letters, digits, '.', '_' and '-'"
[[ "$SSHD_CONFIG_DIR" == /* ]] || die "--sshd-config must be an absolute path"
[[ "$TUNNEL_USER" != "root" ]] || die "refusing to use root as the tunnel account"

if [[ -n "$PUBKEY_FILE" ]]; then
    [[ -f "$PUBKEY_FILE" && -r "$PUBKEY_FILE" ]] || die "public key file '$PUBKEY_FILE' is not readable"
fi

if ((DRY_RUN == 0)) && ((EUID != 0)); then
    die "run as root (for example: sudo scripts/vps-setup.sh ...)"
fi

for tool in useradd usermod install id; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool '$tool' is not installed"
done

if [[ ! -x /usr/sbin/nologin ]]; then
    say "warning: /usr/sbin/nologin is missing; install openssh-server on this VPS"
fi

TUNNEL_HOME="/home/$TUNNEL_USER"
TUNNEL_GROUP="$TUNNEL_USER"
if id -u "$TUNNEL_USER" >/dev/null 2>&1; then
    if command -v getent >/dev/null 2>&1; then
        existing_home="$(getent passwd "$TUNNEL_USER" | awk -F: '{print $6}')"
        [[ -n "$existing_home" ]] && TUNNEL_HOME="$existing_home"
    fi
    existing_group="$(id -gn "$TUNNEL_USER" 2>/dev/null || true)"
    [[ -n "$existing_group" ]] && TUNNEL_GROUP="$existing_group"
    existing_shell=""
    if command -v getent >/dev/null 2>&1; then
        existing_shell="$(getent passwd "$TUNNEL_USER" | awk -F: '{print $7}')"
    fi
    if [[ -n "$existing_shell" && "$existing_shell" != "/usr/sbin/nologin" ]]; then
        say "setting '$TUNNEL_USER' shell to /usr/sbin/nologin"
        run usermod --shell /usr/sbin/nologin "$TUNNEL_USER"
    fi
    say "account '$TUNNEL_USER' already exists (home $TUNNEL_HOME)"
else
    say "creating system account '$TUNNEL_USER' with home $TUNNEL_HOME"
    run useradd --system --home-dir "$TUNNEL_HOME" --no-create-home \
        --shell /usr/sbin/nologin --user-group "$TUNNEL_USER"
fi

run install -d -m 0755 -o "$TUNNEL_USER" -g "$TUNNEL_GROUP" "$TUNNEL_HOME"
run install -d -m 0700 -o "$TUNNEL_USER" -g "$TUNNEL_GROUP" "$TUNNEL_HOME/.ssh"

authorized_keys="$TUNNEL_HOME/.ssh/authorized_keys"
if [[ -e "$authorized_keys" ]]; then
    run chown "$TUNNEL_USER:$TUNNEL_GROUP" "$authorized_keys"
    run chmod 0600 "$authorized_keys"
else
    run install -m 0600 -o "$TUNNEL_USER" -g "$TUNNEL_GROUP" /dev/null "$authorized_keys"
fi

if [[ -n "$PUBKEY_FILE" ]]; then
    mapfile -t pubkey_lines < <(sed -e 's/[[:space:]]*$//' "$PUBKEY_FILE" | grep -v '^[[:space:]]*$' || true)
    [[ ${#pubkey_lines[@]} -eq 1 ]] || die "public key file must contain exactly one non-empty line"
    pubkey_line="${pubkey_lines[0]}"
    [[ "$pubkey_line" != *"PRIVATE KEY"* ]] || die "public key file contains private key material"

    read -r key_type key_blob _ <<<"$pubkey_line" || true
    [[ -n "${key_type:-}" && -n "${key_blob:-}" ]] || die "public key file is not an OpenSSH public key line"
    case "$key_type" in
        ssh-ed25519 | ssh-rsa | ecdsa-sha2-nistp256 | ecdsa-sha2-nistp384 | ecdsa-sha2-nistp521 | sk-ssh-ed25519@openssh.com | sk-ecdsa-sha2-nistp256@openssh.com)
            ;;
        *)
            die "unsupported public key type '$key_type'"
            ;;
    esac

    if command -v ssh-keygen >/dev/null 2>&1; then
        ssh-keygen -l -f "$PUBKEY_FILE" >/dev/null 2>&1 || die "ssh-keygen rejected '$PUBKEY_FILE' as a public key"
    fi

    options="restrict,port-forwarding,permitlisten=\"127.0.0.1:$PORT\""
    desired_line="$options $key_type $key_blob weatherpi-$SERIAL"

    already_present=0
    if [[ -f "$authorized_keys" ]]; then
        while IFS= read -r existing_line; do
            [[ -z "$existing_line" ]] && continue
            existing_line="${existing_line%$'\r'}"
            for token in $existing_line; do
                if [[ "$token" == "$key_blob" ]]; then
                    already_present=1
                    if [[ "$existing_line" == "$desired_line" ]]; then
                        say "device key already enrolled for $TUNNEL_USER"
                    else
                        say "WARNING: the same key is already present with different options or comment:"
                        printf '  %s\n' "$existing_line"
                        say "leaving the existing line unchanged; edit it deliberately if the port or serial changed"
                    fi
                    break
                fi
            done
            ((already_present == 0)) || break
        done <"$authorized_keys"
    fi

    if ((already_present == 0)); then
        if ((DRY_RUN)); then
            printf '%s: authorized_keys += %s\n' "$PROG" "$desired_line"
        else
            if [[ -s "$authorized_keys" ]] && [[ "$(tail -c 1 "$authorized_keys" | wc -l)" -eq 0 ]]; then
                printf '\n' >>"$authorized_keys"
            fi
            printf '%s\n' "$desired_line" >>"$authorized_keys"
            chown "$TUNNEL_USER:$TUNNEL_GROUP" "$authorized_keys"
            chmod 0600 "$authorized_keys"
            say "enrolled device key as weatherpi-$SERIAL"
        fi
    fi
else
    say "no --pubkey-file supplied; enroll the device public key later with:"
    printf '  sudo %s --port %s --serial <serial> --pubkey-file <device.pub>\n' "$0" "$PORT"
fi

if command -v ss >/dev/null 2>&1; then
    if ss -H -ltn 2>/dev/null | awk '{print $4}' | grep -Eq ":$PORT$"; then
        say "WARNING: TCP port $PORT already has a listener on this VPS"
        if ((DRY_RUN == 0)); then
            ss -ltnp 2>/dev/null | awk -v p=":$PORT" '$4 ~ p "$"' || true
        fi
        say "the tunnel will fail with ExitOnForwardFailure until the port is free; choose another --port"
    else
        say "TCP port $PORT is free on this VPS"
    fi
else
    say "warning: 'ss' is not installed; cannot check whether port $PORT is already bound"
fi

fragment="$SSHD_CONFIG_DIR/00-weatherpi-tunnel.conf"
desired_fragment='# Managed by weather-pi scripts/vps-setup.sh.
# The device tunnel forwards to the VPS loopback interface only. Do not add
# GatewayPorts clientspecified or yes here; a client mistake must not expose
# the device to the internet.
GatewayPorts no'
fragment_changed=0
if [[ -f "$fragment" ]] && printf '%s\n' "$desired_fragment" | cmp -s - "$fragment"; then
    say "sshd drop-in $fragment is already current"
else
    say "installing sshd drop-in $fragment"
    if ((DRY_RUN)); then
        printf '%s: would write %s:\n%s\n' "$PROG" "$fragment" "$desired_fragment"
    else
        install -d -m 0755 "$SSHD_CONFIG_DIR"
        fragment_tmp="$(mktemp)"
        printf '%s\n' "$desired_fragment" >"$fragment_tmp"
        install -m 0644 "$fragment_tmp" "$fragment"
        rm -f "$fragment_tmp"
        fragment_changed=1
    fi
fi

if ((DRY_RUN == 0)); then
    if [[ -f /etc/ssh/sshd_config ]] && ! grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
        say "WARNING: /etc/ssh/sshd_config does not include /etc/ssh/sshd_config.d/*.conf"
        say "the drop-in may be ignored; add the Include line deliberately"
    fi

    if command -v sshd >/dev/null 2>&1 && [[ "$SSHD_CONFIG_DIR" == "/etc/ssh/sshd_config.d" ]]; then
        if ! sshd -t; then
            if ((fragment_changed)); then
                rm -f "$fragment"
                say "removed the invalid drop-in; sshd was not reloaded"
            fi
            die "sshd -t rejected the configuration; fix it before reloading"
        fi
        if ! effective="$(sshd -T 2>/dev/null)"; then
            if ((fragment_changed)); then
                rm -f "$fragment"
            fi
            die "sshd -T failed; fix the configuration before reloading"
        fi
        if ! grep -qix 'gatewayports no' <<<"$effective"; then
            if ((fragment_changed)); then
                rm -f "$fragment"
            fi
            die "GatewayPorts is not 'no' in the effective sshd configuration; sshd was not reloaded"
        fi
        say "sshd configuration accepted; GatewayPorts is no"
    elif [[ "$SSHD_CONFIG_DIR" != "/etc/ssh/sshd_config.d" ]]; then
        say "custom sshd drop-in directory; skipping sshd -t and sshd -T validation"
    else
        say "warning: sshd is not installed; skipping config validation"
    fi

    if ((fragment_changed)); then
        if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
            if systemctl reload ssh 2>/dev/null; then
                say "reloaded sshd (ssh.service)"
            elif systemctl reload sshd 2>/dev/null; then
                say "reloaded sshd (sshd.service)"
            else
                die "could not reload sshd; reload it manually after checking sshd -t"
            fi
        elif command -v service >/dev/null 2>&1 && { service ssh reload 2>/dev/null || service sshd reload 2>/dev/null; }; then
            say "reloaded sshd (service)"
        else
            die "could not reload sshd; reload it manually after checking sshd -t"
        fi
    fi
fi

say "VPS host keys (pin one as host_key in the provisioning configuration):"
shopt -s nullglob
host_key_files=(/etc/ssh/ssh_host_*_key.pub)
shopt -u nullglob
if [[ ${#host_key_files[@]} -eq 0 ]]; then
    say "WARNING: no /etc/ssh/ssh_host_*_key.pub files found; generate host keys first"
else
    for host_key_file in "${host_key_files[@]}"; do
        fingerprint="unknown"
        if command -v ssh-keygen >/dev/null 2>&1; then
            fingerprint="$(ssh-keygen -E sha256 -lf "$host_key_file" 2>/dev/null | awk '{print $2}')" || true
            [[ -n "$fingerprint" ]] || fingerprint="unknown"
        fi
        printf '  %s\n' "$host_key_file"
        printf '    fingerprint: %s\n' "$fingerprint"
        printf '    host_key = "%s"\n' "$(awk '{print $1 " " $2; exit}' "$host_key_file")"
    done
    say "Use the complete host_key value (not the fingerprint) in tunnel.toml or the provisioning file."
    say "Prefer the ssh-ed25519 key when the VPS offers one, and pin exactly one key."
    say "Verify the fingerprint on the VPS console before trusting a network copy."
fi

say "done; ensure the VPS firewall allows SSH from the operator only, not port $PORT"
