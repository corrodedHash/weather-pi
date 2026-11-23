# Spec Delta

## Purpose

Gives the operator a persistent, authenticated route to a headless device behind NAT so configuration can be deployed and a broken update can be recovered without physical access.

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

The project SHALL provide a command that copies configuration and assets to the device over the tunnel, restarts the application service, and reports the resulting service state.

#### Scenario: Deploy configuration

- **WHEN** the operator runs the deploy command with a reachable tunnel
- **THEN** changed files are transferred, the service restarts, and the command reports success only if the service is active afterwards

#### Scenario: Unreachable device

- **WHEN** the tunnel is down or the device is offline
- **THEN** the deploy command fails with a clear error and changes no local state

### Requirement: Recovery path

The operator SHALL be able to reach the device over the tunnel and run the update rollback or restart the application manually.

#### Scenario: Broken update

- **WHEN** the application is failing after an update and the tunnel is available
- **THEN** the operator can connect over the VPS and invoke the rollback command successfully
