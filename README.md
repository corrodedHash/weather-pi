# Weather PI

Control software for a Raspberry Pi Zero with a Waveshare e-ink display. Very
individual use case: the applications watch the local network and draw the
result on the panel.

## Requirements

- [mise](https://mise.jdx.dev/) for the task runner and auxiliary tools.
- [rustup](https://rustup.rs/). `rust-toolchain.toml` pins the dated nightly the
  code needs; the first build downloads it automatically.
- A container runtime for `cross` (Docker or Podman) when building for the
  device architectures. Image builds need a **privileged** Docker daemon and a
  minisign key; see [docs/imaging.md](docs/imaging.md).
- Debian packaging tools (`dpkg-dev`, `apt-utils`, `gpg`) for building and
  signing packages locally. CI provides them; `mise` cannot install
  distribution packages.

Run `mise install` once to install the pinned tools (`cross`, `cargo-deb`,
`minisign`, `shellcheck`, Node and OpenSpec).

## Tasks

All builds go through mise so the repository's toolchain pin is used:

```sh
mise run check        # cargo fmt --check, clippy and tests
mise run sim          # run the greeter on the desktop simulator
mise run build:armv6  # release binary for armv6/armv7 (Pi Zero, armhf)
mise run build:arm64  # release binary for aarch64 (Pi Zero 2 W, arm64)
mise run package      # build the Debian packages into dist/
mise run repo         # regenerate and sign the apt repository
mise run image        # build the signed Raspberry Pi image (privileged Docker)
mise run deploy       # copy configuration and assets over the tunnel, restart
mise run status       # tunnel, service, package and update state
mise run release      # validate a tag, build packages, generate the repository
scripts/test-package.sh          # build and inspect a host package
scripts/test-release-pipeline.sh # version, signing and retention checks
```

`mise run deploy` and `mise run status` use the `weather-pi` SSH host alias;
remote access setup, the `~/.ssh/config` snippet and recovery commands are in
[docs/remote-access.md](docs/remote-access.md).

`./build.sh` remains as a thin wrapper around `mise run build:armv6`.

## Device image

One armhf image for the Pi Zero, Zero W, and Zero 2 W installs the application,
archive keyring, signed repository, and unattended-upgrades configuration, then
provisions WiFi, SSH keys, hostname, and the tunnel from
`/boot/firmware/weather-pi.cfg` on first boot. The image contains no
device-specific secrets. Build prerequisites, the `IMAGE_VERSION` argument,
signing, flashing, the provisioning file format, and the on-device smoke test
are documented in [docs/imaging.md](docs/imaging.md).

OpenSpec is pinned through mise:

```sh
mise x -- openspec list
```

## Configuration

The application reads its configuration from `/etc/weather-pi`:

- `/etc/weather-pi/greeter.toml`
- `/etc/weather-pi/countdown.toml`

Releases before the rename used `/etc/skyscreen`; that directory is still read
as a fallback with a deprecation warning for one release.

The binary reports its version and target triple:

```sh
weather-pi --version
```

## Updating

Devices install newer signed `weather-pi` packages through Debian's daily
`unattended-upgrades` job. Discovery, schedule, logs, pinning, downgrades, and
recovery are documented in [docs/updating.md](docs/updating.md).

## Releasing

Packages, the signed apt repository, key handling and the tag workflow are
documented in [docs/releasing.md](docs/releasing.md).
