# Tasks

## 1. Toolchain and task runner

- [ ] 1.1 Add `rust-toolchain.toml` pinning a dated nightly that compiles the current code; verify `rustup show active-toolchain` reports it inside the repo
- [ ] 1.2 Add `mise.toml` with `check`, `build:armv6`, `build:arm64`, `package`, `repo`, and `sim` tasks and pinned `cross`/`cargo-deb`/`dpkg-dev`/`apt-ftparchive`/`gpg`/`minisign` tools plus `npm:@fission-ai/openspec@2.1.1`; verify `mise run check` and `mise x -- openspec --version` both work from a clean shell
- [ ] 1.3 Replace `build.sh` with a thin wrapper around the mise tasks (or delete it) and verify `mise run build:armv6` produces `target/arm-unknown-linux-gnueabihf/release/weather-pi`
- [ ] 1.4 Document the toolchain and task workflow in `README.md`; verify the documented commands work verbatim

## 2. Version and packaging fixes

- [ ] 2.1 Compile the version in from `WEATHER_PI_VERSION`/`git describe` and implement `--version`; verify `weather-pi --version` prints the tag and target triple on both targets
- [ ] 2.2 Fix `assets/weather-pi.service` (app argument, non-root user, `spi`/`gpio` groups, no `chrt`); verify `systemd-analyze verify assets/weather-pi.service` is clean
- [ ] 2.3 Fix `assets/greeter.toml` to `watched_ips` and add a config parse test that loads every sample file; verify `cargo test` fails on a knowingly broken sample
- [ ] 2.4 Move config lookup to `/etc/weather-pi` with a `/etc/skyscreen` fallback and a deprecation log; verify both paths load on the simulator

## 3. Package build

- [ ] 3.1 Add `packaging/weather-pi/` metadata for `cargo-deb` (name, architecture mapping, unit, assets, config conffiles) and verify `mise run package` produces a `.deb` whose `dpkg-deb -c` listing matches the documented layout
- [ ] 3.2 Map `vX.Y.Z` to upstream `X.Y.Z` and Debian revision `-1`, and implement the strict-greater version check with `dpkg --compare-versions`; verify a repeated or lower version is refused
- [ ] 3.3 Add `packaging/weather-pi-updater/` and `packaging/keyring/` metadata for the updater and archive keyring packages; verify all three packages install together with `apt install ./...` on a scratch container
- [ ] 3.4 Verify the installed `weather-pi` package starts the service and that `dpkg -V weather-pi` is clean after install

## 4. Repository generation and signing

- [ ] 4.1 Write `scripts/apt-repo.sh` that pools packages, generates `Packages{,.gz}` for `binary-armhf` and `binary-arm64`, and writes `Release` with `Origin`, `Suite`, `Codename`, `Valid-Until` (seven days), and `Acquire-By-Hash: yes`; verify the generated `Release` contains all documented fields
- [ ] 4.2 Sign `Release` into `InRelease` with the archive key and upload `InRelease` last; verify `apt-get update` succeeds against a local HTTP server and fails after a one-byte edit to `Packages`
- [ ] 4.3 Enforce retention of the five newest versions per architecture and prune the rest; verify the index lists exactly five and an older version is refused
- [ ] 4.4 Document the key ceremony, protected-environment setup, and rotation through the keyring package in `docs/releasing.md`; verify a second key can be added and trusted without reflashing

## 5. CI publication

- [ ] 5.1 Add `.github/workflows/release.yml` triggered by `v*` tags that runs checks, builds both architectures in parallel, and builds all three packages; verify a draft tag on a fork produces artifacts and no publication on a failing check
- [ ] 5.2 Add the publication step that pushes the regenerated repository tree to the `apt` branch and attaches packages, metadata, and `SHA256SUMS` to the GitHub Release only after checks and signing succeed; verify the release page and Pages URL list exactly those files
- [ ] 5.3 Document cutting a release end to end in `docs/releasing.md`; verify a maintainer can follow it on a scratch tag

## 6. Integration check

- [ ] 6.1 On a scratch Raspberry Pi OS armhf container, add the repository with `signed-by`, install `weather-pi`, and verify `--version`; repeat with `arm64`
- [ ] 6.2 Install the previous version and downgrade with `--allow-downgrades`; verify the service restarts on the older package
- [ ] 6.3 Confirm the packaged unit starts the greeter on a real Pi with `/etc/weather-pi/greeter.toml` and with the legacy path

## Workflow follow-up

- Archive the change after review and a successful `v0.2.0` publication.
