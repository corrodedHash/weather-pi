# Remote access

The device sits behind a home NAT and has no inbound port. It keeps an
outbound SSH connection to a small VPS, and the VPS exposes the device's sshd
on a port bound to its loopback interface. The operator reaches that port
through `ProxyJump`; nothing on the home network or the VPS public interface is
opened.

```
operator ──ssh──▶ vps.example.org:22 ──ssh forwarding──▶ 127.0.0.1:2201
                                                              │
                                                              ▼
                                                    device sshd :22
```

The tunnel is supervised by `weather-pi-tunnel.service`. It is independent of
the display application, so a bad application release can be inspected and
recovered without pulling the SD card. Application packages still come from the
signed apt repository directly; they do **not** travel through the tunnel.

## VPS prerequisites

- A Debian 12/13 or Ubuntu 22.04/24.04 VPS with systemd and OpenSSH server.
- Root or passwordless sudo on the VPS.
- A DNS name (or stable address) for the VPS, reachable from the device.
- The operator's own SSH key already installed for the administrative account.
  The tunnel account is separate and is not used for VPS administration.
- One TCP port per device on the VPS loopback interface. No firewall opening is
  needed for that port.

The setup script is `scripts/vps-setup.sh`. Run it on the VPS from a clone or a
copy of this repository. It is idempotent and supports `--dry-run`.

## Port allocation and firewall

Allocate a distinct loopback port for every device, for example:

| Device | VPS loopback port | VPS authorized key comment |
| ------ | ----------------- | -------------------------- |
| pi-01  | 2201              | `weatherpi-pi-01`          |
| pi-02  | 2202              | `weatherpi-pi-02`          |

Use an unprivileged port (1024–65535) that is not used by another service. The
`permitlisten` option in the device's `authorized_keys` line pins that port, so
a compromised or misconfigured device cannot forward a different port.

The forwarding account is `weatherpi-tunnel` with `/usr/sbin/nologin`; it cannot
run commands, allocate a pty, or use agent/X11 forwarding. `restrict` plus
`port-forwarding` allows exactly the reverse forwarding needed by the tunnel.

`GatewayPorts no` is enforced by the script. A remote forward therefore binds
`127.0.0.1` only, even if a client asks for a public bind. Do not add
`GatewayPorts yes` or `clientspecified` anywhere.

Firewall expectations:

- Allow SSH to the VPS (normally TCP 22) from the operator's address only.
- Do **not** open the tunnel port (`2201`, `2202`, ...) in the VPS firewall.
- The device needs outbound SSH to the VPS and outbound HTTPS to the apt
  repository. It needs no inbound rule at home.
- If the VPS uses `ufw`, the tunnel port must not appear in `ufw status`; the
  loopback bind is enough. For example (bash on the VPS; replace the operator
  address):

  ```bash
  sudo ufw allow from <operator-ip> to any port 22 proto tcp
  sudo ufw status verbose
  ```

Check after a tunnel is up:

```bash
# On the VPS
ss -ltnp 'sport = :2201'
```

The local address must be `127.0.0.1:2201`, never `0.0.0.0:2201` or `[::]:2201`.
From a second machine, connecting to `vps.example.org:2201` must fail.

## VPS setup

Run as root on the VPS (bash):

```bash
sudo bash scripts/vps-setup.sh --port 2201 --serial pi-01 --dry-run
sudo bash scripts/vps-setup.sh --port 2201 --serial pi-01
```

The first run creates:

- the `weatherpi-tunnel` system account, home and `~/.ssh`;
- `~/.ssh/authorized_keys` at mode 0600;
- `/etc/ssh/sshd_config.d/00-weatherpi-tunnel.conf` with `GatewayPorts no`.

It validates the result with `sshd -t`, checks `sshd -T` for
`gatewayports no`, and reloads sshd. It refuses to reload an invalid
configuration. It does not replace `/etc/ssh/sshd_config`.

Enroll the device public key on the same run, or later:

```bash
sudo bash scripts/vps-setup.sh --port 2201 --serial pi-01 \
    --pubkey-file /tmp/weather-pi-tunnel.pub
```

The resulting line looks like:

```text
restrict,port-forwarding,permitlisten="127.0.0.1:2201" ssh-ed25519 AAAA... weatherpi-pi-01
```

Re-running with the same key and port is a no-op. If the same key is present
with different options or a different port, the script warns and leaves the
existing line alone; edit it deliberately.

`--sshd-config DIR` overrides the drop-in directory for non-standard systems.
The script warns if `/etc/ssh/sshd_config` does not include
`/etc/ssh/sshd_config.d/*.conf`; add that `Include` line before relying on the
drop-in.

The script warns if `ss` reports that the chosen port already has a listener.
It does not kill anything; choose another port and re-enroll if the listener is
not this device's tunnel.

## Host-key pinning and fingerprint verification

The device pins the VPS host public key. It does not trust the network on first
contact, so a changed host key stops the tunnel instead of silently accepting an
impostor.

`vps-setup.sh` prints every VPS host key in this form:

```text
  /etc/ssh/ssh_host_ed25519_key.pub
    fingerprint: SHA256:...
    host_key = "ssh-ed25519 AAAA..."
```

The complete `host_key` value is what goes into the provisioning configuration
(or `tunnel.toml`). This is a public key, not a fingerprint and not a secret.
Prefer the `ssh-ed25519` key when the VPS has one, and pin exactly one key.

Verify the fingerprint out of band, for example on the VPS provider's console
or against a value recorded when the VPS was created:

```bash
# On the VPS
sudo ssh-keygen -E sha256 -lf /etc/ssh/ssh_host_ed25519_key.pub
sudo cat /etc/ssh/ssh_host_ed25519_key.pub
```

Do not verify it only with `ssh-keyscan` over the same untrusted path you are
trying to protect. If the VPS SSH port is not 22, the client's `known_hosts`
entry is `[vps.example.org]:2222` rather than `vps.example.org`; first boot
writes that entry with the pinned key, and the unit uses
`StrictHostKeyChecking=yes`.

A VPS rebuild changes the host key. The tunnel then fails closed until the new
key is verified and the provisioning value or
`/etc/weather-pi/known_hosts` is updated deliberately.

## First boot, key generation and enrollment

The image contains no tunnel credentials. First boot writes the runtime files:

- `/etc/weather-pi/tunnel.env` with `TUNNEL_HOST`, `TUNNEL_PORT`,
  `TUNNEL_USER`, `TUNNEL_REMOTE_PORT`, owned `root:weather-pi` at mode 0640
  (or 0644) so the `weather-pi` account can read it;
- `/etc/weather-pi/tunnel_key`, owned `weather-pi:weather-pi` at mode 0600.
  If first boot writes it as root, it must chown it to `weather-pi`; OpenSSH
  rejects a client private key with group or other access;
- `/etc/weather-pi/known_hosts` with the pinned VPS host key, owned
  `root:weather-pi` at mode 0640 (or `root:root` 0644) so `weather-pi` can read
  it.

`weather-pi-tunnel.service` runs as `weather-pi`, so all three paths must be
readable by that account. The environment file is also read by systemd as root.
Use `chown weather-pi:weather-pi` and `chmod 0600` for the private key, and do
not make the key group- or world-readable.

```bash
# Expected ownership and modes on the device (bash)
sudo ls -l /etc/weather-pi/tunnel.env /etc/weather-pi/tunnel_key /etc/weather-pi/known_hosts
```

The package installs the unit but does not enable or start it. First boot
enables and starts `weather-pi-tunnel.service` only when the tunnel is
configured. Without the environment file, the private key and `known_hosts`,
the unit's `ConditionPathExists` checks keep it stopped.

The preferred key flow is:

1. First boot generates an ed25519 key and exports the public half to
   `/boot/firmware/weather-pi-tunnel.pub`.
2. The operator copies that file to the VPS (for example over the LAN, or with
   the boot partition mounted on a computer).
3. The operator runs `scripts/vps-setup.sh --pubkey-file ...` as above.
4. The tunnel reconnects on the next retry; restart it immediately with
   `sudo systemctl restart weather-pi-tunnel.service` on the device if needed.

If the provisioning file supplies a private key instead, that key is treated as
a secret exactly like the WiFi passphrase and must be removed from the boot
partition after first boot. Never commit a real key to this repository.

Check the device over LAN while enrolling (bash on the device):

```bash
sudo systemctl status weather-pi-tunnel.service
sudo journalctl -u weather-pi-tunnel.service -n 50 --no-pager
sudo ls -l /etc/weather-pi/tunnel.env /etc/weather-pi/tunnel_key /etc/weather-pi/known_hosts
```

## Operator SSH configuration

On the operator machine, add an alias to `~/.ssh/config`:

```sshconfig
Host weather-pi
    HostName 127.0.0.1
    Port 2201
    User weather-pi
    ProxyJump vps.example.org
    IdentityFile ~/.ssh/weather-pi-admin
    IdentitiesOnly yes
```

Use `ProxyJump vps.example.org:2222` if the VPS sshd is not on port 22. The
device-side administrator key is the one placed in `weather-pi`'s
`~/.ssh/authorized_keys` during provisioning; it is independent of the tunnel
key.

The equivalent one-liner is:

```nu
ssh -J vps.example.org -p 2201 weather-pi@127.0.0.1
```

Test it with a command that does not depend on the application:

```nu
ssh weather-pi 'hostname; weather-pi --version; systemctl is-active weather-pi-tunnel.service'
```

A LAN fallback such as `ssh weather-pi.local` remains available for initial
setup and rescue. It is not exposed through the tunnel setup.

## Deploy configuration and assets

From the repository root on the operator machine:

```nu
mise run deploy
```

`scripts/deploy.sh`:

1. checks that `weather-pi` is reachable over SSH and fails clearly if not;
2. records the installed version with `dpkg-query`;
3. copies the application configuration `assets/greeter.toml` and
   `assets/countdown.toml` to `/etc/weather-pi/`, and `assets/*.bmp` to
   `/usr/share/weather-pi/`, using `sudo -n` on the device;
   `assets/tunnel.toml` is never copied by deploy;
4. restarts `weather-pi.service` and verifies `is-active`;
5. verifies that `dpkg-query` still reports the same version.

It never installs, upgrades, downgrades or replaces `/usr/bin/weather-pi`.
That file belongs to dpkg, and package releases arrive through apt.

Environment overrides (local nushell):

```nu
$env.WEATHER_PI_HOST = "weather-pi"          # SSH alias
$env.WEATHER_PI_SSH_OPTS = "-o ConnectTimeout=15"
$env.WEATHER_PI_DEPLOY_ASSETS = "0"          # skip rsync, only restart
mise run deploy
```

Use `with-env` for a one-off override:

```nu
with-env { WEATHER_PI_DEPLOY_ASSETS: "0" } { mise run deploy }
```

`mise run status` reads the same `WEATHER_PI_HOST` and `WEATHER_PI_SSH_OPTS`
overrides.

The deploy command treats `assets/greeter.toml` and `assets/countdown.toml` as
the source of truth for their files in `/etc/weather-pi/`. Edit the repository
files, not only the device, or the next deploy overwrites the remote copies.
`assets/tunnel.toml` is deliberately not deployed: it is a package/provisioning
template, and first boot owns `/etc/weather-pi/tunnel.toml` and the runtime
`tunnel.env`, `tunnel_key` and `known_hosts`.

If deploy fails during preflight, it has not changed the device. If it fails
after rsync, the configuration may already be copied; the error says so, and
`mise run status` shows the service state.

## Status

```nu
mise run status
```

One SSH invocation collects, in labels meant to be read by a human or a script:

- tunnel unit active/enabled state;
- application unit state and `NRestarts`;
- installed package version; candidate version from `apt-cache policy`;
- `apt-daily-upgrade.timer` state and next run;
- the tail of `/var/log/unattended-upgrades/unattended-upgrades.log`.

It is read-only and exits 0 even when the application is stopped. It uses
`sudo -n` only for the root-owned unattended-upgrades log. If the tunnel itself
is down, status cannot reach the device; use the LAN alias or the VPS console.

## Update visibility and recovery

Application updates are applied on the device by `unattended-upgrades` from the
signed repository. The tunnel carries only operator SSH sessions, so update
traffic bypasses the VPS and a tunnel outage does not block an update. The
reverse also holds: an application update failure does not stop the tunnel.

Inspect versions over the tunnel (bash on the device):

```bash
dpkg-query -W -f='${Status} ${Version}\n' weather-pi
apt-cache policy weather-pi
apt-cache madison weather-pi
systemctl status apt-daily-upgrade.timer --no-pager
sudo tail -n 30 /var/log/unattended-upgrades/unattended-upgrades.log
```

A newer published version appears as the candidate; the installed version does
not change until unattended-upgrades or the operator acts.

### Pin or downgrade a bad release

The repository retains the five newest versions per architecture. To restore a
known-good version (bash on the device):

```bash
sudo apt-get update
apt-cache madison weather-pi
sudo apt-get install --allow-downgrades weather-pi=0.2.0-1
sudo systemctl restart weather-pi.service
dpkg-query -W -f='${Version}\n' weather-pi
```

If the repository has pruned the version, use the cached package that apt keeps
on the device:

```bash
ls -l /var/cache/apt/archives/weather-pi_*.deb
sudo apt-get install /var/cache/apt/archives/weather-pi_0.2.0-1_armhf.deb
sudo systemctl restart weather-pi.service
```

To keep unattended-upgrades from immediately moving the package again:

```bash
sudo apt-mark hold weather-pi
# after the incident
sudo apt-mark unhold weather-pi
```

### Finish an interrupted installation

If dpkg was interrupted or left the package half-configured, the tunnel is still
independent of the application. On the device (bash):

```bash
sudo dpkg --audit
sudo dpkg --configure -a
sudo apt-get -f install
sudo systemctl restart weather-pi.service
```

Wait for a running `apt-daily-upgrade.service` to finish rather than killing it.
`mise run status` afterwards shows the installed version and service state.

### Restart only

To restart without changing the package (bash on the device):

```bash
sudo systemctl restart weather-pi.service
dpkg-query -W -f='${Version}\n' weather-pi
```

The version must not change. `mise run deploy` with
`WEATHER_PI_DEPLOY_ASSETS=0` is the operator shortcut for restart-only, but it
still checks the version before and after.

## Troubleshooting

Start with the VPS side, then the device side, then the object's logs.

### The VPS port is absent or public

```bash
# On the VPS
ss -ltnp 'sport = :2201'
sudo sshd -T | grep -i '^gatewayports'
sudo tail -n 50 /var/log/auth.log
```

- No listener: the device is not connected, the key is not enrolled, or the
  device is offline. Check the device logs below.
- Listener on `0.0.0.0` or `[::]`: an earlier `GatewayPorts yes` or
  `clientspecified` is winning. Fix the earlier sshd configuration and rerun
  `vps-setup.sh`; do not expose the port.
- `Accepted publickey` then an immediate disconnect: inspect the device side.

### Tunnel unit fails on the device

Over LAN or the VPS console (bash on the device):

```bash
systemctl status weather-pi-tunnel.service --no-pager
journalctl -u weather-pi-tunnel.service -n 80 --no-pager
sudo ls -l /etc/weather-pi/tunnel.env /etc/weather-pi/tunnel_key /etc/weather-pi/known_hosts
sudo systemctl cat weather-pi-tunnel.service
```

Common causes:

- A `Condition check resulted in ... being skipped` line means the unit is not
  configured. First boot did not write the environment file or key; the tunnel
  is deliberately fail-closed.
- `Permission denied (publickey)`: the public key is not enrolled for
  `weatherpi-tunnel`, the key file is not owned by `weather-pi` at mode 0600,
  or the account/options do not match.
- `REMOTE HOST IDENTIFICATION HAS CHANGED`: verify the new VPS host key out of
  band, then update provisioning/`known_hosts`. Do not delete the pinned entry
  without verifying it.
- `remote port forwarding failed for listen port 2201`: another process or
  another device holds the port; check `ss` on the VPS.
- `Connection timed out`: the VPS is unreachable from the home network, DNS is
  wrong, or the VPS firewall blocks the device's outbound SSH.

A foreground diagnostic using the same fixed paths (bash on the device). Read
the four values from `/etc/weather-pi/tunnel.env` and substitute them; this is
not a command to paste unchanged:

```bash
sudo cat /etc/weather-pi/tunnel.env
sudo -u weather-pi ssh -vv -N -T -o BatchMode=yes -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile=/etc/weather-pi/known_hosts \
  -o IdentitiesOnly=yes -i /etc/weather-pi/tunnel_key \
  -p <TUNNEL_PORT> -R "127.0.0.1:<TUNNEL_REMOTE_PORT>:localhost:22" \
  "<TUNNEL_USER>@<TUNNEL_HOST>"
```

Stop the diagnostic with Ctrl-C; the systemd unit continues to be the only
supported runtime path.

### Deploy cannot reach `weather-pi`

```nu
ssh -v weather-pi true
```

- `ProxyJump` failure: the VPS account/key changed or the VPS sshd is down.
- Connection accepted but authentication fails: the device-side admin key is
  wrong or `AllowUsers weather-pi` no longer matches.
- The tunnel unit is inactive: use LAN access to fix the tunnel before deploying.

`mise run deploy` deliberately fails before rsync when the preflight fails.

### Device sshd refuses access

On the device over LAN (bash):

```bash
sudo sshd -T | grep -Ei '^(passwordauthentication|permitrootlogin|pubkeyauthentication|allowusers|kbdinteractiveauthentication) '
sudo ls -l /etc/ssh/sshd_config.d/10-weather-pi.conf
```

The image installs `10-weather-pi.conf` with password and root login disabled
and `AllowUsers weather-pi`. A package or administrator change that overrides
the fragment should be corrected there, not by re-enabling passwords.

### apt is failing, but the tunnel is fine

Package traffic does not use the tunnel. Check the device's outbound HTTPS,
the apt source and keyring, and the unattended-upgrades log:

```bash
sudo apt-get update
sudo apt-get -o Debug::Acquire::https=true update
apt-cache policy weather-pi
```

An expired repository index or a missing archive key is an apt problem, not a
tunnel problem.

## Key and host-key rotation

- **Rotate a device tunnel key**: generate a new key on the device, enroll its
  public half on the VPS with `vps-setup.sh`, remove the old authorized_keys
  line, then restart `weather-pi-tunnel.service`. The old key stops working as
  soon as its line is removed.
- **Replace a lost SD card**: install the image, let first boot create a new
  key, and enroll the new public key. The old line can be removed when the old
  card is retired.
- **Rebuild the VPS**: verify the new host key out of band, update the
  provisioning value (or `/etc/weather-pi/known_hosts` over LAN/console), and
  restart the tunnel unit. A host-key mismatch must keep the tunnel down until
  this is done.

## Security notes

- Tunnel private keys and administrator private keys are never in the image or
  repository. `assets/tunnel.toml` is a template with a placeholder public key
  only.
- The VPS forwarding account can only forward one loopback port for one key. It
  cannot execute commands on the VPS or the device.
- The VPS sees connection metadata, not the encrypted SSH session contents.
- The tunnel port is not a public service. Keep it on loopback and out of the
  firewall.
- Package downloads use the device's direct HTTPS path, not the VPS.
