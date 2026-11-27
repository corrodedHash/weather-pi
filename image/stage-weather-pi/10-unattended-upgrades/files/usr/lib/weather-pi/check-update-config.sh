#!/usr/bin/env bash
# Read-only verification of the weather-pi unattended-upgrade configuration.
#
# Usage:
#   check-update-config.sh [--no-dry-run]
#
# The static checks read the effective apt configuration through apt-config.
# Unless --no-dry-run is given, the script also runs
# `unattended-upgrade --dry-run -d` and shows the project origin and candidate
# (or the normal "no packages" result). It never installs anything.
#
# Exit status is 0 only when every check that ran passed. The image build
# invokes it with --no-dry-run so the build never depends on a live candidate
# or on network access.
set -u

export LC_ALL=C

dry_run=1
passed=0
failed=0
skipped=0
tmp=""

usage() {
	cat <<'EOF'
Usage: check-update-config.sh [--no-dry-run]

Verify the weather-pi apt and unattended-upgrades configuration. The script is
read-only with respect to packages. By default it also runs
`unattended-upgrade --dry-run -d`; pass --no-dry-run to run only the static
checks (used by the image chroot build).

Exit status is 0 when all checks pass, 1 when any check fails.
EOF
}

pass() {
	printf 'PASS  %s\n' "$*"
	passed=$((passed + 1))
}

fail() {
	printf 'FAIL  %s\n' "$*" >&2
	failed=$((failed + 1))
}

skip() {
	printf 'SKIP  %s\n' "$*"
	skipped=$((skipped + 1))
}

summary() {
	printf '\nSummary: %d passed, %d failed, %d skipped\n' \
		"$passed" "$failed" "$skipped"
	if ((failed > 0)); then
		printf 'RESULT: FAIL\n'
		return 1
	fi
	printf 'RESULT: PASS\n'
}

cleanup() {
	if [[ -n $tmp ]]; then
		rm -f "$tmp"
	fi
}
trap cleanup EXIT

while (($# > 0)); do
	case "$1" in
	--no-dry-run)
		dry_run=0
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		printf 'check-update-config.sh: unknown argument: %s\n' "$1" >&2
		usage >&2
		exit 2
		;;
	esac
	shift
done

if ! command -v apt-config >/dev/null 2>&1; then
	fail "apt-config is not available"
	summary || true
	exit 1
fi

if ! dump="$(apt-config dump 2>&1)"; then
	fail "apt-config dump failed"
	printf '%s\n' "$dump" | sed 's/^/      /' >&2
	summary || true
	exit 1
fi

check_value() {
	local key="$1"
	local expected="$2"
	local found

	if grep -Fqx "$key \"$expected\";" <<<"$dump"; then
		pass "$key is \"$expected\""
		return
	fi

	fail "$key is not \"$expected\""
	found="$(grep -F "$key " <<<"$dump" | head -n 3 || true)"
	if [[ -n $found ]]; then
		printf '%s\n' "$found" | sed 's/^/      found: /' >&2
	else
		printf '      found: (unset)\n' >&2
	fi
}

check_value 'APT::Periodic::Update-Package-Lists' '1'
check_value 'APT::Periodic::Unattended-Upgrade' '1'
check_value 'Acquire::Check-Valid-Until' 'true'
check_value 'APT::Keep-Downloaded-Packages' 'true'

# apt-config dump prints list values as:
#   Unattended-Upgrade::Origins-Pattern "";
#   Unattended-Upgrade::Origins-Pattern:: "origin=...";
origins="$(grep -E '^Unattended-Upgrade::Origins-Pattern::[[:space:]]' <<<"$dump" || true)"
project_origin="$(grep -F 'origin=weather-pi' <<<"$origins" |
	grep -F 'archive=trixie' | head -n 1 || true)"
if [[ -n $project_origin ]]; then
	pass 'Unattended-Upgrade::Origins-Pattern includes origin=weather-pi,archive=trixie'
else
	fail 'Unattended-Upgrade::Origins-Pattern does not include origin=weather-pi,archive=trixie'
	if [[ -n $origins ]]; then
		printf '%s\n' "$origins" | sed 's/^/      found: /' >&2
	else
		printf '      found: (no origins)\n' >&2
	fi
fi

# The image build performs the strict comparison by moving the project fragment
# aside. Here, at least require that a distribution origin is still effective;
# this catches a fragment that replaced the distribution's list instead of
# extending it.
distribution_origin="$(grep -E \
	'(origin|o)=(Debian|Raspbian|Raspberry Pi Foundation|Raspberry Pi OS)(,|")' \
	<<<"$origins" | head -n 1 || true)"
if [[ -n $distribution_origin ]]; then
	pass 'a Debian or Raspberry Pi OS origin is still allowed'
else
	fail 'Unattended-Upgrade::Origins-Pattern has no Debian/Raspberry Pi OS origin'
	printf '%s\n' "$origins" | sed 's/^/      found: /' >&2
fi

if ((dry_run == 0)); then
	skip 'unattended-upgrade --dry-run -d (--no-dry-run)'
elif ! command -v unattended-upgrade >/dev/null 2>&1; then
	skip 'unattended-upgrade --dry-run -d (command not installed)'
else
	tmp="$(mktemp "${TMPDIR:-/tmp}/weather-pi-check.XXXXXX")" || {
		tmp=""
		fail 'could not create a temporary file for the dry run'
	}
	if [[ -n $tmp ]]; then
		dry_status=0
		if unattended-upgrade --dry-run -d >"$tmp" 2>&1; then
			pass 'unattended-upgrade --dry-run -d completed'
		else
			dry_status=$?
			fail "unattended-upgrade --dry-run -d failed with exit status $dry_status"
		fi

		if ((dry_status == 0)); then
			if grep -Fq 'origin=weather-pi,archive=trixie' "$tmp"; then
				pass 'dry run lists origin=weather-pi,archive=trixie'
			else
				fail 'dry run did not list origin=weather-pi,archive=trixie'
			fi
		fi

		evidence="$(grep -Ei \
			'Allowed origins are:|weather-pi|Packages that (will|may) be upgraded|No packages found that can be upgraded|conffile prompt|^E: |ERROR' \
			"$tmp" | head -n 20 || true)"
		if [[ -n $evidence ]]; then
			printf '      dry-run evidence:\n'
			printf '%s\n' "$evidence" | sed 's/^/      /'
		fi
		if grep -Fq 'No packages found that can be upgraded' "$tmp"; then
			printf '      no packages to upgrade (normal up-to-date result)\n'
		fi

		rm -f "$tmp"
		tmp=""
	fi
fi

summary || exit 1
