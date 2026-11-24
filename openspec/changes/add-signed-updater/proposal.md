# Proposal

## Why

The device sits on a wall with no keyboard, so shipping a code change currently means pulling the SD card. Updating it remotely requires a mechanism that cannot be tricked into installing an unsigned or corrupted binary, and that cannot leave the device dead if a new build is bad.

## What Changes

- Add a `weather-pi update` subcommand that checks for, verifies, installs, and rolls back application updates.
- Verify a detached signature over the release manifest with a public key embedded at build time (with room for a second key during rotation).
- Enforce a monotonic sequence number so an attacker cannot replay an older, validly signed release.
- Install atomically: verify first, write a temporary file, rename over the current binary, restart the service, then health-check and roll back automatically on failure.
- Run checks on a systemd timer with jitter, and expose `--check`, `--status`, and `--rollback` for manual use.
- Add a heartbeat the application writes after successful start, used by the health check.
- Document the update lifecycle and failure modes; OS security updates remain with `unattended-upgrades`.

## Capabilities

### New Capabilities

- `auto-update`: cryptographically verified, atomic, rollback-capable in-place updates of the weather-pi binary.

### Modified Capabilities

<!-- None: the display applications' behavior is unchanged except for the heartbeat write, which is an implementation detail of the update contract. -->

## Impact

- New `src/update/` module and CLI flags; new `weather-pi-update.service` and `.timer`; new state under `/var/lib/weather-pi`
- Consumes `manifest.json` from `add-release-pipeline`
- Requires the release public key in the image (from `add-device-image`)
- Adds `minisign-verify` (or equivalent) and an HTTP client dependency; update checks must remain usable on a Pi Zero with limited memory
