# Spec Delta

## Purpose

Keeps the deployed application current without physical access, while guaranteeing that only signed, newer, intact releases are installed and that a failed update never leaves the device unusable.

## ADDED Requirements

### Requirement: Signature verification before installation

The updater SHALL verify a detached signature over the release manifest against a public key embedded in the installed software, and MUST refuse to install any artifact when verification fails.

#### Scenario: Unsigned manifest

- **WHEN** the downloaded manifest has no signature or an invalid one
- **THEN** the updater installs nothing, reports an error, and leaves the running binary unchanged

#### Scenario: Unknown signing key

- **WHEN** the manifest is signed by a key that is not embedded in the binary
- **THEN** the updater rejects the release

#### Scenario: Key rotation

- **WHEN** the binary embeds two public keys and the manifest is validly signed by the second key
- **THEN** the updater accepts the release

### Requirement: Artifact integrity

The updater SHALL verify the SHA-256 and size of the downloaded artifact against the signed manifest before installing it.

#### Scenario: Truncated download

- **WHEN** a download is incomplete or its hash differs from the manifest
- **THEN** the updater discards the download and keeps the current installation

### Requirement: Anti-rollback

The updater SHALL persist the sequence number of the last installed release and MUST NOT install a release whose sequence number is less than or equal to it, unless an explicit force option is used by an operator.

#### Scenario: Replayed older release

- **WHEN** a validly signed manifest with the same or lower sequence number is offered
- **THEN** the updater declines to install it without the force option

#### Scenario: Newer release

- **WHEN** a validly signed manifest has a higher sequence number than the recorded one
- **THEN** the updater proceeds with installation

### Requirement: Atomic installation and health check

The updater SHALL replace the application binary atomically and SHALL confirm that the restarted service is healthy before committing the update.

#### Scenario: Successful update

- **WHEN** a verified release is installed and the restarted service makes progress within the health window
- **THEN** the new binary remains in place, the sequence number is recorded, and the updater reports success

#### Scenario: New build crashes on start

- **WHEN** the restarted service exits or writes no heartbeat within the health window
- **THEN** the updater restores the previous binary, restarts it, and reports a failed update

### Requirement: Manual recovery

The updater SHALL provide commands to check for updates, report the installed and available versions, and roll back to the previously installed binary.

#### Scenario: Status query

- **WHEN** an operator runs the status command
- **THEN** it prints the running version, last check time, last result, and the available version if known

#### Scenario: Operator rollback

- **WHEN** an operator requests a rollback and a previous binary is available
- **THEN** the previous binary is restored, the service restarts, and the failure is reported

### Requirement: Scheduled checks

The system SHALL check for updates on a recurring schedule with randomized delay and MUST NOT run more than one update attempt at a time.

#### Scenario: Timer fires during an existing update

- **WHEN** the timer triggers while an update is already in progress
- **THEN** the new run exits without modifying the installation

#### Scenario: Offline device

- **WHEN** the device has no network or the release endpoint is unreachable
- **THEN** the check fails quietly, records the failure, and retries on the next schedule without affecting the running service
