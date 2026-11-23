# Design

## Context

See `proposal.md`. Constraints that shape the approach:

- The existing binary targets `arm-unknown-linux-gnueabihf` (armv6). Raspberry Pi OS 32-bit runs on Zero, Zero W, and Zero 2 W, so one image can serve all three; a 64-bit image would exclude the original Zero.
- The device is headless, connects over WiFi, and sits behind NAT.
- The release pipeline produces signed artifacts and a manifest; the image build must consume, not rebuild, them.
- The current unit file is not startable: it passes no app argument and runs as root with `chrt`.
- Trixie uses NetworkManager for WiFi; older Bookworm recipes based on `wpa_supplicant.conf` will not apply.

## Goals / Non-Goals

**Goals:**

- One armhf image that works on every supported model.
- First boot to a running service with only a provisioning file added to the boot partition.
- Image builds reproducible enough to identify exactly what shipped.

**Non-Goals:**

- 64-bit image variants.
- Whole-disk A/B updates or signed boot (RAUC); the app binary updater covers the software we change most.
- Multiple device profiles or a fleet provisioning server.

## Decisions

### Image builder: pi-gen (master, armhf/trixie) in Docker

pi-gen is the tool that produces Raspberry Pi OS, supports armhf, and is routinely run on x86 through Docker and QEMU. Alternative: `rpi-image-gen` is more declarative and better for bespoke images, but its supported host is native arm64 Raspberry Pi OS and armhf cross builds are less proven; it can be revisited if ARM64 becomes the only target.

Pin the pi-gen revision in the image task so the base does not move under us.

### One armhf image, both architectures still built

Because 32-bit userspace runs on armv8, a single armhf image covers the whole Zero family. The release pipeline still builds aarch64 so the device can move to 64-bit later without changing the update format.

### First boot reads `/boot/firmware/weather-pi.cfg`

A small `weather-pi-firstboot.service` runs before the app, parses a TOML file from the FAT partition, and applies:

- hostname
- WiFi SSID/passphrase via `nmcli` (or a generated NetworkManager keyfile)
- `authorized_keys` for the admin user
- tunnel target (VPS host/port/user)
- application config overrides, if present

It then deletes the secret fields from the boot partition and marks itself done with a sentinel. Re-running without secrets leaves state untouched. This keeps one published image valid for every device and avoids committing or distributing secrets.

Alternative considered: Raspberry Pi Imager's `custom.toml` preconfiguration. Rejected because the workflow is `dd`, not Imager, and because it does not cover tunnel settings.

### Minimal package set

Install only: `ca-certificates`, `curl`, `iputils-ping` (the greeter shells out to `ping`), `openssh-client` and `openssh-server` for the tunnel, `zstd` at build time only, and the base Lite packages. Enable SPI with `raspi-config nonint do_spi 0` in the stage. No compilers or development tools in the image.

### Runtime hardening

`User=weather-pi`, `SupplementaryGroups=spi gpio`, `Restart=on-failure`, `StateDirectory=weather-pi`, `NoNewPrivileges=yes`, `ProtectSystem=strict`, `ProtectHome=yes`, and `ReadWritePaths=/var/lib/weather-pi`. Do not set a capability bounding set that would break `/dev/gpiochip` or `/dev/spidev` access. Drop `chrt`; the app has no realtime requirement and cannot take `CAP_SYS_NICE`.

### Configuration layout

- `/etc/weather-pi/<app>.toml` — templates installed by the package.
- `/usr/share/weather-pi/*.bmp` — assets.
- `/etc/weather-pi/update.pub` — release public key.
- `/var/lib/weather-pi/` — update state and logs.

The binary reads `/etc/weather-pi` first and falls back to `/etc/skyscreen` for one release.

### Image integrity

The image task downloads the release manifest, verifies it against the public key, downloads the armv6 archive, verifies its hash, and installs it. The build then writes `/etc/weather-pi/build-info` with the base release, pi-gen revision, release version, and installed package versions. Output is `.img.zst`, `SHA256SUMS`, and a detached signature.

### Reproducibility level

The image is rebuildable but not bit-identical: Debian package repositories move and pi-gen timestamps the filesystem. Pinning pi-gen and recording package versions is the practical middle ground; `SOURCE_DATE_EPOCH` is set to make timestamps stable where pi-gen honors it.

## Risks / Trade-offs

- **Building images needs privileged Docker/loop devices** → document the requirement and keep the task opt-in; CI image builds are manual initially.
- **NetworkManager behavior differs across releases** → pin the release branch (`trixie`), test the firstboot path on real hardware, and keep the WiFi step idempotent.
- **Secrets left on the FAT partition if first boot never completes** → the sentinel is written last; document that the provisioning file should only contain a password that is rotated if the device is lost.
- **Image grows over time** → apt cleanup and no docs/recommends; assert an upper size bound in the task.
- **`ProtectSystem=strict` can break future device access** → keep the list of writable paths explicit and covered by the on-device smoke test.

## Migration Plan

1. Build a candidate image with the current release and boot it on the Zero.
2. Confirm WiFi, service start, display output, and SSH over the tunnel.
3. Flash a second card for the Zero 2 W target (same image).
4. Publish the image only after both boots succeed.

Rollback is re-flashing the previous published image; the app-level rollback is handled by the updater.

## Open Questions

- Whether to keep a serial console enabled on the image for recovery; decide during hardware testing and record the choice in `docs/imaging.md`.
