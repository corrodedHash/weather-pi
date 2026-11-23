# Tasks

## 1. Image scaffold

- [ ] 1.1 Create the pi-gen stage under `image/` pinning the pi-gen revision and `RELEASE=trixie`; verify `mise run image` reaches the stage output directory
- [ ] 1.2 Add a `.dockerignore`/build wrapper for the privileged Docker requirements; verify the build runs on the development host from a clean clone
- [ ] 1.3 Document build prerequisites and output in `docs/imaging.md`; verify the documented command produces an `.img.zst`

## 2. Installed payload

- [ ] 2.1 Install the verified armv6 release archive into `/usr/bin/weather-pi` and assets into `/usr/share/weather-pi`; verify `dpkg -L`-equivalent file list matches the documented layout
- [ ] 2.2 Add the corrected unit with `weather-pi` user, `spi`/`gpio` groups, state directory, and no `chrt`; verify `systemd-analyze verify` and a real boot
- [ ] 2.3 Install config templates into `/etc/weather-pi` and enable SPI; verify the service starts with the sample config on hardware
- [ ] 2.4 Assert the secret-free property in the build (grep for key headers/passphrases) and document it; verify a build with a planted test secret fails
- [ ] 2.5 Write `/etc/weather-pi/build-info` with base release, pi-gen revision, and artifact version; verify it is present and correct after boot

## 3. First-boot provisioning

- [ ] 3.1 Implement `weather-pi-firstboot.service` and its provisioning parser for hostname, WiFi, SSH keys, and tunnel target; verify each field is applied on a fresh card
- [ ] 3.2 Make provisioning idempotent with a sentinel and preserve existing identities; verify a second boot changes nothing
- [ ] 3.3 Remove secret fields from the boot partition after success and document rotation; verify the file no longer contains the passphrase
- [ ] 3.4 Add an on-device smoke test (hardware or QEMU where practical) that checks service active state, network, and display initialization; verify it fails when the unit is reverted

## 4. Verification of the supplied artifact

- [ ] 4.1 Verify the manifest signature and artifact SHA-256 in the image task and abort otherwise; verify a deliberately corrupted archive fails the build
- [ ] 4.2 Publish the image with `SHA256SUMS` and a minisign signature; verify both from a clean download

## 5. Hardware validation

- [ ] 5.1 Boot the image on a Pi Zero and on a Zero 2 W with a provisioning file; record display output, service state, and network reachability
- [ ] 5.2 Re-flash and boot once more to confirm the image is unchanged by the first device; verify no device identity carried over

## Workflow follow-up

- Archive after both models pass hardware validation.
