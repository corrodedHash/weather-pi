# Tasks

## 1. VPS side

- [x] 1.1 Write `scripts/vps-setup.sh` to create the `weatherpi-tunnel` account, install a restricted `authorized_keys` template, and assert `GatewayPorts no`; verify the script is idempotent on a scratch VM
- [x] 1.2 Document port allocation and firewall expectations in `docs/remote-access.md`; verify an unenrolled key is refused and a disallowed port is refused
- [x] 1.3 Add a host-key fingerprint step to the setup script output; verify the fingerprint matches what the device pins

## 2. Device side

- [x] 2.1 Add `weather-pi-tunnel.service` using `ssh -N -T` with keepalives, `ExitOnForwardFailure`, and systemd restart; verify `systemd-analyze verify` and a manual start
- [x] 2.2 Add `/etc/weather-pi/tunnel.toml` (host, port, user, remote port, pinned host key) with a parsing test; verify an invalid config fails closed
- [ ] 2.3 Implement first-boot handling for the tunnel key: generate and export the public half, or install a supplied key with 0600 permissions; verify no key material remains in the image or repository
- [ ] 2.4 Write `known_hosts` from the pinned host key and use `StrictHostKeyChecking=yes`; verify a changed host key prevents the tunnel
- [x] 2.5 Harden device sshd (key-only, no root, `AllowUsers weather-pi`); verify password and root attempts are refused

## 3. Operator workflow

- [x] 3.1 Add `mise run deploy` that rsyncs configuration and assets over ProxyJump, restarts the service, checks `is-active`, and verifies `dpkg-query` reports an unchanged package version; verify it fails cleanly when the tunnel is down
- [x] 3.2 Add `mise run status` that prints tunnel state, application state and restart count, installed and candidate package versions, `apt-daily-upgrade.timer` state, and the tail of the unattended-upgrades log; verify it works with the application stopped and with an update available
- [ ] 3.3 Verify the documented pin/downgrade and `dpkg --configure -a` recovery commands over the tunnel, and confirm no updater CLI or `deploy-updater` task is required
- [x] 3.4 Document the access command, `~/.ssh/config` snippet, configuration deploy, update visibility, downgrade, and recovery procedure in `docs/remote-access.md`; verify the commands run as written and that package traffic bypasses the tunnel

## 4. Verification

- [ ] 4.1 Reboot the device and confirm the tunnel re-establishes unattended; record time to usable port
- [ ] 4.2 Simulate network loss and VPS restart; verify reconnection and that the display keeps running
- [ ] 4.3 Break the application with a test package and recover using only the tunnel and an explicit version pin; record the steps and the resulting `status` output
- [ ] 4.4 Confirm from a second machine that the VPS port is not reachable on the public interface; verify only ProxyJump access succeeds

## Workflow follow-up

- Archive after the recovery drill succeeds using only the tunnel.

## Implementation notes

Local implementation and verification were completed on 2026-11-27. Tasks
2.3 and 2.4 are owned by the separate device first-boot provisioning change,
so they remain unchecked here. Real VPS/device validation remains for the
scratch-VM idempotence check (1.1), unenrolled-key and wrong-port refusal
(1.2), device fingerprint pin match (1.3), a manual tunnel start (2.1),
password/root attempts against the image sshd (2.5), the tunnel recovery drill
(3.3), executing the documented commands end to end (3.4), and all of 4.x.
