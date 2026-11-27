# Design

## Context

See `proposal.md` for motivation. Current constraints:

- `src/main.rs` uses `#![feature(iter_intersperse)]`, so the project needs a nightly compiler, but no toolchain file exists. The default toolchain on the development host is stable 1.100.0.
- `build.sh` calls `cross build --target arm-unknown-linux-gnueabihf --release`; `.cargo/config.toml` has the target and linker entries commented out.
- The repository is public on GitHub (`corrodedHash/weather-pi`), so the package repository must be readable without a token.
- One physical device exists; the device runs Raspberry Pi OS armhf, and both armv6 and aarch64 must remain supported.
- An x86_64 build path exists for the embedded-graphics simulator and must keep working locally.

## Goals / Non-Goals

**Goals:**

- One documented command per target that a fresh checkout can run.
- Package artifacts that a stock `apt` installs, verifies, downgrades, and audits without custom client code.
- One artifact consumed by both the device and the image build.

**Non-Goals:**

- Bit-for-bit reproducible rebuilds of the Rust binaries or the packages (timestamps and dependency builds make this costly; not needed for the trust model).
- Building the disk image in this change (see `add-device-image`).
- Implementing the update policy, schedule, and recovery workflow (see `add-unattended-upgrades`).
- Signing boot artifacts or kernel images (RAUC/Mender remain out of scope).

## Decisions

### Toolchain pin: `rust-toolchain.toml` over mise-only

`rust-toolchain.toml` is read by rustup, cargo, editors, and mise, so it remains authoritative even when a command bypasses mise. mise complements it by pinning auxiliary tools and defining tasks. Alternative: declare the toolchain only in `mise.toml`; rejected because direct `cargo` invocations and IDE tooling would use the wrong compiler.

Pin a dated nightly (for example `nightly-2026-11-20`) rather than the rolling `nightly` channel, so a re-run of CI months later uses the same compiler. Updating the date is an explicit commit.

### Task runner: mise

Add `mise.toml` with tasks `check`, `build:armv6`, `build:arm64`, `package`, `repo`, `sim`, and `release`. Tasks call cargo/cross/cargo-deb directly and are usable in CI. mise also pins `cross`, `cargo-deb`, `dpkg-dev`, `apt-ftparchive`, `gpg`, and `minisign` (the last one only for image signatures, which `add-device-image` produces). OpenSpec has no registry short name, so it is pinned as `npm:@fission-ai/openspec@<version>` (it needs Node ≥22.20, which mise can also manage). Alternative: a Makefile; rejected because mise is already the user's tool of choice.

### Debian packages, not tarballs

`cargo-deb` produces `weather-pi_<version>_<arch>.deb` with almost no packaging code: the binary has no runtime dependencies, the unit and assets are static, and conffiles cover the sample configuration. A tarball would need a custom install path, a custom file inventory, and a custom integrity check, all of which `dpkg` already provides (`dpkg -L`, `dpkg -V`, `dpkg-query -W`).

Package split:

- `weather-pi` — binary, unit, assets, sample configuration.
- `weather-pi-archive-keyring` — repository trust anchor; see key rotation below.

Both packages share one version derived from the tag, so an operator can tell which image state a device came from. `Architecture: armhf` for armv6/armv7 and `arm64` for aarch64; no `any`/`all` games, because the repository is small.

### Version mapping: tag to Debian version

`vX.Y.Z` becomes upstream version `X.Y.Z` with Debian revision `-1` (`weather-pi_0.2.1-1_armhf.deb`). A packaging-only fix bumps the revision, an application change bumps upstream. CI refuses to publish a version that is not strictly greater than every version already in the published repository, using `dpkg --compare-versions`. This keeps the "never silently reinstall an older version" property that the previous manifest `seq` was meant to give, without inventing a parallel counter.

### Signed apt repository over a signed custom manifest

The repository is a standard flat-to-`dists` layout served over HTTPS:

```
pool/main/w/weather-pi/weather-pi_0.2.1-1_armhf.deb
dists/trixie/main/binary-armhf/Packages{,.gz}
dists/trixie/main/binary-arm64/Packages{,.gz}
dists/trixie/Release
dists/trixie/InRelease
```

`Release` is generated with `apt-ftparchive release`, given `Origin: weather-pi`, `Suite: trixie`, `Codename: trixie`, `Valid-Until: <now + 7 days>`, `Acquire-By-Hash: yes`, then clearsigned with the archive key. `InRelease` is uploaded last, so a client never sees metadata that references packages that are not yet present. Alternatives considered:

- **Signed JSON manifest + minisign (previous design)**: requires a custom client, custom signature verification, custom anti-rollback state, and a custom installer; provides nothing apt does not already provide, and has no downgrade semantics.
- **`reprepro` or `aptly`**: better for a large pool or multiple distributions; for one suite and a handful of versions, `apt-ftparchive` plus `gpg` is fewer moving parts and fully inspectable. Revisit if the pool grows or a second suite appears.

### Repository integrity and the replay window

apt verifies the `InRelease` signature and every file's SHA-256 from `Release`/`Packages`; a corrupted or unsigned download is refused and the installed package is untouched. `Acquire::Check-Valid-Until` is enabled on the device, and `Valid-Until` is 7 days, so a replayed older metadata snapshot stops being installable shortly after it was superseded.

Residual risk, accepted for one device: an attacker who controls the repository and the signing key, or can serve an old snapshot within the validity window, could present an older but validly signed release. There is no separate monotonic counter; the version comparison plus a short `Valid-Until` plus explicit-operator downgrades are the whole defense. This is documented rather than engineered around.

### Retain published versions for rollback

The repository pool keeps the last five published versions per architecture, and the `Packages` index lists all of them. `apt-get install weather-pi=<old-version> --allow-downgrades` then works without any custom rollback storage. Older versions are pruned by the `repo` task after publication; the image and the device additionally keep their downloaded archives (`APT::Keep-Downloaded-Packages "true"`), so a rollback survives a repository prune.

### Key handling and rotation

A dedicated archive key (`weather-pi archive <year>`), not the maintainer's personal key and not the release-binary key. It signs `Release` only.

- Public half is shipped in the image as `/usr/share/keyrings/weather-pi-archive.gpg` and referenced with `signed-by=` in `/etc/apt/sources.list.d/weather-pi.list`.
- Rotation: publish a new `weather-pi-archive-keyring` version containing both keys, signed by the old key; devices pick it up as a normal package update. The image ships both keys during the overlap.
- Private key lives in a protected GitHub Environment with required reviewers, or is used offline with the signed `InRelease` pushed by a `workflow_dispatch` job. Never in the repository or in an unprotected secret.

### Publication target

GitHub Pages from a dedicated `apt` branch (CI force-pushes the regenerated tree), which gives HTTPS for free and keeps the device free of credentials. Alternative: object storage (S3/R2); rejected for now as extra infrastructure and credentials for the same result. If Pages' soft size limit becomes a problem, the pool is pruned harder — packages are a few megabytes each.

### SHA256SUMS and GitHub Release assets

Every tag still attaches the `.deb` files, `Packages`, `Release`, `InRelease`, and `SHA256SUMS` to the GitHub Release for archival and for the image build's independent verification. `SHA256SUMS` is redundant with `Release` but is what a human or a shell script reads most easily.

### Include packaging fixes in this change

A release that cannot start is not a release. The unit file gains the missing app argument, drops `chrt` (no realtime requirement), runs as `weather-pi` with `spi`/`gpio` groups, and the sample config is corrected to `watched_ips`.

## Risks / Trade-offs

- **Signing key compromise** → offline or protected-environment key, keyring rotation package, and the device only trusts keys shipped by the project.
- **Repository replay within `Valid-Until`** → accepted for one device; keep the window short, document the limit, and never install a downgrade except through the explicit rollback path.
- **GitHub Pages availability or CDN caching** → `Acquire-By-Hash` plus uploading `InRelease` last; a failed check leaves the previous metadata serving.
- **Package version regression** → CI compares against the published `Packages` index and refuses to publish a non-increasing version.
- **Nightly compiler drift breaks the build later** → dated nightly pin, updated deliberately.
- **Two architectures double CI time** → cache the cross container and cargo registry; armhf and arm64 builds run in parallel.
- **Path move breaks an existing card** → read `/etc/skyscreen` and `/usr/share/skyscreen` as a fallback for one release and log a deprecation warning.

## Migration Plan

1. Land toolchain pin, packaging, and the packaging fixes; verify the current device still starts with `/etc/skyscreen` present.
2. Create the archive key and publish an empty signed repository; verify `apt-get update` succeeds on a scratch Raspberry Pi OS container.
3. Cut `v0.2.0`; CI publishes the application and keyring packages.
4. Point the image change at the pinned version.
5. Remove the legacy path fallback in the following minor release.

## Open Questions

- Exact nightly date: confirm by running `mise run check` against a candidate before committing it.
- Whether GitHub Pages will serve a repository large enough after a year of releases; measure at the third release and prune or move hosting if needed.
