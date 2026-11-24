# Proposal

## Why

There is no repeatable way to get a blank SD card to a working, configured device. Installing the package, unit, assets, display configuration, network access, and update path by hand is undocumented, easy to get wrong, and cannot carry secrets safely.

## What Changes

- Build a bootable, dd-able image for the Pi Zero family from a declarative pi-gen stage.
- Install `weather-pi` and `weather-pi-updater` at pinned versions from the project's signed apt repository, with the archive key, `signed-by` source, and origin pinning in place.
- Enable the update timer, ship the download cache, and enable the boot-time dpkg recovery unit so the device can update and recover without manual setup.
- Run the service as an unprivileged user with the minimum group access it needs for SPI and GPIO.
- Enable SPI, configure a minimal package set, and validate the sample configuration during the build.
- Provision WiFi, SSH authorized keys, hostname, and tunnel settings from a file on the FAT boot partition at first boot; bake no secrets into the image.
- Publish the image compressed with a SHA-256 checksum and a signature, and record the base release, repository state, package versions, and pi-gen revision in `build-info`.
- Add a `mise run image` task that performs the build in Docker.

## Capabilities

### New Capabilities

- `device-image`: a reproducible bootable image that runs the service on first boot with no manual steps, no embedded secrets, and a working verified update path.

### Modified Capabilities

<!-- None: the image is a new delivery mechanism; release-toolchain behavior is unchanged. -->

## Impact

- New: `image/` (pi-gen stage, first-boot script, apt configuration, config templates), `docs/imaging.md`, `mise.toml` image task
- Uses the packages, repository, and keyring from `add-release-pipeline`; the build fails if repository metadata does not verify
- Depends on `add-signed-updater` for the updater package, timer, and recovery unit that must be enabled in the image
- Affects `assets/weather-pi.service` and the config path migration
