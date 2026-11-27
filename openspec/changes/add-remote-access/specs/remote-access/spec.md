# Spec Delta

## Purpose

Gives the operator a persistent, authenticated route to a headless device behind NAT so configuration can be deployed, package state inspected, and a broken update recovered without physical access.

## ADDED Requirements

### Requirement: Persistent reverse tunnel

The device SHALL maintain an outbound SSH connection to the configured VPS that exposes the device's SSH service on the configured remote port, and SHALL re-establish it automatically after network loss, VPS restart, or reboot.

#### Scenario: Device boots

- **WHEN** the device powers on with a configured tunnel target and network access
- **THEN** the remote port on the VPS accepts SSH connections to the device within one minute

#### Scenario: Tunnel drops

- **WHEN** the connection to the VPS is interrupted
- **THEN** the supervising service reconnects without operator action and the remote port becomes usable again

#### Scenario: VPS unreachable

- **WHEN** the VPS cannot be reached
- **THEN** the device keeps running the display application and retries with backoff

### Requirement: Authenticated endpoints

The tunnel SHALL authenticate the device with a key unique to that device, and the VPS account MUST accept only that key with forwarding restricted to the device's remote port.

#### Scenario: Unauthorized key

- **WHEN** a connection to the VPS tunnel account presents a key that is not enrolled
- **THEN** authentication fails and no port is forwarded

#### Scenario: Forwarding scope

- **WHEN** an enrolled device requests a port other than its assigned remote port
- **THEN** the VPS refuses the forwarding request

### Requirement: Host identity verification

The device SHALL verify the VPS host key against a pinned value and MUST refuse to establish the tunnel when the host key does not match.

#### Scenario: Changed host key

- **WHEN** the VPS presents a host key different from the pinned value
- **THEN** the tunnel does not establish and the failure is logged

### Requirement: Credentials are per device

Tunnel private keys and administrator authorized keys SHALL be unique per device and MUST NOT be present in the published image or repository.

#### Scenario: Inspect image and repository

- **WHEN** the image and the git history are searched for private key material
- **THEN** no tunnel or administrator private key is found

### Requirement: Device SSH hardening

The device's SSH service SHALL accept public-key authentication for the administrator only, with password authentication and root login disabled.

#### Scenario: Password attempt

- **WHEN** a client attempts password authentication or root login
- **THEN** the connection is refused

### Requirement: Configuration deployment

The project SHALL provide a command that copies configuration and assets to the device over the tunnel, restarts the application service, and reports the resulting service state, without modifying package-managed binaries.

#### Scenario: Deploy configuration

- **WHEN** the operator runs the deploy command with a reachable tunnel
- **THEN** changed configuration files are transferred, the service restarts, and the command reports success only if the service is active afterwards

#### Scenario: Unreachable device

- **WHEN** the tunnel is down or the device is offline
- **THEN** the deploy command fails with a clear error and changes no local state

#### Scenario: No out-of-band binary replacement

- **WHEN** the deploy command runs
- **THEN** the installed package version reported by `dpkg-query` is unchanged

### Requirement: Package state visibility

The project SHALL provide a read-only status command that reports the tunnel, the application service, the installed and candidate package versions, the unattended-upgrades timer, and the last unattended-upgrade result, and MUST work while the application is stopped.

#### Scenario: Status over the tunnel

- **WHEN** the operator runs the status command with a reachable tunnel and a stopped application
- **THEN** it prints the tunnel state, installed and candidate versions, the `apt-daily-upgrade.timer` state, and the last unattended-upgrade result without failing

#### Scenario: Update available

- **WHEN** a newer application package is published
- **THEN** the status command shows it as the candidate without changing the installation

### Requirement: Recovery path

The operator SHALL be able to reach the device over the tunnel and recover a bad package release or restart the application using standard `apt`, `dpkg`, and `systemctl` commands.

#### Scenario: Broken update

- **WHEN** the application is failing after an update and the tunnel is available
- **THEN** the operator can connect over the VPS, explicitly install a retained previous version, and observe the service return to the previous behaviour

#### Scenario: Interrupted installation

- **WHEN** dpkg left the package half-configured
- **THEN** the operator can complete it over the tunnel with `dpkg --configure -a` without reflashing

#### Scenario: Restart only

- **WHEN** the operator restarts the service over the tunnel
- **THEN** the installed package version is unchanged
