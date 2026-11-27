# Design

## Context

See `proposal.md`. Constraints that shape the approach:

- The existing binary targets `arm-unknown-linux-gnueabihf` (armv6). Raspberry Pi OS 32-bit runs on Zero, Zero W, and Zero 2 W, so one image can serve all three; a 64-bit image would exclude the original Zero.
- The device is headless, connects over WiFi, and sits behind NAT.
- The release pipeline produces signed packages and an apt repository; the image build must consume them, not rebuild them.
- The current unit file is not startable: it passes no app argument and runs as root with `chrt`.
- Trixie uses NetworkManager for WiFi; older Bookworm recipes based on `wpa_supplicant.conf` will not apply.
- apt is already part of the base system, so installing packages needs no new mechanism.

## Goals / Non-Goals

**Goals:**

- One armhf image that works on every supported model.
- First boot to a running service with only a provisioning file added to the boot partition.
- An installed update path that works without further setup, using the same verification as a manual install.
- Image builds reproducible enough to identify exactly what shipped.

**Non-Goals:**

- 64-bit image variants.
- Whole-disk A/B updates or signed boot (RAUC); the package update path covers the software we change most.
- Multiple device profiles or a fleet provisioning server.
- Changing the repository configuration on an existing device; the image ships it once and later changes are deliberate operator edits.

## Decisions

### Image builder: pi-gen (master, armhf/trixie) in Docker

pi-gen is the tool that produces Raspberry Pi OS, supports armhf, and is routinely run on x86 through Docker and QEMU. Alternative: `rpi-image-gen` is more declarative and better for bespoke images, but its supported host is native arm64 Raspberry Pi OS and armhf cross builds are less proven; it can be revisited if ARM64 becomes the only target.

Pin the pi-gen revision in the image task so the base does not move under us.

### One armhf image, both architectures still built

Because 32-bit userspace runs on armv8, a single armhf image covers the whole Zero family. The release pipeline still builds arm64 so the device can move to 64-bit later without changing the update format.

### Install packages from the signed repository, not from a tarball

The stage adds the archive key to `/usr/share/keyrings`, writes the `signed-by` source, and runs `apt-get install weather-pi=<version> weather-pi-archive-keyring=<version>` inside the chroot. This exercises exactly the path the device uses later: if the repository metadata or a package hash does not verify, the image build fails.

Alternatives:

- **Install a verified tarball**: duplicates the install path, needs a second trust anchor (`update.pub`/minisign), and gives the image and the device different notions of what is installed.
- **Copy `.deb` files in and `dpkg -i` them**: skips the repository signature, leaving the image's trust story weaker than the device's.

The pinned version is recorded as an argument to `mise run image`, so an image can be rebuilt from an older repository state while the pool still holds that version.

### Configuration layout

- `/etc/apt/sources.list.d/weather-pi.list` — `signed-by=` source for the project repository.
- `/etc/apt/preferences.d/weather-pi.pref` — `o=weather-pi` pin, priority 500.
- `/etc/apt/apt.conf.d/90weather-pi` — `Acquire::Check-Valid-Until`, `APT::Keep-Downloaded-Packages`, retries, lock timeout.
- `/etc/apt/apt.conf.d/20auto-upgrades` — `APT::Periodic::Update-Package-Lists` and `APT::Periodic::Unattended-Upgrade` set to `1`.
- `/etc/apt/apt.conf.d/51weather-pi-unattended` — the project origin in the unattended-upgrades allowlist.
- `/usr/share/keyrings/weather-pi-archive.gpg` — archive public key, from `weather-pi-archive-keyring`.
- `/etc/weather-pi/<app>.toml` — conffiles installed by the application package.
- `/usr/share/weather-pi/*.bmp` — assets from the application package.
- `/etc/weather-pi/build-info` — base release, pi-gen revision, repository `Date`, package versions.

`/etc/weather-pi/update.pub` from the earlier design is removed; the apt keyring is the only trust anchor.

### First boot reads `/boot/firmware/weather-pi.cfg`

A small `weather-pi-firstboot.service` runs before the app, parses a TOML file from the FAT partition, and applies:

- hostname
- WiFi SSID/passphrase via `nmcli` (or a generated NetworkManager keyfile)
- `authorized_keys` for the admin user
- tunnel target (VPS host/port/user)
- application config overrides, if present

It then deletes the secret fields from the boot partition and marks itself done with a sentinel. Re-running without secrets leaves state untouched. This keeps one published image valid for every device and avoids committing or distributing secrets.

Alternative considered: Raspberry Pi Imager's `custom.toml` preconfiguration. Rejected because the workflow is `dd`, not Imager, and because it does not cover tunnel settings.

### Update readiness

The image installs `unattended-upgrades`, enables periodic updates and unattended upgrades in `20auto-upgrades`, adds the project origin to the allowed origins, and leaves the distribution's own origins intact. It enables `APT::Keep-Downloaded-Packages` so archives stay in `/var/cache/apt/archives`, and ships no project-owned update timer, recovery unit, or state directory. After first boot the standard `apt-daily-upgrade.timer` is the only update scheduler; an update that installs successfully is not health-checked or rolled back automatically.

### Minimal package set

Install only: `ca-certificates`, `curl`, `iputils-ping` (the greeter shells out to `ping`), `openssh-client` and `openssh-server` for the tunnel, `unattended-upgrades`, `zstd` at build time only, and the base Lite packages. `apt` and `gpgv` come from the base and are sufficient for verification. No compilers or development tools in the image.

### Runtime hardening

`User=weather-pi`, `SupplementaryGroups=spi gpio`, `Type=simple`, `Restart=on-failure`, `RestartSec=5s`, `NoNewPrivileges=yes`, `ProtectSystem=strict`, `ProtectHome=yes`. No `ReadWritePaths` is needed. Do not set a capability bounding set that would break `/dev/gpiochip` or `/dev/spidev` access. Drop `chrt`; the app has no realtime requirement and cannot take `CAP_SYS_NICE`.

### Image integrity

The image task verifies the repository `InRelease` against the archive key, then builds; the chroot install verifies again. The output is `.img.zst`, `SHA256SUMS`, and a detached minisign signature (minisign is used only for the image, not for packages). `build-info` records what was installed and from which repository state.

### Reproducibility level

The image is rebuildable but not bit-identical: Debian package repositories move and pi-gen timestamps the filesystem. Pinning pi-gen, pinning the project packages, and recording package versions and the repository `Date` is the practical middle ground; `SOURCE_DATE_EPOCH` is set to make timestamps stable where pi-gen honors it.

## Risks / Trade-offs

- **Building images needs privileged Docker/loop devices** → document the requirement and keep the task opt-in; CI image builds are manual initially.
- **Repository unreachable during a build** → the build fails rather than producing an image with an unverified payload; an offline mode that consumes previously downloaded packages can be added later.
- **Pinned version disappears after pruning** → repository retention is five versions; rebuilding an ancient image needs the pool restored from the GitHub Release assets, which is documented.
- **NetworkManager behavior differs across releases** → pin the release branch (`trixie`), test the firstboot path on real hardware, and keep the WiFi step idempotent.
- **Secrets left on the FAT partition if first boot never completes** → the sentinel is written last; document that the provisioning file should only contain a password that is rotated if the device is lost.
- **Image grows over time** → apt cleanup and no docs/recommends; assert an upper size bound in the task.
- **`ProtectSystem=strict` can break future device access** → keep the writable-path list explicit and covered by the on-device smoke test.

## Migration Plan

1. Build a candidate image with the current release and boot it on the Zero.
2. Confirm WiFi, service start, display output, `apt-get update`, and SSH over the tunnel.
3. Confirm `unattended-upgrade --dry-run -d` lists the project origin and reports no pending changes, and that `apt-daily-upgrade.timer` is enabled.
4. Flash a second card for the Zero 2 W target (same image).
5. Publish the image only after both boots succeed.

Rollback is re-flashing the previous published image; a package-level downgrade is an explicit operator command using a retained version.

## Open Questions

- Whether to keep a serial console enabled on the image for recovery; decide during hardware testing and record the choice in `docs/imaging.md`.
