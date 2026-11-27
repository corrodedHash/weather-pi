# Spec Delta

## Purpose

Provides a reproducible bootable image that brings a blank SD card to a working, remotely reachable, updatable device without manual installation and without embedding secrets.

## ADDED Requirements

### Requirement: Bootable image for supported hardware

The project SHALL produce a compressed disk image that boots on Raspberry Pi Zero, Zero W, and Zero 2 W and starts the configured application without manual installation.

#### Scenario: First boot on a Pi Zero

- **WHEN** the image is written to an SD card, inserted into a Pi Zero, and powered on with network credentials supplied on the boot partition
- **THEN** the device joins the network and the configured weather-pi application runs under systemd

#### Scenario: First boot on a Zero 2 W

- **WHEN** the same image is written to an SD card and booted in a Zero 2 W
- **THEN** the device reaches the same running state as on a Pi Zero

### Requirement: Unprivileged runtime

The application SHALL run as a dedicated, non-root user with access to the SPI and GPIO devices limited to the groups that own them.

#### Scenario: Service identity

- **WHEN** the running service's user and groups are inspected
- **THEN** it runs as the `weather-pi` user in the `spi` and `gpio` groups and is not running as root

### Requirement: Secret-free image

The image SHALL contain no device-specific WiFi password, SSH private key, tunnel private key, or host key, and first-boot provisioning MUST take those values from a file on the FAT boot partition.

#### Scenario: Inspect shipped image

- **WHEN** the published image is mounted or string-searched
- **THEN** no WiFi passphrase, private key, or per-device shared secret is present

#### Scenario: Provision from boot partition

- **WHEN** the boot partition contains a valid provisioning file and the device boots for the first time
- **THEN** the device applies the network, SSH key, hostname, and tunnel settings, then removes the secrets from the boot partition

### Requirement: Idempotent provisioning

First-boot provisioning SHALL be safe to re-run and SHALL NOT overwrite an existing device identity or authorized keys without an explicit marker.

#### Scenario: Provisioning runs twice

- **WHEN** the provisioning service runs again after a successful first boot
- **THEN** existing network configuration, host keys, and authorized keys are preserved and the service exits successfully

### Requirement: Installed layout

The image SHALL install the application and archive keyring packages in fixed documented paths, and the application MUST start using the shipped sample configuration.

#### Scenario: Installed paths

- **WHEN** the image is mounted
- **THEN** the binary is at `/usr/bin/weather-pi`, assets under `/usr/share/weather-pi`, configuration under `/etc/weather-pi`, the archive key at `/usr/share/keyrings/weather-pi-archive.gpg`, and the unit at `/usr/lib/systemd/system/weather-pi.service`

#### Scenario: Sample config is valid

- **WHEN** the service starts with the shipped sample configuration
- **THEN** the configuration parses and the application starts instead of exiting with a deserialization error

### Requirement: Verified package payload

The image build SHALL install only packages that resolve from repository metadata verifying against the shipped archive key, and MUST fail the build otherwise.

#### Scenario: Tampered repository metadata

- **WHEN** the repository `InRelease` or a package hash does not verify during the build
- **THEN** the image build aborts and no image is produced

#### Scenario: Pinned version unavailable

- **WHEN** the requested package version is missing from the repository
- **THEN** the build fails and names the missing version

### Requirement: Update-ready image

The image SHALL ship the archive keyring, the signed repository source, the origin pin, the download-cache configuration, periodic unattended-upgrade enablement, and an unattended-upgrades allowlist containing the project origin while preserving the distribution's own origins.

#### Scenario: Update path present after first boot

- **WHEN** the freshly booted device is inspected
- **THEN** `apt-get update` verifies the repository, `apt-daily-upgrade.timer` is enabled, and `unattended-upgrade --dry-run -d` lists the project origin

#### Scenario: Origin pin

- **WHEN** any package from the project repository is considered
- **THEN** apt resolves it from the pinned `o=weather-pi` origin and not from a Debian origin

### Requirement: Publishable and auditable output

The image build SHALL emit a compressed image, a SHA-256 checksum, a detached signature, and a `build-info` file recording the base distribution, repository date, package versions, and application version.

#### Scenario: Consume an image

- **WHEN** a maintainer downloads a published image
- **THEN** the checksum and signature verify and the image's `/etc/weather-pi/build-info` names the source release, base distribution, and installed package versions
