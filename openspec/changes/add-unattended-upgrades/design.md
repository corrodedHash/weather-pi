# Design

## Context

See `proposal.md`. Relevant facts:

- The device sits on a wall, is headless, has no RTC battery, and is a Pi Zero with little memory; a second long-running daemon is undesirable.
- The signed apt repository from `add-release-pipeline` already provides signature verification, per-file hashes, retries, atomic installation, downgrade semantics, an audit trail, and key rotation.
- `unattended-upgrades` is the distribution's standard package for applying apt upgrades without an operator. It runs from the base system's daily apt timer, not from a project-owned unit.
- The application package ships its systemd unit with `restart-after-upgrade`, so an installed upgrade restarts the service and redraws the panel.
- The repository retains the five newest versions per architecture and the device keeps downloaded archives.
- An earlier design put the updater inside the application binary; a later design used a separate `weather-pi-updater` package with a health-gated shell wrapper and its own timer. Both are rejected here.

## Goals / Non-Goals

**Goals:**

- Only signed, newer, intact packages are installed, using the trust chain the repository already has.
- Updates happen without operator action and without project-owned update code or units.
- The operator can inspect state and recover a bad release over SSH without reflashing.
- The application stays a display program with no network or update logic.

**Non-Goals:**

- Health gating, automatic rollback, or canary/staged rollout.
- A replay counter beyond apt's version ordering and `Valid-Until`.
- Updating the kernel, firmware, or disk image; image changes are reflashed.
- Multiple devices, channels, or maintenance windows.

## Decisions

### Debian's `unattended-upgrades` is the update scheduler

Add the project origin to the origins that `unattended-upgrades` may upgrade from:

```
Unattended-Upgrade::Origins-Pattern {
    "origin=weather-pi,archive=trixie";
};
```

The fragment is additive in intent. apt appends list values across `apt.conf.d` fragments, but the release verifies this rather than assuming it: the image build asserts statically that both the distribution's origins and the project origin are in the effective list, and `unattended-upgrade --dry-run -d` after boot shows the same. Debian security origins are never replaced.

The schedule is the distribution's `apt-daily-upgrade.timer` (with its randomized delay and `Persistent=true`), not a project timer. The image enables the daily job with `APT::Periodic::Update-Package-Lists "1"` and `APT::Periodic::Unattended-Upgrade "1"`, because installing the package alone does not guarantee that periodic upgrades are switched on. `unattended-upgrades` only upgrades packages already installed from an allowed origin, so the application and its keyring are eligible; unrelated packages are not.

Alternatives:

- **Project-owned timer running the wrapper** (the previous design): controllable and health-gated, but it is a second package, a wrapper to maintain, and a duplicate of the standard schedule. Its only unique feature was the health gate.
- **Project-owned timer running `apt-get` directly**: replaces `unattended-upgrades` with a slightly different copy and reopens the question of which mechanism owns Debian security updates.
- **`unattended-upgrades` plus a hook for post-install health checks**: `DPkg::Post-Invoke` or `Post-Invoke-Success` could run a script, but it would reintroduce the wrapper and still cannot reliably distinguish a good release from a bad one without a rollback policy. Rejected for one device.

### apt is the transport and the verifier

The signed repository is the trust anchor. There is no manifest, no minisign key for packages, no sequence state, and no custom download code. apt refuses unsigned metadata, hash mismatches, expired `Valid-Until`, and (by default) a lower version. Trust and integrity are therefore identical to a manual `apt-get install`.

### No health gate and no automatic rollback

`unattended-upgrades` installs the newer package, dpkg unpacks it, and the package's maintainer scripts restart `weather-pi.service`. `Restart=on-failure` covers a crashing binary. Nothing evaluates whether the display is drawing correctly.

This is the accepted cost of using the standard mechanism. A release that installs successfully but behaves badly stays installed until an operator acts; recovery is an explicit version pin (below). The alternative is the wrapper design, rejected because it adds a package, a unit, a state file, and rollback logic to protect a single wall-mounted device.

### Conffiles, cache, and package scope

`/etc/weather-pi/*.toml` are conffiles. `unattended-upgrades` runs dpkg non-interactively and keeps locally modified conffiles; if the new package also changes the same file, the package is held back and logged rather than prompted. The image task verifies this with an edited config so an upgrade cannot silently replace the operator's settings. Assets under `/usr/share/weather-pi` are replaced.

`APT::Keep-Downloaded-Packages "true"` keeps archives fetched by apt. The automatic path's own `Unattended-Upgrade::Keep-Debs-After-Install` cleanup is left at its default, so the archive from the latest automatic install is removed after success; a cached earlier version, when present, and the repository's five-version retention are the rollback sources.

Only packages installed from `origin=weather-pi` are candidates: `weather-pi` and `weather-pi-archive-keyring`. There is no updater package any more.

### Operator recovery uses standard commands

No status or rollback CLI is shipped. Over the tunnel the operator runs:

```
dpkg-query -W weather-pi
apt-cache policy weather-pi
systemctl list-timers apt-daily-upgrade.timer
unattended-upgrade --dry-run -d
tail -n 50 /var/log/unattended-upgrades/unattended-upgrades.log
```

A rollback pins a retained version explicitly:

```
apt-get update
apt-get install --allow-downgrades weather-pi=<version>
systemctl restart weather-pi
```

When the cache holds the archive, `apt-get install /var/cache/apt/archives/weather-pi_<version>_armhf.deb` works offline. There is no recorded "last good" version; the operator chooses. `apt-get install --reinstall weather-pi` restores the current version after a partially unpacked file.

An interrupted dpkg run is completed with `dpkg --configure -a` over the tunnel; no boot unit performs it automatically. The image documentation states this, and the device remains reachable because the tunnel unit is independent of the application.

### Anti-replay and downgrade policy

Automatic upgrades only move forward: apt installs a candidate only when it is newer unless `--allow-downgrades` is passed, which only the operator does. Metadata replay is bounded by a seven-day `Valid-Until` with `Acquire::Check-Valid-Until "true"`.

Residual risk, accepted: an attacker who controls the repository and the archive key, or who can serve an old snapshot inside the validity window, can present an older signed release. A local sequence counter would not defend against a compromised signing key, and physical access defeats any local state by restoring the SD image. The limitation is documented rather than engineered around.

### Failure policy

- Repository unreachable or metadata expired: apt installs nothing; the installed version and the running service are unchanged. The next daily run retries.
- Package fails to install: dpkg leaves the previous version or reports a half-configured state; the operator completes or reverses it with standard apt/dpkg commands.
- Installed release crashes: systemd restarts the unit; a crash loop is visible in `systemctl status` and the journal.
- Installed release runs but behaves badly: stays installed until the operator pins an older version.
- Power loss during installation: the package may be half-configured; the device still boots, the tunnel still starts, and the operator runs `dpkg --configure -a`.

### Update visibility

`unattended-upgrades` logs to `/var/log/unattended-upgrades/`; the daily service and the application restart are visible in the journal. The image smoke test and `docs/updating.md` use `--dry-run -d` to show the candidate and origin without changing anything. No project-specific status file is written, because the package database and apt are already the source of truth.

## Risks / Trade-offs

- **No automatic rollback** → a bad release stays until an operator intervenes. Accepted; the operator has a tunnel and retained versions.
- **No health gate** → a release that installs but renders badly is not detected automatically. Mitigated by hardware validation before publishing and by fast manual recovery.
- **Power loss during dpkg** → manual `dpkg --configure -a` over the tunnel. Accepted; the previous recovery unit was removed with the updater.
- **Origin allowlist mistakes** → the project origin is not upgraded at all, or distribution origins are dropped. Verified with static origin checks in the image build and with `--dry-run -d` after boot.
- **Concurrent apt use** → `unattended-upgrades` and a manual `apt-get` can collide; apt's lock and `DPkg::Lock::Timeout` serialize them, and the operator waits for the daily run to finish.
- **Keyring and application update together** → the keyring package may be unpacked in the same run as the application; this is intended, but a rotation that requires the new key before metadata verification must be staged as documented in `docs/releasing.md`.
- **Replay within the validity window** → accepted and documented; short `Valid-Until`, HTTPS, and a protected signing key.
- **No OS-level rollback** → out of scope; a bad base image is reflashed.

## Decision record

Accepted for this change:

- **Standard scheduler only.** Debian's `unattended-upgrades`, driven by the
  distribution's `apt-daily-upgrade.timer`; no project package, unit, timer,
  state file, or CLI.
- **No health gate.** A release that installs and starts is kept even if the
  panel renders badly. Hardware validation before publication is the guard;
  `Restart=on-failure` covers only a crashing binary.
- **No automatic rollback.** The operator downgrades explicitly to a retained or
  cached version and optionally holds it. There is no recorded "last good"
  version.
- **Replay within `Valid-Until`.** apt's version ordering prevents automatic
  downgrades, and a seven-day signed-metadata window bounds replay. A
  compromised key or physical access defeats a local counter, so none is added.
- **Power-loss recovery is manual.** The device boots and the tunnel is
  independent of the application; the operator runs `dpkg --configure -a` and
  the standard reinstall path. No boot-time recovery unit is shipped.
- **Conffiles can hold a package back.** Locally modified
  `/etc/weather-pi/*.toml` files are never silently replaced. If the new package
  also changes the same file, the run holds the package back and logs a
  conffile-prompt warning; `--force-confold` and `--force-confnew` remain
  explicit operator choices.
- **An offline repository is a no-op.** The installed version and running
  service are unchanged, and the next daily run retries. No rollback or restart
  is triggered by a failed update.
- **Package traffic bypasses the tunnel.** The SSH tunnel is for operator
  access; apt uses its own direct HTTPS egress. No apt proxy is configured.

Rejected:

- **Updater inside the application binary.** Mixes display and update logic,
  puts network code in the application, and still needs a restart and rollback
  policy.
- **`weather-pi-updater` package with a health-gated wrapper and project
  timer.** Adds a package, unit, state file, and rollback logic; duplicates the
  distribution scheduler; a reliable health signal is not available on a single
  wall-mounted device.
- **Project timer running `apt-get` directly.** Reimplements
  `unattended-upgrades` and splits ownership of Debian security updates.
- **`DPkg::Post-Invoke`/`Post-Invoke-Success` health hook.** Reintroduces the
  wrapper and cannot decide whether to roll back without the same policy.
- **Local sequence/anti-replay counter.** Does not defend against a compromised
  signing key and is defeated by restoring the SD image; the `Valid-Until`
  window and protected archive key are the accepted boundary.

## Migration Plan

1. Build an image that installs `weather-pi` and the keyring at pinned versions and allows the project origin.
2. Confirm `unattended-upgrade --dry-run -d` lists the origin, the timer is enabled, and a fresh boot performs no changes.
3. Publish `v0.2.1`; confirm the next daily run installs it, the service restarts, and the panel redraws.
4. Pin the previous version explicitly, confirm the downgrade and restart, then let the next run return to the newest version.
5. Publish a deliberately bad `v0.2.2` to a staging repository; confirm it is not rolled back automatically, then recover by pinning `v0.2.1` and record the procedure.

## Open Questions

- Resolved: the image uses `Origins-Pattern` in `51weather-pi-unattended`, and the chroot check asserts that every distribution entry survives while the project entry is present.
- How long the panel stays blank during an upgrade restart, and whether that is acceptable without a service restart policy of its own; measure during hardware validation.
