# Proposal

## Why

There is no repeatable way to get a blank SD card to a working, configured device. Installing the binary, unit, assets, display configuration, and network access by hand is undocumented, easy to get wrong, and cannot carry secrets safely.

## What Changes

- Build a bootable, dd-able image for the Pi Zero family from a declarative pi-gen stage.
- Install a verified release binary, the systemd unit, config templates, and BMP assets into defined paths.
- Run the service as an unprivileged user with the minimum group access it needs for SPI and GPIO.
- Enable SPI, configure a minimal package set, and validate the sample configuration during the build.
- Provision WiFi, SSH authorized keys, hostname, and tunnel settings from a file on the FAT boot partition at first boot; bake no secrets into the image.
- Publish the image compressed with a SHA-256 checksum and a signature, and record build inputs in the image.
- Add a `mise run image` task that performs the build in Docker.

## Capabilities

### New Capabilities

- `device-image`: a reproducible bootable image that runs the service on first boot with no manual steps and no embedded secrets.

### Modified Capabilities

<!-- None: the image is a new delivery mechanism; release-toolchain behavior is unchanged. -->

## Impact

- New: `image/` (pi-gen stage, first-boot script, config templates), `docs/imaging.md`, `mise.toml` image task
- Uses the release artifacts from `add-release-pipeline`; the build fails if the artifact signature does not verify
- Depends on `add-signed-updater` for the timer/service that must be enabled in the image
- Affects `assets/weather-pi.service` and the config path migration
