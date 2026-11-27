# Tasks

## 1. Image scaffold

- [ ] 1.1 Create the pi-gen stage under `image/` pinning the pi-gen revision and `RELEASE=trixie`; verify `mise run image` reaches the stage output directory
- [ ] 1.2 Add a `.dockerignore`/build wrapper for the privileged Docker requirements and an `IMAGE_VERSION` argument that selects the package version; verify the build runs on the development host from a clean clone
- [ ] 1.3 Document build prerequisites, the version argument, and output in `docs/imaging.md`; verify the documented command produces an `.img.zst`

## 2. Payload installation

- [ ] 2.1 Write the apt source, origin pin, and `90weather-pi` configuration into the stage and verify `apt-get update` inside the chroot verifies the signed repository
- [ ] 2.2 Install `weather-pi` and `weather-pi-archive-keyring` at the pinned version inside the chroot; verify `dpkg-query -W` reports exactly that version and `dpkg -V` is clean
- [ ] 2.3 Assert the build fails when the repository key is absent or a package is corrupted; verify with a deliberately broken local repository
- [ ] 2.4 Install `unattended-upgrades`, enable periodic updates and unattended upgrades in `20auto-upgrades`, confirm `APT::Keep-Downloaded-Packages` is effective, and verify `apt-daily-upgrade.timer` is enabled after boot
- [ ] 2.5 Add the `weather-pi` origin to the unattended-upgrades allowlist without replacing the distribution's origins; verify `unattended-upgrade --dry-run -d` lists both and that a newer project package is a candidate

## 3. Runtime and first-boot behaviour

- [ ] 3.1 Install and enable the application unit with `weather-pi` user, `spi`/`gpio` groups, `Type=simple`, `Restart=on-failure`, and no `chrt`; verify `systemd-analyze verify` and a real boot
- [ ] 3.2 Install config templates and assets through the package, enable SPI, and verify the service starts with the sample config on hardware
- [ ] 3.3 Implement `weather-pi-firstboot.service` and its provisioning parser for hostname, WiFi, SSH keys, and tunnel target; verify each field is applied on a fresh card
- [ ] 3.4 Make provisioning idempotent with a sentinel and preserve existing identities; verify a second boot changes nothing
- [ ] 3.5 Remove secret fields from the boot partition after success and document rotation; verify the file no longer contains the passphrase
- [ ] 3.6 Assert the secret-free property in the build (grep for key headers, passphrases, and the archive private key) and verify a build with a planted test secret fails
- [ ] 3.7 Write `/etc/weather-pi/build-info` with base release, pi-gen revision, repository date, and package versions; verify it is present and correct after boot

## 4. Output and publication

- [ ] 4.1 Emit `.img.zst`, `SHA256SUMS`, and a detached minisign signature; verify both from a clean download
- [ ] 4.2 Add an on-device smoke test that checks service active state, network, display initialisation, and a no-change unattended-upgrades dry run; verify it fails when the unit is reverted

## 5. Hardware validation

- [ ] 5.1 Boot the image on a Pi Zero and on a Zero 2 W with a provisioning file; record display output, service state, network reachability, and update-check result
- [ ] 5.2 Re-flash and boot once more to confirm the image is unchanged by the first device; verify no device identity carried over
- [ ] 5.3 Verify the repository and pin survive a first boot and that a published newer package is seen by `apt-cache policy`

## Workflow follow-up

- Archive after both models pass hardware validation.
