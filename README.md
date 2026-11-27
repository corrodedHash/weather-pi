# Weather PI

Control software for a Raspberry Pi Zero with a Waveshare e-ink display. Very
individual use case: the applications watch the local network and draw the
result on the panel.

## Requirements

- [mise](https://mise.jdx.dev/) for the task runner and auxiliary tools.
- [rustup](https://rustup.rs/). `rust-toolchain.toml` pins the dated nightly the
  code needs; the first build downloads it automatically.
- A container runtime for `cross` (Docker or Podman) when building for the
  device architectures.
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
mise run release      # validate a tag, build packages, generate the repository
scripts/test-package.sh          # build and inspect a host package
scripts/test-release-pipeline.sh # version, signing and retention checks
```

`./build.sh` remains as a thin wrapper around `mise run build:armv6`.

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

## Releasing

Packages, the signed apt repository, key handling and the tag workflow are
documented in [docs/releasing.md](docs/releasing.md).
