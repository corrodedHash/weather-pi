# Design

## Context

See `proposal.md` for motivation. Current constraints:

- `src/main.rs` uses `#![feature(iter_intersperse)]`, so the project needs a nightly compiler, but no toolchain file exists. The default toolchain on the development host is stable 1.100.0.
- `build.sh` calls `cross build --target arm-unknown-linux-gnueabihf --release`; `.cargo/config.toml` has the target and linker entries commented out.
- The repository is public on GitHub (`corrodedHash/weather-pi`), so release assets must be downloadable without a token.
- One physical device exists, but both armv6 and aarch64 must remain supported.
- An x86_64 build path exists for the embedded-graphics simulator and must keep working locally.

## Goals / Non-Goals

**Goals:**

- One documented command per target that a fresh checkout can run.
- Release metadata that the image build and updater can verify without trusting GitHub alone.
- Keep the developer loop fast: checks and the simulator build stay native.

**Non-Goals:**

- Bit-for-bit reproducible rebuilds of the Rust binaries (timestamps and dependency builds make this costly; not needed for the trust model).
- Building the disk image in this change (see `add-device-image`).
- Designing the update client (see `add-signed-updater`).

## Decisions

### Toolchain pin: `rust-toolchain.toml` over mise-only

`rust-toolchain.toml` is read by rustup, cargo, editors, and mise, so it remains authoritative even when a command bypasses mise. mise complements it by pinning auxiliary tools and defining tasks. Alternative: declare the toolchain only in `mise.toml`; rejected because direct `cargo` invocations and IDE tooling would use the wrong compiler.

Pin a dated nightly (for example `nightly-2026-11-20`) rather than the rolling `nightly` channel, so a re-run of CI months later uses the same compiler. Updating the date is an explicit commit.

### Task runner: mise

Add `mise.toml` with tasks `check`, `build:armv6`, `build:aarch64`, `sim`, `release`, and `sign`. Tasks call cargo/cross directly and are usable in CI. Alternative: a Makefile; rejected because mise is already the user's tool of choice and also pins `cross`, `minisign`, `jq`, and `openspec`. OpenSpec has no registry short name, so it is pinned as `npm:@fission-ai/openspec@<version>` (it needs Node ≥22.20, which mise can also manage).

### Cross-compilation: `cross` for armv6, native cargo for aarch64

`cross` already works for the armv6 target and pins its container image. aarch64 builds can use `cross` too, keeping one tool path. Alternative: `cargo-zigbuild`; rejected as an extra tool without a concrete benefit here.

### Version stamping: `git describe` at build time

Build scripts read `WEATHER_PI_VERSION` from the environment, falling back to `git describe --tags --always --dirty`. CI sets it from the tag. The value is compiled in and printed by `--version`. This avoids a fragile build script rewriting `Cargo.toml`.

### Signing: minisign detached signature over the manifest

The manifest is the single signed document; it in turn pins each artifact's SHA-256. minisign (Ed25519) has a small CLI, a simple file format, and a maintained Rust verifier (`minisign-verify`). Alternatives considered:

- **cosign/Sigstore keyless**: strong identity binding, but requires OIDC, Fulcio roots, and transparency-log access on the device; too many moving parts for one device.
- **GPG**: available but heavier to script and verify in Rust.

Only the manifest is signed; signing every binary is redundant because the manifest commits to their hashes.

### Private key handling: offline by default

The release private key MUST NOT be a plain repository or organization secret. Until a protected GitHub Environment with required reviewers is set up, releases are built by CI as artifacts, then signed on the maintainer's machine and attached by a `workflow_dispatch` job. The bootstrap image embeds only the public key.

Key rotation is supported by allowing the verifier to hold a list of public keys; the first key is the current one and new releases are signed with it.

### Manifest shape

`schema_version`, `version`, `seq` (strictly increasing integer), `created_at`, `channel` (`stable` for now), and `artifacts[]` entries with `target`, `url`, `sha256`, `size`. Keeping `seq` separate from the semantic version gives the updater a rollback defense that does not depend on version parsing.

### Include packaging fixes in this change

A release that cannot start is not a release. The unit file gains the missing app argument, drops `chrt` (no realtime requirement), runs as `weather-pi` with `spi`/`gpio` groups, and the sample config is corrected to `watched_ips`.

## Risks / Trade-offs

- **Nightly compiler drift breaks the build later** → dated nightly pin, updated deliberately.
- **Signing key compromise** → offline key, public-key list for rotation, and the updater never trusts a release without a valid signature from a listed key.
- **GitHub asset URLs change or rate-limit** → manifest carries full URLs; updater uses the direct asset URL and sends a User-Agent. GitHub Releases for a public repo need no token.
- **Two architectures double CI time** → cache the cross container and cargo registry; aarch64 and armv6 builds run in parallel.
- **Path move breaks an existing card** → read `/etc/skyscreen` and `/usr/share/skyscreen` as a fallback for one release and log a deprecation warning.

## Migration Plan

1. Land toolchain pin and packaging fixes; verify the current device still starts with `/etc/skyscreen` present.
2. Cut `v0.2.0`; attach signed assets manually.
3. Use that release as the input to the image change.
4. Remove the legacy path fallback in the following minor release.

## Open Questions

- Exact nightly date: confirm by running `mise run check` against a candidate before committing it.
