#!/usr/bin/env bash
# Fail if a staged image payload contains credentials or private key material.
#
#   scripts/check-image-secrets.sh <directory> [directory ...]
#
# The check is intentionally blunt: the image must never ship a WiFi password,
# an SSH/tunnel private key, or the archive signing key. It is run against the
# copied pi-gen stage before Docker starts and again inside the chroot against
# the paths that can hold operator secrets.
set -euo pipefail

if [[ $# -eq 0 ]]; then
    echo "usage: $0 <directory> [directory ...]" >&2
    exit 2
fi

fail=0

report() {
    local file="$1" line="$2" reason="$3"
    if [[ -n "$line" ]]; then
        printf '%s:%s: %s\n' "$file" "$line" "$reason" >&2
    else
        printf '%s: %s\n' "$file" "$reason" >&2
    fi
    fail=1
}

scan_file() {
    local file="$1"
    local match
    local first_byte

    # Armored or textual private keys. The regex deliberately does not match
    # this script's own source text.
    if match="$(grep -anm1 -E -- '-----BEGIN ([A-Z0-9]+ )?PRIVATE KEY-----' "$file" 2>/dev/null)"; then
        report "$file" "${match%%:*}" "private key material"
    fi
    if match="$(grep -anm1 -E -- '-----BEGIN PGP PRIVATE[[:space:]]+KEY BLOCK-----' "$file" 2>/dev/null)"; then
        report "$file" "${match%%:*}" "OpenPGP private key block"
    fi

    # Non-empty password/passphrase assignments in config-like text. Empty
    # quoted values are allowed so a template can carry a placeholder. A
    # boundary check keeps variable names such as WIFI_PASSWORD out of the
    # result; a line must assign the credential itself.
    if ! grep -Iq . "$file"; then
        return 0
    fi
    local lineno=0 line value
    # shellcheck disable=SC2094 # findings go to stderr; the file is read-only here
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))
        if [[ "$line" =~ (^|[^[:alnum:]])([A-Za-z0-9_.-]*(password|passphrase))[[:space:]]*[=:][[:space:]]*(.*)$ ]]; then
            value="${BASH_REMATCH[4]}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
                value="${value:1:${#value}-2}"
            fi
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            if [[ -n "$value" && "$value" != "#"* ]]; then
                report "$file" "$lineno" "non-empty password/passphrase assignment"
            fi
        fi
    done <"$file"
}

scan_gnupg() {
    local file="$1"
    command -v gpg >/dev/null 2>&1 || return 0
    case "${file##*/}" in
        *.gpg | *.pgp | *.kbx | *.asc | *.key | *.keyring) ;;
        *) return 0 ;;
    esac
    if gpg --batch --list-packets -- "$file" 2>/dev/null |
        grep -Eq ':secret (sub )?key packet:'; then
        report "$file" "" "OpenPGP secret key packet (gpg)"
    fi
}

while IFS= read -r -d '' dir; do
    if [[ ! -d "$dir" ]]; then
        echo "$0: not a directory: $dir" >&2
        fail=1
        continue
    fi
    while IFS= read -r -d '' file; do
        scan_file "$file"

        # A binary OpenPGP keyring or export starts with a secret-key packet
        # (tag 5) or secret-subkey packet (tag 7); gpg gives a more precise
        # answer for packets stored later in a file.
        if [[ -s "$file" ]] && ! grep -Iq . "$file"; then
            first_byte="$(od -An -tx1 -N1 "$file" 2>/dev/null | tr -d '[:space:]' || true)"
            case "$first_byte" in
                c5 | c7 | 95 | 97)
                    report "$file" "" "OpenPGP secret key packet"
                    ;;
            esac
        fi
        scan_gnupg "$file"
    done < <(find "$dir" \( -name __pycache__ -o -name '*.pyc' \) -prune -o -type f -print0)
done < <(printf '%s\0' "$@")

if ((fail)); then
    echo "secret scan failed" >&2
    exit 1
fi

echo "secret scan passed: $*"
