# Spec Delta

## Purpose

Keeps the deployed application current without physical access, while guaranteeing that only signed, newer, intact packages are installed, that a failed update is rolled back automatically, and that recovery does not depend on the application being healthy.

## ADDED Requirements

### Requirement: Trusted installation source

The updater SHALL install application packages only from the project repository whose metadata verifies against the archive key shipped in the image, and MUST refuse a repository, package, or expired metadata that does not verify.

#### Scenario: Unsigned or tampered metadata

- **WHEN** the repository metadata fails signature or hash verification
- **THEN** the updater installs nothing, records the failure, and leaves the running application unchanged

#### Scenario: Unknown signing key

- **WHEN** the metadata is signed by a key that is not present in the installed keyring
- **THEN** the updater refuses the repository

### Requirement: No automatic downgrade

The updater SHALL install only a version strictly newer than the installed one, and MUST NOT downgrade except through the explicit rollback action.

#### Scenario: Repository offers an older version

- **WHEN** the available version is lower than or equal to the installed version
- **THEN** the updater installs nothing and reports that no update is available

#### Scenario: Metadata replay

- **WHEN** a validly signed but expired metadata snapshot is served
- **THEN** apt refuses it and the updater reports a failure without changing the installation

### Requirement: Health-gated update

After installing a newer package the updater SHALL restart the application and require it to become active and to keep signalling the systemd watchdog within the health window.

#### Scenario: Successful update

- **WHEN** the restarted service becomes active and keeps its watchdog alive for the health window
- **THEN** the new version stays installed, the last-good version is recorded, and the run reports success

#### Scenario: New build crashes or hangs

- **WHEN** the restarted service fails, exits, or misses the watchdog within the health window
- **THEN** the updater reinstalls the last-good version, restarts the service, records the failed version, and reports failure

### Requirement: Updater isolation

The updater SHALL be delivered and run independently of the application, and an application package MUST NOT be able to change the updater, its units, or its apt configuration.

#### Scenario: Broken application release

- **WHEN** an application package installs a binary that cannot run
- **THEN** the updater still starts, reports status, and can roll back

#### Scenario: Automatic upgrade scope

- **WHEN** the scheduled update runs
- **THEN** it upgrades only the application package and leaves the updater package at its installed version

### Requirement: Scheduled checks

The system SHALL check for updates on a recurring schedule with randomized delay and MUST NOT run more than one update attempt at a time.

#### Scenario: Timer fires during an existing update

- **WHEN** the timer triggers while an update is already in progress
- **THEN** the new run exits without modifying the installation

#### Scenario: Device offline

- **WHEN** the device has no network or the repository is unreachable
- **THEN** the run fails quietly, records the failure, and retries on the next schedule without affecting the running service

### Requirement: Operator recovery commands

The updater SHALL provide commands to check for updates, report versions and last result, and roll back to the recorded last-good version, usable over SSH while the application is down.

#### Scenario: Status query

- **WHEN** an operator runs the status command
- **THEN** it prints the installed version, the available version, the last-good version, and the last result and time

#### Scenario: Operator rollback

- **WHEN** an operator requests a rollback and a last-good version is recorded
- **THEN** that version is reinstalled, the service restarts, and the result is reported; with no record, the command refuses and changes nothing

### Requirement: Interrupted update recovery

The system SHALL complete or report an interrupted package installation at boot before starting the application, so a power loss during an update does not leave the device unusable.

#### Scenario: Power loss during installation

- **WHEN** the device reboots with a pending package configuration
- **THEN** the boot sequence configures the pending package before the application starts, and the application runs the installed version

### Requirement: OS update boundary

The updater SHALL manage only the project's application package; Debian package security updates MUST remain with `unattended-upgrades`, and the project origin MUST be excluded from that automatic path.

#### Scenario: Security update runs

- **WHEN** `unattended-upgrades` applies Debian security updates
- **THEN** it does not upgrade or downgrade the application package, and the display keeps running
