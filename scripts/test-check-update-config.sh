#!/usr/bin/env bash
# Tests for scripts/check-update-config.sh.
#
# The tests use fake apt-config and unattended-upgrade commands in PATH, so they
# run as an ordinary user and never touch the real package database.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check="$repo_root/scripts/check-update-config.sh"
staged="$repo_root/image/stage-weather-pi/10-unattended-upgrades/files/usr/lib/weather-pi/check-update-config.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/weather-pi-check-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fake="$tmp/bin"
mkdir -p "$fake"

cat >"$fake/apt-config" <<'EOF'
#!/usr/bin/env bash
cat "${FAKE_APT_DUMP:?FAKE_APT_DUMP is not set}"
EOF

cat >"$fake/unattended-upgrade" <<'EOF'
#!/usr/bin/env bash
if [[ -n ${FAKE_UU_MARKER:-} ]]; then
	: >"$FAKE_UU_MARKER"
fi

case "${FAKE_UU_MODE:-success}" in
success)
	cat <<'OUT'
Allowed origins are: origin=weather-pi,archive=trixie, origin=Debian,codename=trixie,label=Debian
Checking: weather-pi (0.2.1-1)
Packages that will be upgraded: weather-pi
OUT
	;;
none)
	cat <<'OUT'
Allowed origins are: origin=weather-pi,archive=trixie, origin=Debian,codename=trixie,label=Debian
No packages found that can be upgraded unattended and no pending auto-removals
OUT
	;;
error)
	echo 'E: simulated unattended-upgrade failure' >&2
	exit 1
	;;
*)
	echo "fake unattended-upgrade: unknown mode ${FAKE_UU_MODE}" >&2
	exit 2
	;;
esac
EOF

chmod +x "$fake/apt-config" "$fake/unattended-upgrade"

base_dump() {
	cat <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
Acquire::Check-Valid-Until "true";
APT::Keep-Downloaded-Packages "true";
Unattended-Upgrade::Origins-Pattern "";
Unattended-Upgrade::Origins-Pattern:: "origin=Debian,codename=trixie,label=Debian";
Unattended-Upgrade::Origins-Pattern:: "origin=Debian,codename=trixie-security,label=Debian-Security";
Unattended-Upgrade::Origins-Pattern:: "origin=Raspbian,codename=trixie,label=Raspbian";
Unattended-Upgrade::Origins-Pattern:: "origin=Raspberry Pi Foundation,codename=trixie,label=Raspberry Pi Foundation";
Unattended-Upgrade::Origins-Pattern:: "origin=weather-pi,archive=trixie";
EOF
}

checks=0
failures=0
case_output=""
case_status=0

ok() {
	checks=$((checks + 1))
	printf 'ok %d - %s\n' "$checks" "$1"
}

not_ok() {
	checks=$((checks + 1))
	failures=$((failures + 1))
	printf 'not ok %d - %s\n' "$checks" "$1"
	if [[ -n $case_output ]]; then
		printf '%s\n' "$case_output" | sed 's/^/#   /'
	fi
}

run_check() {
	local dump="$1"
	local mode="$2"
	shift 2

	printf '%s\n' "$dump" >"$tmp/dump"
	rm -f "$tmp/marker"

	set +e
	case_output="$(PATH="$fake:$PATH" \
		FAKE_APT_DUMP="$tmp/dump" \
		FAKE_UU_MODE="$mode" \
		FAKE_UU_MARKER="$tmp/marker" \
		"$check" "$@" 2>&1)"
	case_status=$?
	set -e
}

expect() {
	local expected="$1"
	local name="$2"
	local pattern="$3"
	local dump="$4"
	local mode="$5"
	shift 5

	run_check "$dump" "$mode" "$@"

	if [[ $expected == pass ]]; then
		if [[ $case_status -eq 0 && $case_output == *'RESULT: PASS'* ]]; then
			ok "$name"
		else
			not_ok "$name (expected PASS, got exit $case_status)"
		fi
	elif [[ $case_status -ne 0 && $case_output == *'RESULT: FAIL'* &&
		$case_output == *"$pattern"* ]]; then
		ok "$name"
	else
		not_ok "$name (expected FAIL containing '$pattern', got exit $case_status)"
	fi
}

base="$(base_dump)"

expect pass 'all checks pass with a project candidate' '' "$base" success
expect pass 'a normal no-packages dry run passes' '' "$base" none

no_periodic_updates="${base/APT::Periodic::Unattended-Upgrade \"1\";/APT::Periodic::Unattended-Upgrade \"0\";}"
expect fail 'disabled periodic unattended upgrade fails' \
	'APT::Periodic::Unattended-Upgrade' "$no_periodic_updates" success

no_periodic_lists="${base/APT::Periodic::Update-Package-Lists \"1\";/APT::Periodic::Update-Package-Lists \"0\";}"
expect fail 'disabled periodic list refresh fails' \
	'APT::Periodic::Update-Package-Lists' "$no_periodic_lists" success

no_valid_until="${base/Acquire::Check-Valid-Until \"true\";/Acquire::Check-Valid-Until \"false\";}"
expect fail 'disabled Valid-Until enforcement fails' \
	'Acquire::Check-Valid-Until' "$no_valid_until" success

no_keep="${base/APT::Keep-Downloaded-Packages \"true\";/APT::Keep-Downloaded-Packages \"false\";}"
expect fail 'disabled download cache fails' \
	'APT::Keep-Downloaded-Packages' "$no_keep" success

no_project="$(grep -Fv 'origin=weather-pi' <<<"$base")"
expect fail 'missing project origin fails' \
	'origin=weather-pi' "$no_project" success

no_distribution="$(grep -Ev 'origin=(Debian|Raspbian|Raspberry Pi Foundation)' <<<"$base")"
expect fail 'missing distribution origin fails' \
	'Debian/Raspberry Pi OS origin' "$no_distribution" success

expect fail 'a failing dry run fails' \
	'unattended-upgrade --dry-run -d failed' "$base" error

run_check "$base" error --no-dry-run
if [[ $case_status -eq 0 && $case_output == *'RESULT: PASS'* &&
	$case_output == *'SKIP  unattended-upgrade --dry-run -d'* ]]; then
	if [[ -e $tmp/marker ]]; then
		not_ok '--no-dry-run does not invoke unattended-upgrade'
	else
		ok '--no-dry-run skips the dry run and passes'
	fi
else
	not_ok '--no-dry-run skips the dry run and passes'
fi

if cmp -s "$check" "$staged"; then
	ok 'staged image copy matches scripts/check-update-config.sh'
else
	not_ok 'staged image copy differs from scripts/check-update-config.sh'
fi

printf '\n%d checks, %d failed\n' "$checks" "$failures"
if ((failures > 0)); then
	printf 'RESULT: FAIL\n'
	exit 1
fi
printf 'RESULT: PASS\n'
