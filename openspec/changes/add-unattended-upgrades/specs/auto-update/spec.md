# Spec Delta

## Purpose

Keeps the deployed application current without physical access by letting Debian's standard unattended upgrade path install signed, newer packages from the project repository, while leaving Debian security updates on their existing path and giving the operator a documented downgrade route.

## ADDED Requirements

### Requirement: Trusted installation source

The system SHALL install application packages only from the project repository whose metadata verifies against the archive key shipped in the image, and MUST refuse a repository, package, or expired metadata that does not verify.

#### Scenario: Unsigned or tampered metadata

- **WHEN** the repository metadata fails signature or hash verification
- **THEN** nothing is installed, the failure is logged, and the running application is unchanged

#### Scenario: Unknown signing key

- **WHEN** the metadata is signed by a key that is not present in the installed keyring
- **THEN** the repository is refused and no package from it is installed

#### Scenario: Expired metadata

- **WHEN** the repository's `Valid-Until` has passed
- **THEN** apt refuses the metadata and the installed version is unchanged

### Requirement: No automatic downgrade

The automatic path SHALL install only a version strictly newer than the installed one and MUST NOT downgrade the application.

#### Scenario: Repository offers an older version

- **WHEN** the available version is lower than or equal to the installed version
- **THEN** the automatic run installs nothing and reports that no upgrade is available

#### Scenario: Operator requests a downgrade

- **WHEN** an operator explicitly installs an older retained version with `--allow-downgrades`
- **THEN** that version is installed and the service is restarted on it

### Requirement: Unattended application updates

The image configuration SHALL allow `origin=weather-pi` as an unattended-upgrades origin with periodic unattended upgrades enabled, so a newer published application package is installed without operator action.

#### Scenario: Newer release published

- **WHEN** a newer `weather-pi` package appears in the signed repository
- **THEN** the next scheduled unattended upgrade installs it, the application service restarts on the new binary, and the display resumes drawing

#### Scenario: No newer release

- **WHEN** the published version equals the installed version
- **THEN** the scheduled run leaves the installation unchanged

#### Scenario: Project origin not allowed

- **WHEN** the project origin is missing from the effective unattended-upgrades configuration
- **THEN** a dry run shows no project candidate, and the image validation fails

### Requirement: Debian updates remain on the standard path

Enabling the project origin MUST NOT remove or replace the distribution's own unattended-upgrade origins, and MUST NOT cause packages from other origins to be installed from the project repository.

#### Scenario: Distribution security update

- **WHEN** `unattended-upgrades` applies a distribution security update
- **THEN** the project origin configuration does not prevent it, and the application keeps running

#### Scenario: Origin pin

- **WHEN** a project package is considered
- **THEN** apt resolves it from the pinned `o=weather-pi` origin and not from a distribution origin

### Requirement: Operator recovery without an updater CLI

The operator SHALL be able to inspect update state and recover a bad release over SSH using standard `apt`, `dpkg`, and `systemctl` commands, without relying on the application being healthy or on a project-specific executable.

#### Scenario: Status query

- **WHEN** the operator queries the device while the application is stopped
- **THEN** the installed version, the apt candidate, the unattended-upgrades timer, and the last run's result are obtainable from `dpkg-query`, `apt-cache policy`, `systemctl`, and the unattended-upgrades log

#### Scenario: Roll back a bad release

- **WHEN** a newer release is installed but misbehaves and the previous version is retained or cached
- **THEN** the operator can install that version explicitly, restart the service, and observe the display return to the previous behaviour

#### Scenario: Restore the current version

- **WHEN** the installed package is half-unpacked but the same version is available
- **THEN** reinstalling that version and completing dpkg restores a consistent installation

### Requirement: Interrupted installation

After a power loss or interrupted dpkg run the device SHALL still boot, remain reachable over the tunnel, and expose the standard dpkg recovery path to the operator.

#### Scenario: Power loss during installation

- **WHEN** the device reboots with a package left unconfigured
- **THEN** the device boots, the tunnel starts independently of the application, and `dpkg --configure -a` completes the installation

### Requirement: Update visibility

Every automatic run SHALL leave a log entry naming the versions and origins involved, and the operator MUST be able to preview a run without changing the installation.

#### Scenario: Successful automatic update

- **WHEN** the scheduled run upgrades the application
- **THEN** the unattended-upgrades log and the journal record the old and new versions

#### Scenario: Preview

- **WHEN** the operator runs `unattended-upgrade --dry-run -d`
- **THEN** the output lists the project origin and the candidate version without installing anything
