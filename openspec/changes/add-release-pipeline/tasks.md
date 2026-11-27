# Tasks

## 1. Toolchain and task runner

- [x] 1.1 Add `rust-toolchain.toml` pinning a dated nightly that compiles the current code; verify `rustup show active-toolchain` reports it inside the repo
- [x] 1.2 Add `mise.toml` with `check`, `build:armv6`, `build:arm64`, `package`, `repo`, and `sim` tasks and pinned `cross`/`cargo-deb`/`dpkg-dev`/`apt-ftparchive`/`gpg`/`minisign` tools plus `npm:@fission-ai/openspec@2.1.1`; verify `mise run check` and `mise x -- openspec --version` both work from a clean shell
- [x] 1.3 Replace `build.sh` with a thin wrapper around the mise tasks (or delete it); the wrapper is present and syntax-checked (the cross build itself needs Docker)
- [x] 1.4 Document the toolchain and task workflow in `README.md`; verify the documented commands work verbatim

## 2. Version and packaging fixes

- [x] 2.1 Compile the version in from `WEATHER_PI_VERSION`/`git describe` and implement `--version`; verify `weather-pi --version` prints the tag and target triple on both targets
- [x] 2.2 Fix `assets/weather-pi.service` (app argument, non-root user, `spi`/`gpio` groups, no `chrt`); verify `systemd-analyze verify assets/weather-pi.service` is clean
- [x] 2.3 Fix `assets/greeter.toml` to `watched_ips` and add a config parse test that loads every sample file; verify `cargo test` fails on a knowingly broken sample
- [x] 2.4 Move config lookup to `/etc/weather-pi` with a `/etc/skyscreen` fallback and a deprecation log; verify both paths load on the simulator

## 3. Package build

- [x] 3.1 Add `packaging/weather-pi/` metadata for `cargo-deb` (name, architecture mapping, unit, assets, config conffiles) and verify `mise run package` produces a `.deb` whose `dpkg-deb -c` listing matches the documented layout
- [x] 3.2 Map `vX.Y.Z` to upstream `X.Y.Z` and Debian revision `-1`, and implement the strict-greater version check with `dpkg --compare-versions`; verify a repeated or lower version is refused
- [x] 3.3 Reduce packaging to `weather-pi` and `weather-pi-archive-keyring`: remove `packaging/weather-pi-updater/`, its build step, the pin entry, and CI/docs references; verified no updater package/CLI/build step remains and both packages build for the host with `scripts/test-package.sh` (scratch-container install is 6.1)
- [ ] 3.4 Verify the installed `weather-pi` package starts the service and that `dpkg -V weather-pi` is clean after install; locally verified the packaged `md5sums` index and contents with `scripts/test-package.sh`, but the real install/service start remains 6.3

## 4. Repository generation and signing

- [x] 4.1 Write `scripts/apt-repo.sh` that pools packages, generates `Packages{,.gz}` for `binary-armhf` and `binary-arm64`, and writes `Release` with `Origin`, `Suite`, `Codename`, `Valid-Until` (seven days), and `Acquire-By-Hash: yes`; verify the generated `Release` contains all documented fields
- [x] 4.2 Sign `Release` into `InRelease` with the archive key and upload `InRelease` last; verify `apt-get update` succeeds against a local HTTP server and fails after a one-byte edit to `Packages`
- [x] 4.3 Enforce retention of the five newest versions per architecture and prune the rest; verify the index lists exactly five and an older version is refused
- [x] 4.4 Document the key ceremony, protected-environment setup, and rotation through the keyring package in `docs/releasing.md`; verify a second key can be added and trusted without reflashing

## 5. CI publication

- [ ] 5.1 Add `.github/workflows/release.yml` triggered by `v*` tags that runs checks, builds both architectures in parallel, and builds both packages; the workflow exists and is YAML-validated, but a real tag/fork run is still pending
- [ ] 5.2 Add the publication step that pushes the regenerated repository tree to the `apt` branch and attaches packages, metadata, and `SHA256SUMS` to the GitHub Release only after checks and signing succeed; implemented and covered by local repository checks, but a real Pages/Release run is still pending
- [x] 5.3 Document cutting a release end to end in `docs/releasing.md`, including local package/repository verification and scratch-host integration commands

## 6. Integration check

- [ ] 6.1 On a scratch Raspberry Pi OS armhf container, add the repository with `signed-by`, install `weather-pi`, and verify `--version`; repeat with `arm64`
- [ ] 6.2 Install the previous version and downgrade with `--allow-downgrades`; verify the service restarts on the older package
- [ ] 6.3 Confirm the packaged unit starts the greeter on a real Pi with `/etc/weather-pi/greeter.toml` and with the legacy path

## Workflow follow-up

- Archive the change after review and a successful `v0.2.0` publication.

## Verification notes

- Locally verified with `scripts/test-package.sh` and
  `scripts/test-release-pipeline.sh`: host package contents (`dpkg-deb -I/-c/-e`,
  `md5sums`, maintainer scripts), `systemd-analyze verify` under a temporary
  root, `weather-pi --version`, signed repository generation, `gpgv`
  verification, `by-hash` files, and five-version retention in Debian order.
- Docker is unavailable in this environment, so 1.3/3.3 cross builds and
  container installs, 3.4 real install/service start, 5.1-5.2 real
  tag/Pages/Release runs, and all of section 6 were not executed. The workflow
  was syntax/YAML checked and the repository generation/retention logic was
  exercised locally with dummy packages, but CI itself was not run.
