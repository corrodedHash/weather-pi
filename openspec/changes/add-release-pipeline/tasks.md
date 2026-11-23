# Tasks

## 1. Toolchain and task runner

- [ ] 1.1 Add `rust-toolchain.toml` pinning a dated nightly that compiles the current code; verify `rustup show active-toolchain` reports it inside the repo
- [ ] 1.2 Add `mise.toml` with `check`, `build:armv6`, `build:aarch64`, and `sim` tasks and pinned `cross`/`minisign`/`jq` tools plus `npm:@fission-ai/openspec@2.1.1`; verify `mise run check` and `mise x -- openspec --version` both work from a clean shell
- [ ] 1.3 Replace `build.sh` with a thin wrapper around the mise tasks (or delete it) and verify `mise run build:armv6` produces `target/arm-unknown-linux-gnueabihf/release/weather-pi`
- [ ] 1.4 Document the toolchain and task workflow in `README.md`; verify the documented commands work verbatim

## 2. Version and packaging fixes

- [ ] 2.1 Compile the version in from `WEATHER_PI_VERSION`/`git describe` and implement `--version`; verify `weather-pi --version` prints the tag and target triple on both targets
- [ ] 2.2 Fix `assets/weather-pi.service` (app argument, non-root user, `spi`/`gpio` groups, no `chrt`); verify `systemd-analyze verify assets/weather-pi.service` is clean
- [ ] 2.3 Fix `assets/greeter.toml` to `watched_ips` and add a config parse test that loads every sample file; verify `cargo test` fails on a knowingly broken sample
- [ ] 2.4 Move config lookup to `/etc/weather-pi` with a `/etc/skyscreen` fallback and a deprecation log; verify both paths load on the simulator

## 3. Release artifacts and signing

- [ ] 3.1 Implement the release task: build both targets, produce `.tar.gz` archives, emit `manifest.json`, and write `SHA256SUMS`; verify a local run produces all files with matching hashes
- [ ] 3.2 Add a `sign` task using minisign over `manifest.json`; verify `minisign -Vm manifest.json -p <pubkey>` succeeds and fails after a one-byte edit
- [ ] 3.3 Define the manifest schema in `docs/releasing.md` (`schema_version`, `version`, `seq`, `channel`, `artifacts[]`); verify a generated manifest validates with `jq` and matches the documented fields
- [ ] 3.4 Document the offline signing ceremony and key rotation (public-key list); verify a second key can be added to the verifier without code changes

## 4. CI publication

- [ ] 4.1 Add `.github/workflows/release.yml` triggered by `v*` tags that runs checks and builds both targets in parallel; verify a draft tag on a fork produces artifacts and no release on a failing check
- [ ] 4.2 Add the publish step that uploads binaries, `manifest.json`, signature, and `SHA256SUMS` only after checks and signing succeed; verify the release page lists exactly those assets
- [ ] 4.3 Document cutting a release end to end in `docs/releasing.md`; verify a maintainer can follow it on a scratch tag

## 5. Integration check

- [ ] 5.1 Run the full flow from a clean clone: `mise install`, `mise run check`, `mise run release`, sign, and verify; record the result in the change notes
- [ ] 5.2 Confirm the packaged unit starts the greeter on a real Pi with `/etc/weather-pi/greeter.toml` and with the legacy path

## Workflow follow-up

- Archive the change after review and a successful `v0.2.0` release.
