# Proposal

## Why

The binary is currently produced by an unpinned `build.sh` that assumes a nightly toolchain the repository never declares, so a fresh checkout fails to build on the default stable compiler. There is also no version stamp, no checksum, and no signature, which means the image and the device have no trustworthy artifact to install, verify, or roll back to.

## What Changes

- Pin the required nightly Rust toolchain in the repository and drive builds through mise tasks.
- Stamp the binary with a version derived from the git tag and expose it via `--version`.
- Package the application as a Debian package (`weather-pi`) for `armhf` and `arm64`.
- Publish a signed apt repository (`InRelease`/`Packages`) so the disk image and the device install and verify the same artifact through one standard trust path.
- Keep the previous published versions in the repository pool so an operator can downgrade deliberately.
- Publish a `weather-pi-archive-keyring` package so the repository signing key can be rotated without reflashing.
- Emit a `SHA256SUMS` file over the packages for archival and for the image build's independent check.
- Run checks, package builds, and repository publication in GitHub Actions on `v*` tags, with Debian-version monotonicity enforced before publication.
- Fix the shipped systemd unit and sample configs so an installed release actually starts (the unit passes no app argument today, and `greeter.toml` uses `watched_ip` where the struct expects `watched_ips`).
- **BREAKING**: canonical install paths move from `/etc/skyscreen` and `/usr/share/skyscreen` to `/etc/weather-pi` and `/usr/share/weather-pi`; the old paths are read as a fallback for one release.

## Capabilities

### New Capabilities

- `release-pipeline`: reproducible toolchain and builds, version reporting, signed Debian packages, a signed apt repository with retained rollback versions, and the task/CI workflow that publishes them.

### Modified Capabilities

<!-- None: this change introduces the first spec-level capability for building and publishing releases. -->

## Impact

- `Cargo.toml`, `src/main.rs`, `assets/weather-pi.service`, `assets/greeter.toml`, `build.sh`
- New: `rust-toolchain.toml`, `mise.toml`, `packaging/weather-pi/`, `packaging/keyring/`, `scripts/apt-repo.sh`, `.github/workflows/release.yml`, `docs/releasing.md`
- Dev dependencies: `cross`, `cargo-deb`, `dpkg-dev`, `apt-ftparchive`, `gnupg` (all via mise)
- Adds a `--version` CLI flag; no other runtime behavior changes
- GitHub Pages (or equivalent static hosting) serves the apt repository; the signing key is held in a protected CI environment
