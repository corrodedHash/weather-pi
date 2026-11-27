# Tasks

## 1. Origin configuration

- [ ] 1.1 Verify the image's unattended-upgrades fragment allows `origin=weather-pi,archive=trixie` without replacing the distribution's origins, and that `unattended-upgrade --dry-run -d` lists both the distribution origins and the project origin
- [ ] 1.2 Verify a newer `weather-pi` package appears as a candidate in the dry run and an unrelated package is never selected from the project origin
- [ ] 1.3 Confirm `APT::Keep-Downloaded-Packages "true"` retains the installed archive and that a locally edited `/etc/weather-pi/*.toml` survives an upgrade; verify both on a scratch device
- [ ] 1.4 Confirm expired repository metadata is refused with `Valid-Until` enforced and the installed version is unchanged

## 2. Automatic update behaviour

- [ ] 2.1 Publish a newer package and confirm the scheduled unattended run installs it, restarts `weather-pi.service`, and the panel redraws; record the time from publication to installation
- [ ] 2.2 Confirm the scheduled run is a no-op when the published version equals the installed version
- [ ] 2.3 Make the repository unreachable for one run and confirm the installed version and the running service are unaffected and the failure is logged
- [ ] 2.4 Confirm the automatic path never downgrades when only an older version is available

## 3. Operator recovery

- [ ] 3.1 Pin and install the previous retained version with `--allow-downgrades`, preferring the cached archive; verify the service restarts and the panel returns to the previous behaviour
- [ ] 3.2 Reinstall the current version over a deliberately half-unpacked package and complete it with `dpkg --configure -a`; verify the installation is consistent afterwards
- [ ] 3.3 Verify the documented status commands (`dpkg-query`, `apt-cache policy`, `systemctl list-timers apt-daily-upgrade.timer`, `unattended-upgrade --dry-run -d`, the unattended-upgrades log) work with the application stopped
- [ ] 3.4 Simulate a power loss during installation and verify the device boots, the tunnel starts, and the documented recovery completes the package state

## 4. Documentation and decision record

- [ ] 4.1 Write `docs/updating.md` covering discovery, the daily timer, the dry run, logs, pinning and downgrading, conffile behaviour, the lack of automatic rollback, and interrupted-installation recovery; verify every command runs on the device
- [x] 4.2 Record the accepted trade-offs and the rejected wrapper design in the change notes, including the residual replay window and the manual rollback path
- [x] 4.3 Confirm `docs/releasing.md` no longer advertises an updater package or updater CLI (the package cleanup is tracked in `add-release-pipeline`)

## 5. Hardware validation

- [ ] 5.1 Run one automatic update on a Zero and on a Zero 2 W; record the schedule, display output, and log lines
- [ ] 5.2 Perform an operator downgrade and a subsequent automatic re-upgrade on the same device; record the commands and results

## Workflow follow-up

- Archive after an automatic update, a manual downgrade, and a power-loss recovery pass on hardware.

## Status notes

- 4.1 is written but still needs its commands checked on a real device; 4.2-4.3 are complete in the repository. `docs/releasing.md` was checked and has no updater-package or updater-CLI references (no edit was needed).
- Locally verified: shell syntax, shellcheck, the check-script PASS/FAIL tests, and `mise x -- openspec validate --all`.
- Still open: the image build/dry run, timer timing, a real automatic update, and conffile/downgrade/power-loss recovery on a scratch device or hardware (1.x-3.x verification and 5.x).
