# Building and provisioning the device image

The device image is a bootable Raspberry Pi OS Lite (trixie, armhf) image with
the `weather-pi` application, archive keyring, repository configuration, and
unattended-upgrades setup installed. One image serves the Pi Zero, Zero W, and
Zero 2 W.

The image contains no device-specific secrets. WiFi, SSH keys, hostname, and
tunnel settings are applied from `/boot/firmware/weather-pi.cfg` on first boot,
then the secret fields are removed from that file.

## Prerequisites

- A Linux build host with a **privileged Docker daemon**. pi-gen creates loop
  devices and runs an armhf chroot.
- armhf execution support. On x86 hosts the usual QEMU/binfmt setup is enough;
  if the Docker build reports `Exec format error`, install
  `qemu-user-static`/`qemu-user-binfmt` or register binfmt with the
  `tonistiigi/binfmt` image.
- `git`, `zstd`, and `minisign`. `mise install` provides the pinned minisign;
  `zstd` is a distribution package.
- The public archive keyring at
  `packaging/keyring/weather-pi-archive.gpg` (see
  [docs/releasing.md](releasing.md)) or `WEATHER_PI_ARCHIVE_KEYRING` pointing at
  it.
- An image-signing minisign key (see below). The build refuses to produce an
  image without `WEATHER_PI_MINISIGN_KEY`.
- Roughly 10 GB of free space under `target/image` and the patience for a
  pi-gen build.

The build runs `apt-get update` and installs the project packages from the
signed repository inside the chroot. A missing key, bad signature, expired
`Valid-Until`, or missing pinned version aborts the build before an image is
exported.

## Version selection

`IMAGE_VERSION` is the exact Debian package version installed into the image.
It must already exist in the repository for `armhf`:

```sh
# Default: derive from the git tag, or Cargo.toml when HEAD is untagged
IMAGE_VERSION="$(scripts/version.sh from-git)"

# Explicit version, for rebuilding an older release while the pool retains it
IMAGE_VERSION=0.2.0-1 mise run image
```

Both `weather-pi` and `weather-pi-archive-keyring` are installed at that exact
version. The value is recorded in `/etc/weather-pi/image-version` and
`/etc/weather-pi/build-info`.

## Signing key

Generate the image key once, keep the secret key off the repository, and publish
the public key:

```sh
mkdir -p ~/.minisign
mise x -- minisign -G -p packaging/image-signing.pub -s ~/.minisign/weather-pi.key
chmod 600 ~/.minisign/weather-pi.key
```

Add `-W` to generate a key without a passphrase for a non-interactive build,
and protect that file accordingly; without it, `minisign -S` prompts during the
build.

`packaging/image-signing.pub` may be committed so consumers can verify images.
Never commit the secret key. The build uses:

| Variable | Purpose |
| --- | --- |
| `WEATHER_PI_MINISIGN_KEY` | Path to the secret key; **required** for a real build |
| `WEATHER_PI_MINISIGN_PUBKEY` | Path to the public key used to self-verify the signature after signing; defaults to `packaging/image-signing.pub` when present |

## Build

```sh
mise install
export IMAGE_VERSION=0.2.0-1
export WEATHER_PI_MINISIGN_KEY="$HOME/.minisign/weather-pi.key"
mise run image
```

`mise run image` calls `image/build.sh`. It:

1. Clones `RPi-Distro/pi-gen` at the pinned `PIGEN_REV` and checks out
   `RELEASE=trixie`.
2. Copies `image/stage-weather-pi` into the pi-gen tree, injects the repository
   URL, archive keyring, `IMAGE_VERSION`, and the resolved pi-gen commit.
3. Scans the staged payload for private keys and password assignments.
4. Runs pi-gen in privileged Docker.
5. Compresses the single exported image, writes `SHA256SUMS`, and creates a
   detached minisign signature.

Useful overrides:

| Variable | Default | Meaning |
| --- | --- | --- |
| `IMAGE_VERSION` | `scripts/version.sh from-git` | Package version installed in the image |
| `IMAGE_BUILD_DIR` | `target/image` | pi-gen checkout and work directory |
| `IMAGE_OUTPUT_DIR` | `dist/image` | Published artifacts |
| `PIGEN_REPO` | upstream pi-gen | Alternative pi-gen clone |
| `PIGEN_REV` | pinned commit | pi-gen revision; the resolved commit is recorded |
| `WEATHER_PI_REPO_URL` | `https://corrodedhash.github.io/weather-pi/` | Repository written into the apt source |
| `WEATHER_PI_ARCHIVE_KEYRING` | `packaging/keyring/weather-pi-archive.gpg` | Public archive key copied into the image |
| `WEATHER_PI_MINISIGN_KEY` | unset | Secret key used to sign the image |
| `WEATHER_PI_MINISIGN_PUBKEY` | `packaging/image-signing.pub` if present | Public key used for the post-sign verification |
| `IMAGE_PREPARE_ONLY` | `0` | `1` assembles the pi-gen tree and stage, runs the secret scan, and stops before Docker |

`IMAGE_PREPARE_ONLY=1` is the no-Docker path:

```sh
IMAGE_PREPARE_ONLY=1 \
WEATHER_PI_ARCHIVE_KEYRING=packaging/keyring/weather-pi-archive.gpg \
IMAGE_VERSION=0.2.0-1 \
mise run image
```

It prints the prepared stage, generated `image-version`, and pi-gen config
paths. This is useful for reviewing the payload and running the secret scan on
a host without a Docker daemon. It still needs `git` and a public keyring.

## Output and verification

A successful build writes:

```text
dist/image/weather-pi-<version>.img.zst
dist/image/weather-pi-<version>.img.zst.minisig
dist/image/SHA256SUMS
```

The raw pi-gen export remains at `target/image/pi-gen/deploy/`. `SHA256SUMS`
covers the compressed image (not the signature).

From a clean download:

```sh
cd dist/image
sha256sum -c SHA256SUMS
minisign -V \
  -m weather-pi-0.2.0-1.img.zst \
  -x weather-pi-0.2.0-1.img.zst.minisig \
  -p ../../packaging/image-signing.pub
```

The image is rebuildable but not bit-identical: Debian package repositories
move and pi-gen timestamps the filesystem. Pinning pi-gen, pinning the project
packages, and recording the repository `Date` and package versions in
`build-info` identify exactly what shipped.

## Flashing

Find the target device carefully; `dd` destroys whatever is on it:

```sh
lsblk
zstd -dc dist/image/weather-pi-0.2.0-1.img.zst |
  sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Mount the FAT boot partition after flashing to add `weather-pi.cfg` (next
section), then boot the device.

## Provisioning file

Create `/boot/firmware/weather-pi.cfg` on the boot partition. It is TOML. All
sections are optional, but at least one recognized setting is required. Unknown
fields, wrong types, out-of-range ports, malformed keys, and invalid TOML fail
the first-boot unit closed: no files are applied and no sentinel is written.

```toml
hostname = "weather-pi"

[wifi]
ssid = "example-network"
password = "correct horse battery staple"
country = "DE"

[ssh]
authorized_keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyOne operator@laptop",
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyTwo backup@laptop",
]

[tunnel]
host = "vps.example.com"
port = 2222
user = "weather-pi"
remote_port = 2200
host_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleHostKey"
# private_key = """
# -----BEGIN OPENSSH PRIVATE KEY-----
# ...
# -----END OPENSSH PRIVATE KEY-----
# """
```

### Fields

| Field | Required | Behaviour |
| --- | --- | --- |
| `hostname` | No | Written to `/etc/hostname` and `127.0.1.1` in `/etc/hosts`. Must be 1-63 letters, digits, or hyphens and not start/end with `-`. |
| `[wifi].ssid` | Yes, with `[wifi]` | NetworkManager connection `weather-pi-wifi` is created or updated with `nmcli`. If `nmcli` fails or is unavailable, a keyfile is written to `/etc/NetworkManager/system-connections/` with mode `0600`. |
| `[wifi].password` | No | WPA passphrase, 8-63 characters or 64 hex digits. Omit or use `""` for an open network. Removed from the boot partition after provisioning; only the applied NetworkManager profile keeps it. |
| `[wifi].country` | No | Two-letter ISO 3166 code. Persisted as `cfg80211.ieee80211_regdom=XX` in `cmdline.txt` and applied with `iw reg set` when possible. |
| `[ssh].authorized_keys` | No | Keys are appended to `/home/weather-pi/.ssh/authorized_keys`; existing entries are preserved. Duplicate keys are not added twice. |
| `[tunnel].host` | Yes, with `[tunnel]` | VPS hostname or IP address. |
| `[tunnel].port` | No | SSH port on the VPS, default `22`. |
| `[tunnel].user` | Yes, with `[tunnel]` | Login user on the VPS. |
| `[tunnel].remote_port` | Yes, with `[tunnel]` | Port opened on the VPS for the reverse tunnel. |
| `[tunnel].host_key` | Yes, with `[tunnel]` | Pinned VPS SSH public key. A bare key is prefixed with `[host]:port` in `known_hosts`; a complete known_hosts entry is kept as written. |
| `[tunnel].private_key` | No | OpenSSH/PEM tunnel identity. If omitted and no identity exists, an ed25519 key is generated with `ssh-keygen -t ed25519 -N ''`. |

The first-boot program is `/usr/lib/weather-pi/firstboot`; the unit is
`weather-pi-firstboot.service`. It runs before `weather-pi.service`, logs to the
journal, and writes `/var/lib/weather-pi/firstboot.done` as its final action.
If the sentinel exists, a later run exits successfully without changing
anything. If the provisioning file is absent, the run exits successfully
without creating the sentinel.

Troubleshoot a provisioning run with:

```sh
journalctl -u weather-pi-firstboot -b
cat /var/lib/weather-pi/firstboot.done
```

When `[tunnel]` is present the program writes the paths expected by
`weather-pi-tunnel.service`:

```text
/etc/weather-pi/tunnel.toml        # no private key
/etc/weather-pi/tunnel.env         # TUNNEL_HOST, TUNNEL_PORT, TUNNEL_USER, TUNNEL_REMOTE_PORT (0600)
/etc/weather-pi/tunnel_key         # private identity (0600)
/etc/weather-pi/tunnel_key.pub     # public half (0644)
/etc/weather-pi/known_hosts        # pinned host key (0644)
/boot/firmware/weather-pi-tunnel.pub
```

`weather-pi-tunnel.service` is enabled and started when it is installed. If the
unit is not present, first boot warns and continues; the runtime package can be
installed later.

A bare `host_key` becomes a `[host]:port` known_hosts entry. For the default
SSH port, first boot also writes the bare-host form because OpenSSH looks up the
host name without a port for port 22; both entries pin the same key.

After a successful run the program rewrites the provisioning file without
`wifi.password`, `tunnel.private_key`, or any other private-key field. Other
settings are kept. The rewrite is atomic. If first boot fails before that
rewrite, the file still contains the secrets so the operator can retry; treat a
lost card as compromised and rotate the credentials.

## Build info

After the package install, the image contains `/etc/weather-pi/build-info` in a
stable `key=value` format (split on the first `=`):

```text
BASE_RELEASE=trixie
PIGEN_REV=291c62c1108d03f594dbed65507e97eb0d9a2b0e
REPO_DATE=Wed, 12 Nov 2026 13:30:00 UTC
IMAGE_VERSION=0.2.0-1
WEATHER_PI_VERSION=0.2.0-1
WEATHER_PI_ARCHIVE_KEYRING_VERSION=0.2.0-1
```

`REPO_DATE` is the first `Date:` in the signed `InRelease` used during the
build, with the build's current UTC time as a fallback. The installed package
versions are asserted before this file is written.

## On-device smoke test

Copy `scripts/device-smoke-test.sh` to the device (or run it from a checkout)
and run it as root:

```sh
scp scripts/device-smoke-test.sh weather-pi@device:/tmp/
ssh weather-pi@device 'sudo /tmp/device-smoke-test.sh'
```

It checks:

- `weather-pi.service` is active.
- A default route exists and its gateway (or `--network-target`) answers ping.
- A `/dev/spidev*` device exists, proving the SPI overlay is active. The e-ink
  panel has no framebuffer, so this plus the active service is the practical
  display-initialisation check.
- `weather-pi --version` runs and prints the expected prefix.
- When a tunnel is configured, its files exist and
  `weather-pi-tunnel.service` is active.
- `unattended-upgrade --dry-run -d` completes successfully without installing
  anything.

Any failed check makes the script exit nonzero; successful checks print
`PASS`, a missing tunnel prints `SKIP`.

## Secret scanning

`scripts/check-image-secrets.sh <directory>` fails on armored private keys,
OpenPGP secret-key packets, and non-empty password/passphrase assignments. The
build runs it on the copied stage before Docker, and the
`90-secret-scan` stage runs the same scanner in the chroot against
`/boot/firmware`, `/etc/weather-pi`, `/home/weather-pi`, and `/root`.

Run the local checks with:

```sh
scripts/test-image-secrets.sh
scripts/test-firstboot.sh
scripts/test-device-smoke-test.sh
```

## Rotation and recovery

**WiFi password.** Update the live profile or re-run first boot with a new
provisioning file:

```sh
sudo nmcli connection modify weather-pi-wifi wifi-sec.psk 'new passphrase'
sudo nmcli connection up weather-pi-wifi
```

If first boot used the keyfile fallback instead of nmcli, the profile id is
`weather-pi-<safe-ssid>` and the file is
`/etc/NetworkManager/system-connections/weather-pi-<safe-ssid>.nmconnection`;
update it with `nmcli connection modify` or edit it as root (mode `0600`).

To make first boot reapply a complete file:

```sh
sudo rm /var/lib/weather-pi/firstboot.done
# put the full file, including secrets, back on /boot/firmware/weather-pi.cfg
sudo systemctl restart weather-pi-firstboot.service
```

**SSH keys.** Add a new key to `[ssh].authorized_keys`, remove the sentinel, and
restart first boot. Missing keys are appended and existing keys are preserved.
To revoke a key, edit `/home/weather-pi/.ssh/authorized_keys` directly;
first boot does not remove entries.

**Tunnel identity.** Remove the old identity and sentinel, leave
`tunnel.private_key` out of the file, and restart first boot to generate a new
ed25519 key:

```sh
sudo rm /etc/weather-pi/tunnel_key /etc/weather-pi/tunnel_key.pub
sudo rm /var/lib/weather-pi/firstboot.done
sudo systemctl restart weather-pi-firstboot.service
cat /boot/firmware/weather-pi-tunnel.pub
```

Authorize the new public key on the VPS. To supply a specific key instead, add
`tunnel.private_key` to the file before restarting. Existing tunnel identities
are preserved when the sentinel is absent, so remove the key file explicitly.

**Archive key.** Follow the overlap procedure in
[docs/releasing.md](releasing.md). The image ships the keyring package, so a
rotation is a normal package update after first boot.

If a device or SD card is lost, rotate the WiFi password, remove its SSH key
from the tunnel/VPS authorized keys, and generate a new tunnel identity.
Secrets that were not removed because first boot never completed are still on
the FAT partition.

## Remaining hardware validation

The first-boot logic, secret scanner, and smoke-test harness are covered by
local fixture tests. The following still require real hardware and a
Docker-capable build host:

- [ ] Build a real image with privileged Docker and confirm
  `dist/image/weather-pi-<version>.img.zst` is produced, checksummed, and
  signature-verified.
- [ ] Boot the image on a Pi Zero and a Zero 2 W with a provisioning file.
- [ ] Record display output, `systemctl status weather-pi`, the service user and
  `spi`/`gpio` groups, network reachability, SSH, and the tunnel.
- [ ] Confirm `weather-pi-firstboot.service` removes the secrets, writes the
  sentinel, and that a second boot changes nothing.
- [ ] Confirm the service starts from the shipped sample configuration.
- [ ] Confirm `apt-get update`, `apt-cache policy weather-pi`, and
  `unattended-upgrade --dry-run -d` on the device, including the project origin
  in the allowlist.
- [ ] Re-flash a second card and verify no host keys, authorized keys, tunnel
  identity, or WiFi profile carried over.
- [ ] Decide whether to keep a serial console enabled for recovery and record
  the choice here.
