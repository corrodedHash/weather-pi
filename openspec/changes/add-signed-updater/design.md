# Design

## Context

See `proposal.md`. Relevant facts:

- The binary is a single static-ish executable; replacing the file and restarting the unit is sufficient.
- The service runs the display loop continuously, so a restart blanks and redraws the panel; this is acceptable and already happens on failure.
- The device has no RTC battery; timestamps are only used for logging, not trust.
- Releases are public GitHub assets; TLS protects transport, but the signature is the trust anchor.
- The image ships a public key and a writable state directory.

## Goals / Non-Goals

**Goals:**

- A failed or malicious update cannot brick the device or downgrade it silently.
- An operator can diagnose and recover over SSH without reflashing.
- Keep the updater small enough to run on a Zero alongside the display app.

**Non-Goals:**

- Updating the kernel, packages, or image. `unattended-upgrades` handles security packages; image changes are reflashed.
- Delta updates; the binary is small.
- A staged rollout across a fleet (one device).

## Decisions

### Updater lives in the same binary as a subcommand

`weather-pi update` / `--check` / `--status` / `--rollback` reuse the existing config and version code and avoid shipping and updating a second executable. The running display service and the updater are separate processes, so replacing the binary on disk is safe; systemd restarts into the new inode.

Alternative: a separate `weather-pi-updater` binary. Rejected because it doubles the signing/update surface and the binary is tiny.

### Signature scheme: minisign over the manifest

The manifest is signed once; it pins the artifact hash. Verification uses `minisign-verify`, a small Rust crate with no OpenSSL dependency. Public keys are compiled in with `include_bytes!` and can also be overridden by `/etc/weather-pi/update.pub` for local testing. The private key never touches the device.

The manifest also carries the target triple, so an armv6 device cannot install an aarch64 binary.

### Anti-rollback: persisted `seq`

`/var/lib/weather-pi/update-state.json` records `{seq, version, installed_at, last_check, last_result}` and is written with `write` + `fsync` + `rename`. The updater compares `manifest.seq` to the stored value before download. `--force` allows an operator to override after reviewing the release.

Limitation: restoring an old SD image also restores the old `seq`, so anti-rollback is not a defense against physical access. That is acceptable for this threat model and documented.

### Atomic install sequence

1. Acquire `/run/weather-pi-update.lock` (`flock`) and exit if busy.
2. Fetch `manifest.json` and `manifest.json.minisig` with a timeout and a project User-Agent.
3. Verify signature, schema, target, and `seq`.
4. Download the archive to `/var/lib/weather-pi/download/` on the same filesystem as the binary, verify hash and size.
5. Extract the single binary to `/usr/bin/.weather-pi.new`, `fsync`, `chmod 0755`, `rename` to `/usr/bin/weather-pi`, keeping `/usr/bin/weather-pi.prev`.
6. `systemctl restart weather-pi`.
7. Wait up to 30 s for the heartbeat or a healthy unit state.
8. On failure, swap `.prev` back and restart; record the failure and do not retry the same `seq` automatically.

Using `rename` on the same filesystem guarantees readers see either the old or new complete file.

### Health signal

The application writes `/var/lib/weather-pi/heartbeat` after the display initializes and then at a fixed interval (for example every 30 s). The updater requires a heartbeat newer than the restart. Fallback if heartbeat support is unavailable: `systemctl is-active` for 15 s. The heartbeat is also useful for a future watchdog.

### Scheduling

`weather-pi-update.timer` runs daily with `RandomizedDelaySec=6h` and `Persistent=true`, and the service uses `After=network-online.target`. The unit is `Type=oneshot` and conflicts with itself via `flock`, so a slow download cannot pile up runs.

### Failure policy

- Network/signature errors: log, record, retry next schedule. Never retry aggressively.
- Health failure: roll back, write a marker for the failed `seq`, and surface it in `--status`.
- Disk full or read-only filesystem: abort before touching the binary.

## Risks / Trade-offs

- **Signing key compromise** → offline key, public-key rotation list, no key on the device. Worst case still requires the attacker to publish a manifest the device trusts.
- **A release that passes the health check but misbehaves** → the heartbeat only proves liveness; keep `--rollback` and the previous binary. Optionally add a "soak" check later.
- **GitHub outage or API change** → direct asset URLs in the manifest, cached last-known version, failures are non-fatal.
- **Clock jumps on a battery-less Pi** → do not use timestamps for trust; `seq` is the only ordering.
- **State file corruption** → treat unreadable state as "unknown" and refuse automatic updates until an operator runs `--force` or `--status` shows the issue.

## Migration Plan

1. Ship the updater and heartbeat in the first image; it is inert until a newer signed release exists.
2. Publish `v0.2.1` with a `seq` of 1 and confirm the device updates and survives a restart.
3. Publish a deliberately broken build on a test channel to confirm rollback, then discard it.

## Open Questions

- HTTP client choice: `ureq` (blocking, small) vs `reqwest` with rustls. Decide by binary size and build time on the armv6 target during implementation.
