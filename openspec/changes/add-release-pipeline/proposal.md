# Proposal

## Why

The binary is currently produced by an unpinned `build.sh` that assumes a nightly toolchain the repository never declares, so a fresh checkout fails to build on the default stable compiler. There is also no version stamp, no checksum, and no signature, which means the image and the auto-updater have no trustworthy artifact to install or verify.

## What Changes

- Pin the required nightly Rust toolchain in the repository and drive builds through mise tasks.
- Stamp the binary with a version derived from the git tag and expose it via `--version`.
- Build release binaries for `arm-unknown-linux-gnueabihf` (Pi Zero, Zero W) and `aarch64-unknown-linux-gnu` (Zero 2 W).
- Publish a signed release manifest containing each artifact's target, URL, SHA-256, size, and a monotonic sequence number.
- Run checks, builds, and publication in GitHub Actions on `v*` tags.
- Fix the shipped systemd unit and sample configs so an installed release actually starts (the unit passes no app argument today, and `greeter.toml` uses `watched_ip` where the struct expects `watched_ips`).
- **BREAKING**: canonical install paths move from `/etc/skyscreen` and `/usr/share/skyscreen` to `/etc/weather-pi` and `/usr/share/weather-pi`; the old paths are read as a fallback for one release.

## Capabilities

### New Capabilities

- `release-pipeline`: reproducible toolchain and builds, version reporting, signed release manifest, and the task/CI workflow that publishes them.

### Modified Capabilities

<!-- None: this change introduces the first spec-level capability for building and publishing releases. -->

## Impact

- `Cargo.toml`, `src/main.rs`, `assets/weather-pi.service`, `assets/greeter.toml`, `build.sh`
- New: `rust-toolchain.toml`, `mise.toml`, `.github/workflows/release.yml`, `docs/releasing.md`
- Dev dependencies: `cross`, `minisign`, `jq` (all via mise)
- Adds a `--version` CLI flag; no other runtime behavior changes
