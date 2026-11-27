#!/bin/bash -e

fragment=/etc/ssh/sshd_config.d/10-weather-pi.conf
[[ -f "$fragment" ]] || {
	echo "image stage: sshd fragment $fragment is missing" >&2
	exit 1
}

assert_fragment_line() {
	local line="$1"
	grep -Fqx "$line" "$fragment" || {
		echo "image stage: sshd fragment is missing '$line'" >&2
		exit 1
	}
}

assert_fragment_line 'PasswordAuthentication no'
assert_fragment_line 'PermitRootLogin no'
assert_fragment_line 'PubkeyAuthentication yes'
assert_fragment_line 'AllowUsers weather-pi'
assert_fragment_line 'KbdInteractiveAuthentication no'

# Debian and Raspberry Pi OS include the drop-in directory from sshd_config.
# Do not modify the distribution file; fail the effective-settings check below
# if this warning ever becomes a real problem.
if ! grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
	echo "image stage: warning: /etc/ssh/sshd_config does not include /etc/ssh/sshd_config.d/*.conf" >&2
fi

if ! command -v sshd >/dev/null 2>&1; then
	echo "image stage: warning: sshd is not installed yet; fragment contents verified only" >&2
	exit 0
fi

# sshd -t loads the host keys. Fresh pi-gen chroots may not have generated them
# yet, in which case it fails for a reason unrelated to this fragment. Fall back
# to sshd -T, and only warn if both are unavailable.
if sshd_error="$(sshd -t 2>&1)"; then
	effective="$(sshd -T 2>/dev/null)" || {
		echo "image stage: sshd -T failed after sshd -t succeeded" >&2
		exit 1
	}
	for setting in \
		'passwordauthentication no' \
		'permitrootlogin no' \
		'pubkeyauthentication yes' \
		'allowusers weather-pi' \
		'kbdinteractiveauthentication no'; do
		grep -qix "$setting" <<<"$effective" || {
			echo "image stage: sshd does not apply '$setting' (drop-in not included?)" >&2
			exit 1
		}
	done
	echo "image stage: sshd -t and effective settings verified"
elif sshd -T -f /etc/ssh/sshd_config >/dev/null 2>&1; then
	echo "image stage: warning: sshd -t failed (host keys not generated yet); sshd -T parsed the configuration" >&2
else
	echo "image stage: warning: sshd host keys are unavailable; fragment presence verified only" >&2
	echo "image stage: sshd -t said: $sshd_error" >&2
fi
