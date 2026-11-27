# Design

## Context

See `proposal.md`. Constraints:

- One device, behind a home NAT, with no inbound ports and no static public address.
- An existing VPS is reachable over SSH and is the natural rendezvous point.
- The device already runs systemd and OpenSSH is part of the base image.
- The update flow can leave the service failing, so remote access must not depend on the application being healthy.
- The image must stay secret-free; credentials are applied at first boot.
- Application packages come from the signed repository (`add-release-pipeline`) and are installed by the device's unattended-upgrades configuration (`add-unattended-upgrades`); the tunnel is for operator actions, not for shipping binaries.

## Goals / Non-Goals

**Goals:**

- Reach the device with one documented command from the operator's machine.
- Keep the attack surface to a single, key-restricted forwarding account on the VPS.
- Recover from a bad package release without touching the SD card.

**Non-Goals:**

- A general-purpose VPN or access to the home LAN.
- Multi-device inventory, Ansible, or a jump-host web UI (one device).
- Exposing the SSH port on the VPS's public interface.
- Proxying package downloads through the VPS; the device fetches from the repository directly.

## Decisions

### Reverse SSH tunnel over WireGuard or Tailscale

The operator chose an SSH reverse tunnel; it reuses the VPS account model and needs no third-party coordination service. Trade-offs are real: SSH forwarding is more fragile than WireGuard and the VPS sees (but cannot decrypt) the session. Alternatives:

- **WireGuard**: better reconnect behavior and a real interface, but needs key distribution, a server config, and firewall rules. Worth revisiting if a second device appears.
- **Tailscale**: least maintenance but adds a third-party dependency and an account.

### Plain `ssh` under systemd instead of autossh

Use `ssh -N -T` with `ExitOnForwardFailure=yes`, `ServerAliveInterval=30`, `ServerAliveCountMax=3`, and `Restart=always`. systemd already supervises the process, and OpenSSH exits on a dead peer when keepalives fail. This removes the extra `autossh` package and its stale-connection heuristics. `RestartSec=15` with a start limit prevents a tight loop while the network is down.

### Bind to VPS loopback and access through ProxyJump

The remote forward is `127.0.0.1:${remote_port}:localhost:22`. The VPS keeps `GatewayPorts no`, so the port is never exposed publicly. Operators connect with:

```
ssh -J vps.example.org weather-pi@127.0.0.1 -p 2201
```

and can put that in `~/.ssh/config` as `Host weather-pi`. Alternative: `GatewayPorts clientspecified` plus a firewall rule. Rejected because a misconfigured client would expose the device to the internet.

### Dedicated VPS account with a restricted key

Create `weatherpi-tunnel` with `/usr/sbin/nologin`, no password, and an `authorized_keys` entry:

```
restrict,port-forwarding,permitlisten="127.0.0.1:2201" ssh-ed25519 AAAA... weatherpi-<serial>
```

`restrict` disables pty, agent, X11, and exec; `permitlisten` pins the only port. `AllowTcpForwarding` stays enabled for the account. Each device gets its own port so the model extends to a second device without redesign.

### Device key lifecycle

Preferred: generate an ed25519 key on the device during first boot, write the public half to `/boot/firmware/weather-pi-tunnel.pub`, and have the operator enroll it. For zero-touch provisioning, the provisioning file may carry a pre-generated private key; that key is treated as a secret exactly like the WiFi passphrase and is removed from the boot partition after first boot.

The key lives at `/etc/weather-pi/tunnel_key` (0600). It is never in the image or repository.

### Pin the VPS host key

The provisioning file carries the VPS host public key (or its fingerprint). First boot writes `known_hosts` and the unit uses `StrictHostKeyChecking=yes`. A VPS rebuild requires updating this value deliberately; failing closed is the point.

### Device SSH configuration

`PasswordAuthentication no`, `PermitRootLogin no`, `AllowUsers weather-pi`, and `authorized_keys` from provisioning. The tunnel account on the VPS is the only way in from outside; LAN access remains possible for initial setup and rescue.

### Deploy configuration over the tunnel; observe and recover packages through apt

`mise run deploy` uses `rsync -e "ssh -J ..."` for `/etc/weather-pi/*.toml` and assets, then `systemctl restart weather-pi`, then checks `is-active`. It never writes `/usr/bin` or installs packages: the binary is owned by dpkg, and replacing it out of band would leave `dpkg` and `status` lying about the installed version.

Application updates are applied on the device by `unattended-upgrades`; the tunnel is used only to observe and intervene:

```
ssh weather-pi 'apt-cache policy weather-pi'                                    # installed vs candidate
ssh weather-pi 'sudo apt-get install --allow-downgrades weather-pi=<version>'   # pin an older release
ssh weather-pi 'sudo dpkg --configure -a'                                       # finish an interrupted install
ssh weather-pi 'sudo systemctl restart weather-pi'                              # restart without changing versions
```

Ansible would add inventory, templating, and idempotence for a single host that already has standard apt commands; defer it.

### Status output

`mise run status` collects, in one SSH invocation: tunnel unit state, application unit state and restart count, `dpkg-query -W weather-pi`, `apt-cache policy weather-pi`, `systemctl list-timers apt-daily-upgrade.timer`, and the tail of `/var/log/unattended-upgrades/unattended-upgrades.log`. It is read-only and must work when the application is stopped.

### Update traffic does not use the tunnel

The device pulls packages from the HTTPS repository directly; the tunnel carries only operator SSH sessions. This keeps the tunnel load irrelevant to update speed, avoids VPS bandwidth, and means a tunnel outage does not block an update. The reverse also holds: an update failure cannot break the tunnel, because the tunnel unit is independent of the application and apt.

## Risks / Trade-offs

- **VPS compromise** → the tunnel account can only forward one port; the device key is separate from admin keys; rotate the tunnel key by re-enrolling. The VPS still sees metadata.
- **Tunnel flapping drains the battery/CPU** → keepalive interval plus `RestartSec` backoff and a start limit.
- **Port collision on the VPS** → one port per device, documented in `docs/remote-access.md`; check with `ss -ltnp` during enrollment.
- **Host key pin blocks recovery after a VPS rebuild** → document the update procedure (edit the provisioning value and re-run first boot or update `/etc/ssh/known_hosts` over the console).
- **SD card replacement loses the tunnel key** → re-enroll from the new public key; the image does not carry identity.
- **SSH forwarding is slower than WireGuard** → acceptable for configuration and rescue; package downloads bypass it.
- **Operator runs `deploy` while an update is in progress** → deploy only touches configuration and restarts; wait for the daily apt run to finish when changing configuration, and document restarting afterwards.
- **Manual `apt-get` on the device drifts from the image version** → `build-info` records the image baseline; `status` shows the installed version, which is the source of truth.

## Migration Plan

1. Create the VPS account and firewall state with `scripts/vps-setup.sh`.
2. Boot the device with the provisioning file containing the VPS host and pinned host key; enroll the generated tunnel public key.
3. Confirm `ssh -J ... weather-pi@127.0.0.1 -p 2201` works, shows the installed version and apt candidate, and shows the enabled `apt-daily-upgrade.timer`.
4. Deploy a harmless config change through `mise run deploy` and confirm the service restarts.
5. Confirm a published package is installed by unattended-upgrades, then pin the previous version over the tunnel and confirm recovery.
6. Keep LAN access documented as the fallback.

## Open Questions

- Whether the VPS account should use a non-standard SSH port; decide when setting it up and record it in `docs/remote-access.md`.
