# Spec Delta

## Purpose

Produces versioned, signed, installable Debian packages and a signed apt repository from a reproducible build, so a device and the disk image install and verify exactly one known release through standard tooling.

## ADDED Requirements

### Requirement: Pinned toolchain

The repository SHALL declare the Rust toolchain it builds with, so a checkout compiles with the same compiler regardless of the developer's default toolchain.

#### Scenario: Only stable Rust installed

- **WHEN** a developer with only a stable toolchain installed runs the project's build task
- **THEN** the pinned nightly toolchain is selected automatically and the build proceeds without manual toolchain commands

#### Scenario: Toolchain drift

- **WHEN** the pinned toolchain cannot be installed
- **THEN** the build fails with an error naming the required toolchain instead of silently falling back to another compiler

### Requirement: Multi-architecture packages

The release process SHALL produce packages for `armhf` and `arm64` from the same source revision.

#### Scenario: Release built from a tag

- **WHEN** a release is built for tag `vX.Y.Z`
- **THEN** `armhf` and `arm64` packages are produced and each reports version `X.Y.Z`

### Requirement: Version reporting

The installed binary SHALL report its release version and target triple through a non-interactive command.

#### Scenario: Version query

- **WHEN** the binary is invoked with `--version`
- **THEN** it prints the release version and target triple and exits successfully

### Requirement: Debian package metadata

Each published application package SHALL be named `weather-pi`, carry the tag-derived version with a Debian revision, declare its architecture, and install the binary, unit, assets, and sample configuration at their documented paths.

#### Scenario: Inspect a package

- **WHEN** a published package is inspected with `dpkg-deb -I` and `dpkg-deb -c`
- **THEN** name, version, and architecture match the tag and target, and the file list matches the documented layout

#### Scenario: Monotonic version

- **WHEN** CI computes a package version that is not strictly greater than the newest version already in the published repository
- **THEN** publication is refused

### Requirement: Signed repository metadata

The release SHALL publish apt metadata whose `Release` file is GPG-signed as `InRelease`, covers every package file with a hash and size, and carries an expiry no later than seven days after publication.

#### Scenario: Valid metadata

- **WHEN** a client with the project's archive key runs `apt-get update` against the repository
- **THEN** the signature and hashes verify and the packages are listed

#### Scenario: Tampered metadata

- **WHEN** any byte of `Release` or a listed package is modified after signing
- **THEN** `apt-get update` fails and no package is installed

#### Scenario: Expired metadata

- **WHEN** a client fetches metadata whose `Valid-Until` has passed
- **THEN** apt refuses the repository instead of installing from it

### Requirement: Package integrity

The repository SHALL record a SHA-256 and size for every package, and a client MUST refuse a package whose bytes do not match the signed metadata.

#### Scenario: Corrupted package

- **WHEN** a downloaded package does not match the hash in `Packages`
- **THEN** apt discards it and the installed version is left untouched

### Requirement: Retained rollback versions

The repository SHALL keep the most recent five published versions per architecture available for deliberate downgrade.

#### Scenario: Downgrade to a retained version

- **WHEN** an operator requests the previous package version with `--allow-downgrades`
- **THEN** apt resolves and installs that version from the repository

#### Scenario: Pruning

- **WHEN** more than five versions exist after a publication
- **THEN** the oldest versions are removed from the pool and index while the five newest remain installable

### Requirement: Key rotation deliverable

The release process SHALL publish a `weather-pi-archive-keyring` package containing the archive public key, and SHALL be able to ship a new key alongside the old one.

#### Scenario: Rotate the archive key

- **WHEN** a keyring package containing a new key is published and signed by the current key
- **THEN** an installed device can update the keyring package and then trust metadata signed by the new key

### Requirement: Automated publication

Pushing a tag matching `v*` SHALL run the project's checks and, only if they pass, publish the packages, repository metadata, keyring package, and `SHA256SUMS` to the repository host and the GitHub Release for that tag.

#### Scenario: Successful tag build

- **WHEN** a `v*` tag is pushed and all checks pass
- **THEN** the repository serves the new packages with a valid `InRelease`, and the GitHub Release contains the packages and `SHA256SUMS`

#### Scenario: Failed check

- **WHEN** any check or the version comparison fails for a `v*` tag
- **THEN** no package or metadata is published and the previous repository state remains served
