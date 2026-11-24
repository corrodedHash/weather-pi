# Proposal

## Why

The device sits on a wall with no keyboard, so shipping a code change currently means pulling the SD card. Remote updates require a mechanism that cannot be tricked into installing unsigned or corrupted software, and that cannot leave the device dead if a new build is bad. Putting that mechanism inside the application binary couples the recovery path to the thing being updated, so the updater must be part of the image instead.

## What Changes

- Update the application from the project's signed apt repository; the package metadata is the trust anchor, so no custom signature verification code is needed.
- Ship the updater as its own image-resident Debian package (`weather-pi-updater`), separate from the application package, so a broken application release can never break the update or recovery path.
- Keep the application binary free of update logic, network clients, and writable state; it only reports liveness through the systemd notification protocol.
- Gate each update on a health check: install, restart, require the service to become active and keep pinging the systemd watchdog, otherwise downgrade to the previous package automatically.
- Keep the previously installed package available (`APT::Keep-Downloaded-Packages`) and accept explicit operator downgrades, but never downgrade automatically except during rollback.
- Bound metadata replay with a short `Valid-Until` window and apt's default refusal to downgrade; document the residual risk instead of adding a sequence counter.
- Run checks on a systemd timer with randomized delay, a lock, and network-online ordering.
- Add `weather-pi-update --check`, `--status`, and `--rollback` for diagnosis and recovery over SSH.
- Recover from an interrupted dpkg run at boot before the application starts.
- Document the update lifecycle; Debian package security updates remain with `unattended-upgrades`, and this updater never touches them.

## Capabilities

### New Capabilities

- `auto-update`: signed-package, health-gated, rollback-capable application updates driven by an image-resident updater that is independent of the application.

### Modified Capabilities

<!-- None: the display applications' behavior is unchanged except for the systemd readiness notification, which is an implementation detail of the health contract. -->

## Impact

- New: `packaging/weather-pi-updater/` (wrapper script, units, apt source, keyring reference, preferences), `docs/updating.md`
- `assets/weather-pi.service` gains `Type=notify` and `WatchdogSec`; the application gains a small `sd_notify` dependency and nothing else
- New state under `/var/lib/weather-pi` for the last good version and last result
- Consumes the repository, packages, and keyring from `add-release-pipeline`
- Requires the keyring, sources list, and pinning shipped by `add-device-image`
- `add-remote-access` recovery and status commands call the updater CLI instead of a binary subcommand
