#!/usr/bin/env bash
# Validate a weather-pi tunnel TOML document.
#
#   scripts/test-tunnel-config.sh [CONFIG]
#
# With a path, the file is validated and a non-zero status means it must not be
# used. Without a path the script runs its own valid/invalid fixtures and also
# checks the shipped assets/tunnel.toml template.
#
# The validator uses Python 3.11+ tomllib and is intentionally independent of
# the Rust application: the tunnel is configured before the application runs.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -gt 1 ]]; then
    echo "usage: scripts/test-tunnel-config.sh [CONFIG]" >&2
    exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "test-tunnel-config.sh: python3 is required (3.11 or newer for tomllib)" >&2
    exit 1
fi

python3 - "$repo_root" "$@" <<'PY'
import base64
import pathlib
import re
import struct
import sys
import tomllib

KEY_TYPES = {
    "ssh-ed25519",
    "ssh-rsa",
    "ssh-dss",
    "ecdsa-sha2-nistp256",
    "ecdsa-sha2-nistp384",
    "ecdsa-sha2-nistp521",
    "sk-ssh-ed25519@openssh.com",
    "sk-ecdsa-sha2-nistp256@openssh.com",
}
HOST_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:\[\]-]*\Z")
USER_RE = re.compile(r"[a-z_][a-z0-9_-]{0,31}\Z")
REQUIRED = ("host", "port", "user", "remote_port", "host_key")
ALLOWED = set(REQUIRED) | {"private_key"}


class ConfigError(Exception):
    pass


def fail(message):
    raise ConfigError(message)


def require_table(data):
    if not isinstance(data, dict):
        fail("top level must be a TOML table")
    if set(data) != {"tunnel"}:
        missing = "tunnel" not in data
        if missing:
            fail("missing [tunnel] table")
        extra = sorted(set(data) - {"tunnel"})
        fail(f"unknown top-level tables or keys: {', '.join(extra)}")
    table = data["tunnel"]
    if not isinstance(table, dict):
        fail("[tunnel] must be a TOML table")
    return table


def require_string(table, name):
    if name not in table:
        fail(f"missing required field '{name}'")
    value = table[name]
    if not isinstance(value, str) or not value.strip():
        fail(f"'{name}' must be a non-empty string")
    return value.strip()


def require_port(table, name):
    if name not in table:
        fail(f"missing required field '{name}'")
    value = table[name]
    if isinstance(value, bool) or not isinstance(value, int):
        fail(f"'{name}' must be an integer")
    if not 1 <= value <= 65535:
        fail(f"'{name}' must be between 1 and 65535 (got {value})")
    return value


def parse_host_key(value):
    if "PRIVATE KEY" in value:
        fail("'host_key' must be a public key, not private key material")
    lines = value.strip().splitlines()
    if len(lines) != 1:
        fail("'host_key' must be a single public-key line")

    parts = lines[0].split()
    if len(parts) >= 2 and parts[0] in KEY_TYPES:
        key_type, encoded = parts[0], parts[1]
    elif len(parts) >= 3 and parts[1] in KEY_TYPES:
        # Also accept a known_hosts-style line: [host]:port keytype base64.
        if parts[0].startswith("@"):
            fail("'host_key' must not use a known_hosts marker")
        key_type, encoded = parts[1], parts[2]
    else:
        fail("'host_key' must start with a supported OpenSSH public-key type")

    try:
        blob = base64.b64decode(encoded + "=" * (-len(encoded) % 4), validate=True)
    except Exception as exc:
        fail(f"'host_key' contains invalid base64: {exc}")
    if len(blob) < 4:
        fail("'host_key' is too short to be an OpenSSH public key")

    length = struct.unpack(">I", blob[:4])[0]
    if length > len(blob) - 4:
        fail("'host_key' has an invalid OpenSSH wire format")
    try:
        wire_type = blob[4 : 4 + length].decode("ascii")
    except UnicodeDecodeError:
        fail("'host_key' has an invalid OpenSSH key type")
    if wire_type != key_type:
        fail(f"'host_key' type '{key_type}' does not match its encoded key '{wire_type}'")
    return key_type


def validate(data, source):
    table = require_table(data)
    unknown = sorted(set(table) - ALLOWED)
    if unknown:
        fail(f"unknown field(s) in [tunnel]: {', '.join(unknown)}")

    host = require_string(table, "host")
    if len(host) > 253 or not HOST_RE.fullmatch(host):
        fail("'host' must be a host name or address without spaces, '@' or '/'")

    require_port(table, "port")

    user = require_string(table, "user")
    if not USER_RE.fullmatch(user):
        fail("'user' must be a valid lower-case UNIX account name")

    require_port(table, "remote_port")
    parse_host_key(require_string(table, "host_key"))

    if "private_key" in table:
        private_key = table["private_key"]
        if not isinstance(private_key, str) or not private_key.strip():
            fail("'private_key' must be a non-empty string when present")

    return source


DUMMY_WIRE = struct.pack(">I", 11) + b"ssh-ed25519" + struct.pack(">I", 32) + b"\x01" * 32
DUMMY_KEY = "ssh-ed25519 " + base64.b64encode(DUMMY_WIRE).decode("ascii")


def config(omit=(), **overrides):
    values = {
        "host": "vps.example.invalid",
        "port": 22,
        "user": "weatherpi-tunnel",
        "remote_port": 2201,
        "host_key": f"{DUMMY_KEY} test",
    }
    values.update(overrides)
    for key in omit:
        values.pop(key, None)
    lines = ["[tunnel]"]
    for key, value in values.items():
        if isinstance(value, str):
            lines.append(f'{key} = "{value}"')
        else:
            lines.append(f"{key} = {value}")
    return "\n".join(lines) + "\n"


def expect_ok(name, text):
    try:
        validate(tomllib.loads(text), name)
    except ConfigError as exc:
        print(f"self-test FAILED: {name}: unexpectedly rejected: {exc}", file=sys.stderr)
        raise SystemExit(1)
    return 1


def expect_error(name, text, needle=None):
    try:
        validate(tomllib.loads(text), name)
    except ConfigError as exc:
        if needle and needle not in str(exc):
            print(
                f"self-test FAILED: {name}: error did not mention '{needle}': {exc}",
                file=sys.stderr,
            )
            raise SystemExit(1)
        return 1
    except tomllib.TOMLDecodeError:
        return 1
    print(f"self-test FAILED: {name}: unexpectedly accepted", file=sys.stderr)
    raise SystemExit(1)


def run_self_tests(repo_root):
    passed = 0
    passed += expect_ok("valid minimal config", config())
    passed += expect_ok("valid supplied private key", config() + 'private_key = "secret-value"\n')
    passed += expect_ok(
        "valid known_hosts style host_key",
        config(host_key="[vps.example.invalid]:22 " + DUMMY_KEY),
    )

    passed += expect_error("missing tunnel table", 'host = "vps.example.invalid"\n', "tunnel")
    passed += expect_error("missing host", config(omit=("host",)), "host")
    passed += expect_error("missing user", config(omit=("user",)), "user")
    passed += expect_error("missing host_key", config(omit=("host_key",)), "host_key")
    passed += expect_error("missing port", config(omit=("port",)), "port")
    passed += expect_error("port zero", config(port=0), "port")
    passed += expect_error("port too large", config(port=65536), "port")
    passed += expect_error("port not an integer", config().replace("port = 22", 'port = "22"'), "port")
    passed += expect_error("remote_port zero", config(remote_port=0), "remote_port")
    passed += expect_error("remote_port too large", config(remote_port=65536), "remote_port")
    passed += expect_error("remote_port negative", config(remote_port=-1), "remote_port")
    passed += expect_error("host contains a space", config(host="vps example.invalid"), "host")
    passed += expect_error("unknown tunnel field", config() + 'hostname = "typo"\n', "unknown")
    passed += expect_error("extra top-level table", config() + '\n[other]\nvalue = 1\n', "top-level")
    passed += expect_error("host_key is private material", config(host_key="-----BEGIN OPENSSH PRIVATE KEY-----"), "public key")
    passed += expect_error("host_key invalid base64", config(host_key="ssh-ed25519 not-base64!"), "base64")
    passed += expect_error(
        "host_key type mismatch",
        config(host_key="ssh-rsa " + DUMMY_KEY.split()[1]),
        "does not match",
    )
    passed += expect_error("private_key empty", config() + 'private_key = ""\n', "private_key")

    template_path = pathlib.Path(repo_root) / "assets" / "tunnel.toml"
    try:
        with template_path.open("rb") as handle:
            template = tomllib.load(handle)
        table = require_table(template)
        validate(template, str(template_path))
        if "private_key" in table:
            fail("template must not carry a private_key value")
        for value in table.values():
            if isinstance(value, str) and "PRIVATE KEY" in value:
                fail("template contains private key material")
    except (OSError, ConfigError, tomllib.TOMLDecodeError) as exc:
        print(f"self-test FAILED: {template_path}: {exc}", file=sys.stderr)
        raise SystemExit(1)
    passed += 1

    print(f"tunnel config self-test: {passed} checks passed; {template_path} is valid")
    return 0


def main():
    repo_root = sys.argv[1]
    paths = sys.argv[2:]
    if not paths:
        return run_self_tests(repo_root)

    path = pathlib.Path(paths[0])
    try:
        with path.open("rb") as handle:
            data = tomllib.load(handle)
        validate(data, str(path))
    except OSError as exc:
        print(f"test-tunnel-config.sh: {path}: {exc}", file=sys.stderr)
        return 1
    except tomllib.TOMLDecodeError as exc:
        print(f"test-tunnel-config.sh: {path}: invalid TOML: {exc}", file=sys.stderr)
        return 1
    except ConfigError as exc:
        print(f"test-tunnel-config.sh: {path}: {exc}", file=sys.stderr)
        return 1

    print(f"test-tunnel-config.sh: {path}: OK")
    return 0


raise SystemExit(main())
PY
