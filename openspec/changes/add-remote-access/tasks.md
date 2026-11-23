# Tasks

## 1. VPS side

- [ ] 1.1 Write `scripts/vps-setup.sh` to create the `weatherpi-tunnel` account, install a restricted `authorized_keys` template, and assert `GatewayPorts no`; verify the script is idempotent on a scratch VM
- [ ] 1.2 Document port allocation and firewall expectations in `docs/remote-access.md`; verify an unenrolled key is refused and a disallowed port is refused
- [ ] 1.3 Add a host-key fingerprint step to the setup script output; verify the fingerprint matches what the device pins

## 2. Device side

- [ ] 2.1 Add `weather-pi-tunnel.service` using `ssh -N -T` with keepalives, `ExitOnForwardFailure`, and systemd restart; verify `systemd-analyze verify` and a manual start
- [ ] 2.2 Add `/etc/weather-pi/tunnel.toml` (host, port, user, remote port, pinned host key) with a parsing test; verify an invalid config fails closed
- [ ] 2.3 Implement first-boot handling for the tunnel key: generate and export the public half, or install a supplied key with 0600 permissions; verify no key material remains in the image or repository
- [ ] 2.4 Write `known_hosts` from the pinned host key and use `StrictHostKeyChecking=yes`; verify a changed host key prevents the tunnel
- [ ] 2.5 Harden device sshd (key-only, no root, `AllowUsers weather-pi`); verify password and root attempts are refused

## 3. Operator workflow

- [ ] 3.1 Add `mise run deploy` that rsyncs config and assets over ProxyJump, restarts the service, and checks `is-active`; verify it fails cleanly when the tunnel is down
- [ ] 3.2 Add `mise run status` that prints tunnel state, service state, heartbeat age, and updater status; verify it works over the tunnel
- [ ] 3.3 Document the access command, `~/.ssh/config` snippet, and recovery procedure in `docs/remote-access.md`; verify the commands run as written

## 4. Verification

- [ ] 4.1 Reboot the device and confirm the tunnel re-establishes unattended; record time to usable port
- [ ] 4.2 Simulate network loss and VPS restart; verify reconnection and that the display keeps running
- [ ] 4.3 Break the application with a test release and recover using only the tunnel and the rollback command; record the steps
- [ ] 4.4 Confirm from a second machine that the VPS port is not reachable on the public interface; verify only ProxyJump access succeeds

## Workflow follow-up

- Archive after the recovery drill succeeds using only the tunnel.
