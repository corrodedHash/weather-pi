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
# weather-pi 0.2.0-1 (arm-unknown-linux-gnueabihf)
```

## Repository layout

```
pool/main/w/weather-pi/weather-pi_0.2.0-1_armhf.deb
pool/main/w/weather-pi-archive-keyring/weather-pi-archive-keyring_0.2.0-1_armhf.deb
dists/trixie/Release
dists/trixie/InRelease
dists/trixie/main/binary-armhf/Packages{,.gz}
dists/trixie/main/binary-armhf/by-hash/{MD5Sum,SHA1,SHA256,SHA512}/<hash>
dists/trixie/main/binary-arm64/Packages{,.gz}
dists/trixie/main/binary-arm64/by-hash/{MD5Sum,SHA1,SHA256,SHA512}/<hash>
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

The public keyring under `packaging/keyring/` is not secret and should be
committed once the key exists. CI uses that file by default; the
`WEATHER_PI_ARCHIVE_KEYRING_B64` environment secret can override it during a
protected build.

Store `archive-private.asc` as the `WEATHER_PI_ARCHIVE_KEY` secret in the
protected GitHub Environment `release`. Protect the environment with required
reviewers and restrict it to tags. Delete the offline copy only after the
secret is confirmed; keep an offline backup in a safe place. The private key
must never enter the repository or a CI cache.

For an offline signing flow, keep the private key off CI entirely: run
`scripts/apt-repo.sh` on the offline machine with
`WEATHER_PI_GPG_HOME` pointing at the keyring, push the generated `apt` branch,
and create the GitHub Release manually with `gh release create` and
`gh release upload`. The tag-triggered workflow is the normal path.

## Cutting a release

1. Make sure `main` is green and `mise run check` passes.
2. Update `Cargo.toml` if the crate version should follow the tag.
3. Tag and push:

   ```sh
   git tag -s v0.2.0 -m "weather-pi 0.2.0"
   git push origin v0.2.0
   ```

4. CI runs checks, builds both architectures in parallel, verifies each
   package, checks the version against the published index, signs the
   repository, and restores the previous `apt` branch before regenerating it
   so retained versions survive. It then force-pushes the `apt` branch and
   creates the GitHub Release with the `.deb` files, `Packages-armhf`,
   `Packages-arm64`, `Release`, `InRelease`, and `SHA256SUMS`.
5. If any check fails, nothing is published; the previous `apt` tree keeps
   serving.

A local dry run with a throwaway key:

```sh
export WEATHER_PI_ARCHIVE_KEY="$(gpg --list-secret-keys --with-colons | awk -F: '/^sec:/ { print $5; exit }')"
WEATHER_PI_VERSION=0.0.0-1 mise run package
WEATHER_PI_VERSION=0.0.0-1 mise run repo
```

## Local package and repository verification

Two scripts verify the release artifacts without Docker or a device. Both use
`mktemp`, clean up after themselves, and never write outside `target/` or a
temporary directory. Run them on a Debian/Ubuntu host with `dpkg-dev`,
`apt-utils`, and `gnupg` installed:

```sh
mise install
scripts/test-package.sh
scripts/test-release-pipeline.sh
```

`scripts/test-package.sh` builds the host `x86_64-unknown-linux-gnu` package
with a throwaway archive key (or `WEATHER_PI_ARCHIVE_KEYRING` / the committed
`packaging/keyring/weather-pi-archive.gpg` if present), then checks the control
fields, architecture, file list, modes, conffiles, `md5sums`, maintainer
scripts, `systemd-analyze verify` under a temporary root, and finally runs
`weather-pi --version`. It builds and inspects the keyring package as well.
`systemd-analyze` is optional; that one check is skipped when it is not
installed. A successful run ends with:

```text
PASS: package checks passed for weather-pi 0.0.0-1 (amd64)
```

The same script can inspect CI artifacts without rebuilding. For a cross
package it skips executing the binary, but still checks every file and the unit:

```sh
scripts/test-package.sh --deb dist --arch armhf --version 0.2.0-1
scripts/test-package.sh --deb dist --arch arm64 --version 0.2.0-1
```

`scripts/test-release-pipeline.sh` checks the tag mapping (`v1.2.3` becomes
`1.2.3-1`), refuses equal and lower versions, generates a repository from dummy
packages in a temporary directory with a throwaway GPG key, and asserts:

- `Release` has `Origin`, `Suite`, `Codename`, `Valid-Until`, and
  `Acquire-By-Hash: yes`;
- `InRelease` verifies with `gpgv`;
- five versions per architecture survive retention, in Debian version order,
  and pruned versions disappear from both the pool and `Packages`;
- the `by-hash` copies match the hashes in `Release`.

A successful run ends with `PASS: release pipeline checks completed`. If
`dpkg`, `apt-ftparchive`, `gpg`, or `gpgv` is missing, the affected checks print
`SKIP:` with the reason and the script still exits 0. The release workflow runs
both scripts in the `package-check` job and runs the package inspector against
each matrix artifact.

## Integration check on a published repository

On a scratch Debian or Raspberry Pi OS host with the archive public key from
the key ceremony:

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

For an armhf or arm64 container (requires Docker or Podman on the host):

```sh
docker run --rm -it --platform linux/arm/v7 \
  --add-host=host.docker.internal:host-gateway \
  -v "$PWD:/src:ro" debian:trixie bash
```

Inside the container:

```sh
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg
install -d -m 0755 /usr/share/keyrings
cp /src/packaging/keyring/weather-pi-archive.gpg /usr/share/keyrings/
echo "deb [signed-by=/usr/share/keyrings/weather-pi-archive.gpg] \
https://corrodedhash.github.io/weather-pi/ trixie main" \
  > /etc/apt/sources.list.d/weather-pi.list
apt-get update
apt-get install -y weather-pi
weather-pi --version
dpkg -V weather-pi
```

Use `--platform linux/arm64` for the arm64 check. To test a locally generated
repository instead, publish a tree and point the container at the host:

```sh
# Host: package artifacts must already exist in dist/ for the target arch.
WEATHER_PI_ARCHIVE_KEY=<key-fingerprint> \
  DIST_DIR=dist REPO_DIR=target/repo scripts/apt-repo.sh
python3 -m http.server 8000 --directory target/repo
```

Then use `http://host.docker.internal:8000` as the `deb` URL. A container is a
good check for `apt-get update` and `apt-get install`; starting the service on a
real Pi is covered by the device-image integration tasks.

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
repository prunes an old version. Prefer the cached file when it is present:

```sh
sudo apt-get install /var/cache/apt/archives/weather-pi_<version>_<arch>.deb
```

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

The release workflow (`.github/workflows/release.yml`) runs on `v*` tags. The
`package` matrix and the `publish` job both use the protected environment
`release`, so environment secrets are available where they are needed.
Configure:

| Name                                        | Kind   | Purpose                                              |
| ------------------------------------------- | ------ | ---------------------------------------------------- |
| `WEATHER_PI_ARCHIVE_KEY`                    | secret | Armored private archive key used to sign `InRelease` |
| `WEATHER_PI_ARCHIVE_PASSPHRASE`             | secret | Passphrase for the archive key, if it has one        |
| `WEATHER_PI_ARCHIVE_KEYRING_B64`            | secret | Optional override for the committed public keyring |

Create the public-keyring value once if you want the protected environment to
override the committed file (the public key is not sensitive, but the override
keeps a fork from building a keyring package with an unexpected trust anchor):

```sh
base64 -w0 packaging/keyring/weather-pi-archive.gpg
```

The package job uses `WEATHER_PI_ARCHIVE_KEYRING_B64` when it is set and
otherwise falls back to `packaging/keyring/weather-pi-archive.gpg` from the
checkout, so a fork can still build packages after the key ceremony commits the
public key.

The workflow runs the checks and the host package/repository tests first. For
each matrix entry it builds the application and keyring packages, verifies the
package contents, and only then uploads the artifact. The publish job refuses a
version that is not strictly greater than the served `Packages` indexes (and the
restored `apt` branch), restores the existing `apt` branch so the five-version
retention window spans releases, imports the key, generates and signs
`target/repo`, force-pushes it, and attaches these files to the GitHub Release:

```text
weather-pi_<version>_armhf.deb
weather-pi_<version>_arm64.deb
weather-pi-archive-keyring_<version>_armhf.deb
weather-pi-archive-keyring_<version>_arm64.deb
SHA256SUMS
Release
InRelease
Packages-armhf
Packages-arm64
```

The two `Packages` assets are renamed because GitHub Release asset names must be
unique. Point GitHub Pages at the `apt` branch (root) so clients fetch the
repository over HTTPS. If the repository is hosted elsewhere, set
`WEATHER_PI_REPO_URL` in the workflow and update the source line template.

## Missing tools

`scripts/build-packages.sh` and `scripts/apt-repo.sh` fail with the name of the
missing tool instead of producing a partial artifact. `scripts/test-package.sh`
and `scripts/test-release-pipeline.sh` report missing tools as `SKIP:` and exit
0 so they are usable on a development host; the release workflow installs
`dpkg-dev`, `apt-utils`, and `gnupg` on an Ubuntu runner, so its checks run
fully.
