# Tasks

## 1. Application readiness contract

- [ ] 1.1 Add `sd_notify` readiness and watchdog pings to the application after display initialisation and in the main loop; verify `systemctl status weather-pi` shows `Ready` and no watchdog resets over an hour
- [ ] 1.2 Change `weather-pi.service` to `Type=notify` with `WatchdogSec=60` and a generous `TimeoutStartSec`; verify `systemd-analyze verify` and that killing the loop makes systemd restart the unit
- [ ] 1.3 Remove any planned heartbeat file and writable state path from the application unit; verify the service works with `ProtectSystem=strict` and no `ReadWritePaths`

## 2. Updater package and apt configuration

- [ ] 2.1 Implement `/usr/sbin/weather-pi-update` with `--check`, `--apply`, `--status`, and `--rollback`, using only fixed `apt-get`/`apt-cache`/`dpkg-query`/`systemctl` invocations; verify `shellcheck` is clean and every mode exits non-zero on an unreachable repository
- [ ] 2.2 Add `/etc/apt/sources.list.d/weather-pi.list` with `signed-by=`, the `o=weather-pi` pin, `Acquire::Check-Valid-Until "true"`, and `APT::Keep-Downloaded-Packages "true"`; verify `apt-get update` fails closed when the key is removed
- [ ] 2.3 Write the state file atomically (`write` + `fsync` + `rename`) and treat it as informational only; verify a truncated state file yields "no last-good version" instead of a failed run
- [ ] 2.4 Package the wrapper, units, apt configuration, and keyring reference as `weather-pi-updater` with a dependency on `apt`; verify `apt install ./weather-pi-updater_*.deb` installs and `dpkg -V` is clean

## 3. Health gate and rollback

- [ ] 3.1 Implement the upgrade sequence (lock, installed version, update, candidate check, install with `--force-confdef --force-confold`, restart, wait); verify a normal upgrade from the previous version succeeds and records last-good
- [ ] 3.2 Implement the health window against `is-active` plus the watchdog; verify a deliberately hung build is rolled back automatically
- [ ] 3.3 Implement `--rollback` preferring `/var/cache/apt/archives` and falling back to `--allow-downgrades` from the repository; verify it is idempotent and refuses without a last-good record
- [ ] 3.4 Verify the wrapper never upgrades or downgrades `weather-pi-updater` and that only `weather-pi` appears in its apt candidate handling

## 4. Units, scheduling, and recovery

- [ ] 4.1 Add `weather-pi-update.service` (`Type=oneshot`, network-online ordering, `DPkg::Lock::Timeout=120`, flock) and `.timer` (daily, `RandomizedDelaySec=6h`, `Persistent=true`); verify `systemd-analyze verify`, a manual start, and that a second concurrent start exits without changes
- [ ] 4.2 Add `weather-pi-recover.service` ordered `Before=weather-pi.service` that runs `dpkg --configure -a` only when a pending journal exists; verify a simulated interrupted install is completed before the application starts
- [ ] 4.3 Exclude the `weather-pi` origin from `unattended-upgrades`; verify a simulated unattended run does not change the installed application version

## 5. Operations and documentation

- [ ] 5.1 Write structured log output and `--status` for use over SSH, printing installed, available, last-good, last result, and last check time; verify output contains no secrets and works while the service is stopped
- [ ] 5.2 Document the update lifecycle, rollback, replay-window limitation, state file, and recovery in `docs/updating.md`; verify every documented command runs on the device
- [ ] 5.3 Document the explicit updater-package upgrade path over the tunnel (or `mise run deploy-updater`); verify it upgrades only `weather-pi-updater`

## 6. Integration on hardware

- [ ] 6.1 Publish a newer package, let the timer update, and confirm version change, panel redraw, and a clean `--status`
- [ ] 6.2 Publish a crashing package to a staging repository, confirm automatic rollback, then confirm a manual `--rollback` restores the same version
- [ ] 6.3 Cut power during the install step and confirm the device boots into a working version after journal recovery
- [ ] 6.4 Measure idle memory and disk growth on a Pi Zero; record the numbers in the change notes

## Workflow follow-up

- Archive after the end-to-end update, rollback, and power-loss runs on hardware.
