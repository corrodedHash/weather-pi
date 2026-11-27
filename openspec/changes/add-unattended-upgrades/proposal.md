# Proposal

## Why

The device sits on a wall with no keyboard, so shipping a code change currently means pulling the SD card. Updates must arrive from a source the device already trusts and must not require custom update code, a second package, or another long-running service on a Pi Zero.

## What Changes

- Serve the application from the project's signed apt repository and let Debian's `unattended-upgrades` install newer `weather-pi` packages automatically.
- Add the `weather-pi` origin to the allowed origins so the application and the archive keyring update through the same standard mechanism as Debian security packages.
- Ship the archive keyring, `signed-by` source, origin pin, `Valid-Until` enforcement, and download cache in the image; no updater package, shell wrapper, update timer, or recovery unit.
- Accept the trade-off: no health gate and no automatic rollback. A bad release is recovered by an operator pinning a retained previous version over SSH.
- Keep the application binary free of update logic; it only draws to the panel and is restarted by its package.
- Document discovery, logs, verification, downgrade, and recovery.

## Capabilities

### New Capabilities

- `auto-update`: signed-package updates of the application through Debian's standard unattended upgrade path, with operator-controlled recovery.

### Modified Capabilities

<!-- None: the application and display behaviour are unchanged. -->

## Impact

- New: `docs/updating.md`.
- Uses the packages, repository, keyring, and retained versions from `add-release-pipeline`; the image (`add-device-image`) owns the apt and unattended-upgrades configuration.
- Removes the planned `weather-pi-updater` package from the package set; no new binary, unit, or state directory.
- Image changes: install `unattended-upgrades`, allow the project origin, keep the download cache; drop the updater, its timer, and the recovery unit.
- Remote access (`add-remote-access`) recovery and status use standard `apt`, `dpkg`, and `systemctl` commands instead of an updater CLI.
