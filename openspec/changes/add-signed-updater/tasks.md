# Tasks

## 1. Update protocol and verification

- [ ] 1.1 Define and parse the manifest structure (schema version, version, seq, target, artifacts) with a rejecting test for unknown fields; verify a bad schema is refused
- [ ] 1.2 Embed the release public key(s) and verify the detached minisign signature; verify a tampered manifest and an unknown key are both rejected
- [ ] 1.3 Verify artifact SHA-256 and size against the manifest before extraction; verify a truncated archive is rejected
- [ ] 1.4 Implement target matching so an armv6 device cannot install an aarch64 artifact; verify with cross-target manifests

## 2. State and anti-rollback

- [ ] 2.1 Implement atomic read/write of `/var/lib/weather-pi/update-state.json`; verify a simulated power loss leaves either the old or new complete file
- [ ] 2.2 Enforce `seq` strictly greater than the recorded value and add `--force`; verify replayed and equal sequences are refused
- [ ] 2.3 Record last check time and result for `--status`; verify status output after success, failure, and offline cases

## 3. Atomic install and rollback

- [ ] 3.1 Implement lock, download, verify, atomic `rename`, and `.prev` retention; verify the service runs the new binary after restart
- [ ] 3.2 Add the application heartbeat write after display init and on an interval; verify the file updates while the service runs and stops when killed
- [ ] 3.3 Implement the health check and automatic rollback with a configurable window; verify a deliberately crashing build restores the previous binary
- [ ] 3.4 Implement `--rollback` for operators; verify it restores `.prev`, restarts, and is idempotent when no previous binary exists
- [ ] 3.5 Ensure failures before the swap never modify the running binary; verify by interrupting at each stage in a test harness

## 4. Scheduling and operations

- [ ] 4.1 Add `weather-pi-update.service` and `.timer` with randomized delay, network-online ordering, and single-instance locking; verify `systemd-analyze verify` and a manual `systemctl start`
- [ ] 4.2 Add `--check`, `--status`, and structured logging via tracing; verify output is usable over SSH and does not print secrets
- [ ] 4.3 Document the update lifecycle, state file, failure modes, and recovery in `docs/updating.md`; verify every documented command runs on the device
- [ ] 4.4 Confirm OS security updates remain with `unattended-upgrades` and document the boundary; verify the updater never invokes apt

## 5. Integration

- [ ] 5.1 End-to-end on hardware: publish a higher `seq`, let the timer update, confirm version change and display recovery
- [ ] 5.2 End-to-end rollback: publish a crashing build on a test channel, confirm automatic rollback and a clear `--status` report
- [ ] 5.3 Measure idle memory and binary size impact on a Pi Zero; record the numbers in the change notes

## Workflow follow-up

- Archive after the end-to-end success and rollback runs on hardware.
