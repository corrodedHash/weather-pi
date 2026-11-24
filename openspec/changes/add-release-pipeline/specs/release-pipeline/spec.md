# Spec Delta

## Purpose

Produces versioned, signed, installable artifacts from a reproducible build, so a device can install and verify exactly one known release.

## ADDED Requirements

### Requirement: Pinned toolchain

The repository SHALL declare the Rust toolchain it builds with, so a checkout compiles with the same compiler regardless of the developer's default toolchain.

#### Scenario: Only stable Rust installed

- **WHEN** a developer with only a stable toolchain installed runs the project's build task
- **THEN** the pinned nightly toolchain is selected automatically and the build proceeds without manual toolchain commands

#### Scenario: Toolchain drift

- **WHEN** the pinned toolchain cannot be installed
- **THEN** the build fails with an error naming the required toolchain instead of silently falling back to another compiler

### Requirement: Multi-target release binaries

The release process SHALL produce a binary for `arm-unknown-linux-gnueabihf` and a binary for `aarch64-unknown-linux-gnu` from the same source revision.

#### Scenario: Release built from a tag

- **WHEN** a release is built for tag `vX.Y.Z`
- **THEN** both target binaries are produced and each reports version `X.Y.Z`

### Requirement: Version reporting

The installed binary SHALL report its release version and target triple through a non-interactive command.

#### Scenario: Version query

- **WHEN** the binary is invoked with `--version`
- **THEN** it prints the release version and target triple and exits successfully

### Requirement: Signed manifest

Every release SHALL include a manifest that lists each artifact's target, download URL, SHA-256, and size, plus a monotonically increasing sequence number, and the manifest MUST be accompanied by a detached signature verifiable with the project's release public key.

#### Scenario: Valid manifest

- **WHEN** a consumer verifies the manifest with the release public key
- **THEN** verification succeeds and the manifest yields one artifact entry per supported target

#### Scenario: Tampered manifest

- **WHEN** any byte of a signed manifest is modified before verification
- **THEN** signature verification fails

### Requirement: Integrity metadata

The release SHALL publish a SHA-256 checksum for every artifact and for the disk image, and every checksum MUST match the bytes of the corresponding published file.

#### Scenario: Corrupted artifact

- **WHEN** a downloaded artifact's SHA-256 does not match the manifest entry
- **THEN** the consumer refuses to install it and the existing installation is left untouched

### Requirement: Automated publication

Pushing a tag matching `v*` SHALL run the project's checks and, only if they pass, publish both binaries, the manifest, its signature, and `SHA256SUMS` to the GitHub Release for that tag.

#### Scenario: Successful tag build

- **WHEN** a `v*` tag is pushed and all checks pass
- **THEN** the GitHub Release contains both target binaries, `manifest.json`, `manifest.json.minisig`, and `SHA256SUMS`

#### Scenario: Failed check

- **WHEN** any check fails for a `v*` tag
- **THEN** no release assets are published for that tag
