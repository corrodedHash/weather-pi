# Design

## Context

See `proposal.md` for motivation. Relevant facts:

- The systemd unit already restarts the application on failure; a rebuild blanks and redraws the panel, which is acceptable and already happens.
- The device has no RTC battery; timestamps are only used for logging, never for trust.
- The repository and packages come from `add-release-pipeline`; the image ships the keyring and apt configuration from `add-device-image`.
- The device is a Pi Zero with limited memory; adding a second daemon or a large runtime is not acceptable.
- The application is a single executable with no runtime dependencies, so a Debian package is a thin wrapper around one file.

An earlier design put the updater inside the application binary as a `weather-pi update` subcommand. It was rejected: it couples recovery to the software being recovered, forces an HTTP client and signature verification into the display program, and makes an application release able to break future updates.

## Goals / Non-Goals

**Goals:**

- A failed or malicious update cannot brick the device or silently downgrade it.
- An operator can diagnose and recover over SSH without reflashing, even when the application is down.
- Update logic can be inspected and changed without rebuilding the display application.
- The application stays a display program.

**Non-Goals:**

- Updating the kernel, Raspberry Pi OS packages, or the disk image. `unattended-upgrades` handles Debian security packages; image changes are reflashed.
- Delta updates; the packages are small.
- Staged rollouts across a fleet (one device).
- Cryptographic monotonic sequencing beyond apt's version ordering and `Valid-Until`.

## Decisions

### Updater is a separate package, not a subcommand

`weather-pi-updater` owns the wrapper, units, apt source, keyring reference, and preferences. `weather-pi` owns only the binary, unit, assets, and sample configuration. The wrapper upgrades `weather-pi` and never upgrades `weather-pi-updater`; the updater package is upgraded by an explicit operator command over the tunnel.

Alternative: keep everything in the application binary. Rejected because a broken release then also breaks rollback and diagnosis, and because it forces HTTP, signature, and state-handling dependencies into a program that only draws to a panel.

Alternative: a separate Rust helper binary. Rejected for now: it adds a compiled artifact and a signing target for about 150 lines of orchestration that performs no cryptography. The wrapper only runs fixed `apt-get` and `systemctl` invocations and never parses untrusted structured input. If the wrapper grows policy logic, this decision can be revisited without changing the repository or package formats.

### apt is the transport and the verifier

The signed apt repository already provides signature verification, per-file hashes, download retries, atomic installation, downgrade support, an audit trail (`dpkg -L`, `dpkg -V`), and boot-time journal recovery. Implementing any of that again in a custom client adds attack surface and maintenance for no functional gain. The device therefore has no manifest, no minisign key, no sequence state, and no custom download code.

What apt does not provide is a health gate, so the wrapper adds exactly that. See `add-release-pipeline` for the repository, signing, retention, and version decisions.

### Wrapper shape

`/usr/sbin/weather-pi-update` is a POSIX shell script with four behaviours:

```
weather-pi-update --check      # update if a newer version is available (timer entry point)
weather-pi-update --apply      # same, explicitly
weather-pi-update --status     # installed version, candidate, last result, last good version
weather-pi-update --rollback   # reinstall the recorded last good version
```

`--check`/`--apply` sequence:

1. Take `/run/weather-pi-update.lock` with `flock -n`; exit quietly if busy.
2. Read the installed version with `dpkg-query -W -f='${Version}' weather-pi` and store it as the rollback candidate.
3. `apt-get update` with `Acquire::Retries=3` and `DPkg::Lock::Timeout=120`; record and exit on failure.
4. Resolve the candidate with `apt-cache policy weather-pi`. If it is not strictly newer, write a no-op result and exit 0.
5. `apt-get install -y --only-upgrade weather-pi` with `DEBIAN_FRONTEND=noninteractive` and `--force-confdef --force-confold`.
6. `systemctl restart weather-pi.service`, then wait up to 45 s for `systemctl is-active` plus a live watchdog (the unit is `Type=notify` and the application pings it).
7. On success, write `{last_good, last_result, checked_at}` to `/var/lib/weather-pi/update-state.json`.
8. On failure, run the rollback path, write a failed result, and exit non-zero.

`--rollback` installs the recorded last-good version with `--allow-downgrades`, preferring the cached archive in `/var/cache/apt/archives` and falling back to the repository. It is idempotent and refuses when no last-good version is recorded.

The state file is small, written with `write` + `fsync` + `rename`; it is informational and never a trust decision. Trust comes from the signed repository.

### Health via systemd watchdog, not a heartbeat file

`weather-pi.service` becomes `Type=notify` with `WatchdogSec=60`. The application sends `READY=1` after the display initialises and `WATCHDOG=1` from its main loop. systemd then restarts the unit if the loop stalls, and the wrapper only has to observe `is-active` after the restart. This removes the heartbeat file, the writable state directory from the application's sandbox, and a polling loop from the wrapper.

Alternative: heartbeat file as previously designed. Rejected because it duplicates watchdog functionality, requires the application to know about the update contract, and needs `ReadWritePaths` in the unit.

`WatchdogSec` is set generously relative to the slowest legitimate display refresh so a normal e-ink update never trips it.

### Health failure policy

- Network or metadata failure: record, exit non-zero for the timer journal, retry on the next schedule. Never retry in a loop.
- Install failure before the package is unpacked: nothing changed.
- Failure after install: roll back to the recorded last-good version and restart; record the failed version so `--status` shows it.
- A rolled-back version is not retried automatically; the next run only sees it as "not newer" until a newer package is published.
- Read-only filesystem or full disk: abort before installing.

### Anti-replay and downgrade policy

apt refuses to install a lower version unless told otherwise, so the automatic path cannot be walked backwards. Metadata replay is bounded by `Valid-Until` (seven days) and `Acquire::Check-Valid-Until`; an older snapshot stops being installable shortly after it is superseded.

Residual risk, accepted for one device: someone who controls the repository and the archive key, or can serve an old snapshot inside the validity window, could present an older signed release. A local sequence counter would not defend against a compromised signing key either, and physical access defeats any local counter by restoring the SD image. The risk is documented rather than engineered around.

### Conffiles and user configuration

`/etc/weather-pi/*.toml` are conffiles: a locally edited file survives an upgrade and dpkg keeps the local version under `--force-confold`. Assets under `/usr/share/weather-pi` are replaced. Operators who want a new template diff it against `*.dpkg-dist`.

### Scheduling and locking

`weather-pi-update.timer` runs daily with `RandomizedDelaySec=6h` and `Persistent=true`; the service is `Type=oneshot`, ordered `After=network-online.target`, and additionally guarded by the lock. `unattended-upgrades` is configured to ignore the `weather-pi` origin so there is exactly one automatic path for these packages; Debian packages keep their existing handling. apt's own lock timeout prevents a collision with a concurrent unattended upgrade.

### Interrupted dpkg recovery

`weather-pi-recover.service` is a `Type=oneshot` unit ordered `Before=weather-pi.service` that runs `dpkg --configure -a` when a pending dpkg journal exists. Without it, a power loss during unpack can leave the package half-configured and the application unable to start until someone logs in. The check is cheap and does nothing on a healthy boot.

### Upgrade paths for the updater itself

Only the operator upgrades `weather-pi-updater`, either through `mise run deploy-updater` from the development machine or with an explicit `apt-get install --only-upgrade weather-pi-updater` over the tunnel. This keeps automatic updates unable to change their own supervisor while still allowing a wrapper bug to be fixed without a card pull.

## Risks / Trade-offs

- **Wrapper bug** → the wrapper is a small, inspectable script; the operator can still install `weather-pi-updater` manually over the tunnel; the previous app package remains installable.
- **Watchdog false positive blanks the panel** → `WatchdogSec` sized against the slowest legitimate refresh; a restart is the existing failure behaviour.
- **apt lock contention with unattended-upgrades** → `DPkg::Lock::Timeout` and a lock of our own; failed runs are retried next schedule.
- **Power loss during dpkg** → journal recovery at boot plus `APT::Keep-Downloaded-Packages`; documented as a card-pull case if the journal itself is damaged.
- **Repository replay within the validity window** → accepted and documented; short `Valid-Until`, HTTPS, and a protected signing key.
- **No OS-level rollback** → out of scope; a bad kernel or firmware update still means reflashing. Revisit RAUC/Mender only if the device becomes hard to reach physically.
- **State file corruption** → treat unreadable state as "no last-good version", report it in `--status`, and let the operator choose a version explicitly.

## Migration Plan

1. Publish the repository and packages from `add-release-pipeline` at `v0.2.0`.
2. Build an image that installs `weather-pi` and `weather-pi-updater` at pinned versions with the timer enabled; verify `--check` is a no-op.
3. Publish `v0.2.1`; confirm the timer updates, the panel redraws, and `--status` reports the new version.
4. Publish a deliberately broken `v0.2.2` to a staging repository; confirm automatic rollback to `v0.2.1` and that `--status` shows the failure.
5. Recover over the tunnel only, without reflashing, then discard the broken package.

## Open Questions

- Whether GitHub Pages' expiring CDN cache can serve stale metadata past `Valid-Until` in practice; measure during the first two releases and lengthen the window or add a cache-busting query if needed.
