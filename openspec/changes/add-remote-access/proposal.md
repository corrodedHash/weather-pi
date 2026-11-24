# Proposal

## Why

Once the device is on a wall behind NAT there is no way to reach it, change its configuration, or recover from a failed update without pulling the SD card. A persistent outbound tunnel gives the operator a stable entry point without opening anything on the home network.

## What Changes

- Run a reverse SSH tunnel from the device to the VPS, exposing the device's SSH service on a port bound to the VPS loopback interface.
- Supervise the tunnel with systemd so it reconnects after network loss, VPS restart, or device reboot.
- Keep tunnel credentials per device: generate the tunnel key on the device (or accept a key supplied in the provisioning file) and require a one-time enrollment on the VPS.
- Pin the VPS host key so the device does not connect to an impostor.
- Harden both ends: dedicated VPS user, `restrict,port-forwarding,permitlisten=...` authorized key, key-only SSH on the device, no password or root login.
- Add `mise run deploy` to push configuration and assets over the tunnel with rsync and restart the service, and `mise run status` to inspect it.
- Document VPS setup, enrollment, access commands, and the recovery procedure.

## Capabilities

### New Capabilities

- `remote-access`: a persistent, authenticated outbound tunnel plus the operator workflow for deploying configuration and recovering the device.

### Modified Capabilities

<!-- None: the tunnel does not change application behavior. -->

## Impact

- New: `assets/weather-pi-tunnel.service`, `/etc/weather-pi/tunnel.toml` template, `scripts/vps-setup.sh`, `docs/remote-access.md`, mise `deploy`/`status` tasks
- Image changes: install `openssh-client`, enable the tunnel unit, pass tunnel settings through first-boot provisioning
- Requires an existing VPS with SSH access; Ansible is deliberately not introduced for one device
