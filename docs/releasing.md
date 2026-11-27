# Releasing weather-pi

A release is a git tag `vX.Y.Z`. CI turns it into Debian packages for `armhf`
and `arm64`, signs the apt metadata, publishes the repository, and attaches the
packages to a GitHub Release. Devices install from the repository with stock
`apt`; nothing custom runs on the device to trust a release.

## Toolchain and local build

`rust-toolchain.toml` pins the dated nightly. `mise run check` must pass before a
tag is cut. `mise run package` builds all packages into `dist/`; `mise run repo`
turns `dist/` into a signed repository tree under `target/repo/`.

Local packaging and signing need Debian tooling that mise does not manage:

```sh
# Debian/Ubuntu host
sudo apt-get install dpkg-dev apt-utils gnupg

# Arch host: use a Debian container, or run the packaging inside CI
docker run --rm -it -v "$PWD:/src" -w /src debian:trixie bash
```

`cross` needs Docker or Podman. The build tasks fail if no container runtime is
available rather than silently producing a host binary.

## Version mapping

| Tag       | Debian version | Package file                          |
| --------- | -------------- | ------------------------------------- |
| `v0.2.0`  | `0.2.0-1`      | `weather-pi_0.2.0-1_armhf.deb`        |
| `v0.2.1`  | `0.2.1-1`      | `weather-pi_0.2.1-1_arm64.deb`        |

The upstream part is the tag. The Debian revision starts at `1`; a
packaging-only rebuild of the same upstream version bumps the revision. CI
refuses a tag whose version is not strictly greater than every version already
in the published repository, using `dpkg --compare-versions`:

```sh
scripts/version.sh check 0.2.0-1 published-Packages
```

`WEATHER_PI_VERSION` overrides the derived version for a local test build. The
binary reports the same string plus its target triple:

```sh
weather-pi --version
# weather-pi 0.2.0 (arm-unknown-linux-gnueabihf)
```

## Repository layout

```
pool/main/w/weather-pi/weather-pi_0.2.0-1_armhf.deb
pool/main/w/weather-pi-updater/weather-pi-updater_0.2.0-1_armhf.deb
pool/main/w/weather-pi-archive-keyring/weather-pi-archive-keyring_0.2.0-1_armhf.deb
dists/trixie/Release
dists/trixie/InRelease
dists/trixie/main/binary-armhf/Packages{,.gz}
dists/trixie/main/binary-armhf/by-hash/SHA256/<hash>
dists/trixie/main/binary-arm64/Packages{,.gz}
dists/trixie/main/binary-arm64/by-hash/SHA256/<hash>
```

`Release` carries `Origin: weather-pi`, `Suite: trixie`, `Codename: trixie`,
`Acquire-By-Hash: yes`, and a `Valid-Until` seven days after generation.
`InRelease` is the clearsigned `Release` and is published last, so a client
never sees metadata for packages that are not yet uploaded.

GitHub Pages serves the `apt` branch at
`https://corrodedhash.github.io/weather-pi/`. `Acquire-By-Hash` makes CDN
caching safe: clients request the hash they were told about, and `InRelease`
changing is the only switch.

## Archive key ceremony

Use a dedicated archive key, not a personal or release-signing key.

```sh
export GNUPGHOME="$(mktemp -d)"
chmod 700 "$GNUPGHOME"

gpg --batch --passphrase '' --quick-generate-key \
    "weather-pi archive 2026" rsa4096 sign 2y

gpg --list-secret-keys --keyid-format long
# note the key id, for example 0123456789ABCDEF

# Public half shipped to devices
gpg --export --armor 0123456789ABCDEF \
  | gpg --dearmor > packaging/keyring/weather-pi-archive.gpg

# Private key for the protected CI environment
gpg --export-secret-keys --armor 0123456789ABCDEF > archive-private.asc
```

Store `archive-private.asc` as the `WEATHER_PI_ARCHIVE_KEY` secret in the
protected GitHub Environment `release`. Protect the environment with required
reviewers and restrict it to tags. Delete the offline copy only after the
secret is confirmed; keep an offline backup in a safe place. The private key
must never enter the repository or a CI cache.

For an offline signing flow, keep the private key off CI entirely: run
`scripts/apt-repo.sh` on the offline machine with
`WEATHER_PI_GPG_HOME` pointing at the keyring, then push the `apt` branch and
publish with `workflow_dispatch`.

## Cutting a release

1. Make sure `main` is green and `mise run check` passes.
2. Update `Cargo.toml` if the crate version should follow the tag.
3. Tag and push:

   ```sh
   git tag -s v0.2.0 -m "weather-pi 0.2.0"
   git push origin v0.2.0
   ```

4. CI runs checks, builds both architectures in parallel, builds all packages,
   verifies the version is newer than the published one, signs the repository,
   force-pushes the `apt` branch, and creates the GitHub Release with the `.deb`
   files, `Packages`, `Release`, `InRelease`, and `SHA256SUMS`.
5. If any check fails, nothing is published; the previous `apt` tree keeps
   serving.

A local dry run with a throwaway key:

```sh
export WEATHER_PI_ARCHIVE_KEY="$(gpg --list-secret-keys --with-colons | awk -F: '/^sec:/ { print $5; exit }')"
WEATHER_PI_VERSION=0.0.0-1 mise run package
WEATHER_PI_VERSION=0.0.0-1 mise run repo
```

## Verification

On a scratch Debian or Raspberry Pi OS host:

```sh
sudo install -d -m 0755 /usr/share/keyrings
sudo cp packaging/keyring/weather-pi-archive.gpg /usr/share/keyrings/
echo "deb [signed-by=/usr/share/keyrings/weather-pi-archive.gpg] \
https://corrodedhash.github.io/weather-pi/ trixie main" \
  | sudo tee /etc/apt/sources.list.d/weather-pi.list

sudo apt-get update
apt-cache policy weather-pi
sudo apt-get install weather-pi
weather-pi --version
dpkg -V weather-pi
```

A tampered index or package makes `apt-get update` or the install fail; the
installed version is left untouched. An expired `Valid-Until` makes apt refuse
the repository.

## Downgrades and retention

The repository retains the five newest versions per architecture. To roll back
deliberately:

```sh
apt-cache madison weather-pi
sudo apt-get install --allow-downgrades weather-pi=<version>
```

The device also keeps downloaded archives
(`APT::Keep-Downloaded-Packages "true"`), so a rollback still works after the
repository prunes an old version. The update wrapper prefers
`/var/cache/apt/archives` before falling back to the repository.

There is no separate anti-rollback counter. The defenses are the seven-day
`Valid-Until` window, the repository signature, and explicit operator action
for downgrades. See the design notes for the accepted replay risk.

## Key rotation

1. Generate the new archive key offline.
2. Build a `weather-pi-archive-keyring` package that contains **both** the old
   and new public keys, and a repository release signed by the current key.
3. Publish that keyring version. Devices update it as a normal package, since
   it is still signed by the key they already trust.
4. Sign subsequent repository metadata with the new key.
5. After every device has the keyring package, publish a keyring package with
   only the new key.

The image ships both keys during the overlap, so a rotation never requires
reflashing.

## CI configuration

The release workflow (`.github/workflows/release.yml`) runs on `v*` tags and
uses the protected environment `release` for publishing. Configure:

| Name                                        | Kind   | Purpose                                              |
| ------------------------------------------- | ------ | ---------------------------------------------------- |
| `WEATHER_PI_ARCHIVE_KEY`                    | secret | Armored private archive key used to sign `InRelease` |
| `WEATHER_PI_ARCHIVE_PASSPHRASE`             | secret | Passphrase for the archive key, if it has one        |
| `WEATHER_PI_ARCHIVE_KEYRING_B64`            | secret | Base64 of the binary public keyring for the packages |

Create the public-keyring value once:

```sh
base64 -w0 packaging/keyring/weather-pi-archive.gpg
```

The workflow checks the version against the currently served `Packages`
indexes, imports the key, generates `target/repo`, force-pushes it to the `apt`
branch, then attaches the packages and metadata to the GitHub Release. Point
GitHub Pages at the `apt` branch (root) so clients fetch the repository over
HTTPS. If the repository is hosted elsewhere, set `WEATHER_PI_REPO_URL` in the
workflow and update the source line template.

## Missing tools

`scripts/build-packages.sh` and `scripts/apt-repo.sh` fail with the name of the
missing tool instead of producing a partial artifact. The release workflow uses
an Ubuntu runner and installs `dpkg-dev`, `apt-utils`, and `gnupg`, so the CI
path has the full toolset.
