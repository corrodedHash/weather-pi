# Updating weather-pi

The device updates itself from the project's signed apt repository with Debian's
`unattended-upgrades`. There is no project updater binary, wrapper, timer, or
status command. `apt`, `dpkg`, `systemd`, and the unattended-upgrades log are the
operator interface.

This guide targets Raspberry Pi OS trixie. Commands are run on the device, for
example over the SSH tunnel. Queries can be run as the normal operator account;
`apt`, `dpkg`, the dry run, and anything that changes package state need root, so
the examples use `sudo` where needed.

The timings in this guide come from the packaged systemd timers, not from a
hardware measurement. Actual publication-to-installation time and display
behaviour are tracked in `tasks.md` (2.1, 5.1-5.2).

## How an update reaches the device

1. A release tag is built into `weather-pi` and
   `weather-pi-archive-keyring` packages and published to the signed apt
   repository. `InRelease` is uploaded last, after the packages it references.
2. The device's `apt-daily.timer` refreshes the package lists from the
   repository.
3. `apt-daily-upgrade.timer` runs the distribution's daily upgrade job, which
   calls `unattended-upgrade`.
4. `unattended-upgrade` offers only packages that are already installed from an
   allowed origin. For this image those are `weather-pi` and
   `weather-pi-archive-keyring`.
5. apt verifies the repository signature, the metadata hashes, `Valid-Until`,
   and the package hashes. dpkg installs the package, and the package's
   maintainer scripts restart `weather-pi.service`; the display is expected to
   redraw.

Nothing is pushed to the device. A release is picked up on the device's next
list refresh and daily upgrade run.

## What is installed

| Path | Purpose |
| --- | --- |
| `/etc/apt/sources.list.d/weather-pi.list` | The project repository, restricted to the archive keyring with `signed-by=`. |
| `/usr/share/keyrings/weather-pi-archive.gpg` | Public archive key shipped in the image and by `weather-pi-archive-keyring`. |
| `/etc/apt/preferences.d/weather-pi.pref` | Pins `weather-pi` and the keyring to `o=weather-pi`. |
| `/etc/apt/apt.conf.d/90weather-pi` | `Valid-Until` enforcement, retries, download cache, dpkg lock timeout. |
| `/etc/apt/apt.conf.d/20auto-upgrades` | Enables periodic list refresh and unattended upgrades. |
| `/etc/apt/apt.conf.d/51weather-pi-unattended` | Adds `origin=weather-pi,archive=trixie` to the allowed origins. |
| `/usr/lib/weather-pi/check-update-config.sh` | Read-only verification helper, also used by the image build. |
| `/var/log/unattended-upgrades/unattended-upgrades.log` | One summary record per daily run. |
| `/var/log/unattended-upgrades/unattended-upgrades-dpkg.log` | dpkg output from the last install. |
| `/var/cache/apt/archives/` | Best-effort retained archives for an offline reinstall or rollback. |

The repository source uses the archive key explicitly:

```text
deb [signed-by=/usr/share/keyrings/weather-pi-archive.gpg] https://corrodedhash.github.io/weather-pi/ trixie main
```

The project origin is added without replacing the distribution's origins:

```text
Unattended-Upgrade::Origins-Pattern {
    "origin=weather-pi,archive=trixie";
};
```

The pin is deliberately not a version pin:

```text
Package: weather-pi weather-pi-archive-keyring
Pin: release o=weather-pi
Pin-Priority: 500
```

It tells apt that these two packages belong to the project archive; it does not
force a downgrade or block a newer version.

## Check the current state

Run these first; they are read-only apart from the list refresh:

```sh
sudo apt-get update
apt-cache policy weather-pi
dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' \
  weather-pi weather-pi-archive-keyring
sudo /usr/lib/weather-pi/check-update-config.sh
```

`apt-cache policy weather-pi` should show an installed version and a candidate.
When the repository has a newer release, it looks like this (versions and URLs
vary):

```text
weather-pi:
  Installed: 0.2.0-1
  Candidate: 0.2.1-1
  Version table:
     0.2.1-1 500
        500 https://corrodedhash.github.io/weather-pi trixie/main armhf Packages
 *** 0.2.0-1 500
        500 https://corrodedhash.github.io/weather-pi trixie/main armhf Packages
        100 /var/lib/dpkg/status
```

If `Candidate` equals `Installed`, the device is up to date. `(none)` normally
means the package lists are missing or the repository could not be verified;
rerun `apt-get update` and read its errors. The `500` priority is the origin
pin, not a hold.

`dpkg-query` should report both packages as `install ok installed`:

```text
weather-pi	0.2.0-1	install ok installed
weather-pi-archive-keyring	0.2.0-1	install ok installed
```

The verification helper checks the static configuration and then performs a
dry run:

```sh
sudo /usr/lib/weather-pi/check-update-config.sh
```

A healthy device ends with:

```text
Summary: 8 passed, 0 failed, 0 skipped
RESULT: PASS
```

The exit status is zero only if all static checks pass and the dry run itself
succeeds. A dry run that reports no packages is a pass; that is the normal
up-to-date result. Use `--no-dry-run` for the static checks only (the image
build does this in its chroot).

To see what the next run would do without installing anything:

```sh
sudo unattended-upgrade --dry-run -d 2>&1 \
  | grep -E 'Allowed origins|weather-pi|Packages that will be upgraded|No packages found'
```

The dry run does not install packages. It should list
`origin=weather-pi,archive=trixie` among the allowed origins. If a newer release
is available it prints a line such as
`Packages that will be upgraded: weather-pi`; otherwise it prints the normal
`No packages found that can be upgraded unattended...` message. A command
failure (non-zero exit) is an error, not an up-to-date result.

To list versions that are still in the repository index:

```sh
apt-cache madison weather-pi
```

The repository keeps the five newest versions per architecture. `madison` only
shows versions in the current index; it does not show archives that remain in
the local cache after a version has been pruned.

## The daily schedule

Inspect the distribution timers, not a project timer:

```sh
systemctl list-timers apt-daily.timer apt-daily-upgrade.timer
systemctl is-enabled apt-daily.timer apt-daily-upgrade.timer
systemctl is-active apt-daily.timer apt-daily-upgrade.timer
systemctl cat apt-daily.timer apt-daily-upgrade.timer
```

Both timers should be `enabled`, and `is-active` should print `active` for each
timer. `list-timers` should show a `NEXT` time for both. The service unit itself
is a oneshot, so after a successful run it is normally inactive (dead) with a
successful result:

```sh
systemctl status apt-daily-upgrade.service --no-pager
```

On Raspberry Pi OS trixie the stock timers are:

| Timer | Schedule | Purpose |
| --- | --- | --- |
| `apt-daily.timer` | `OnCalendar=*-*-* 6,18:00`, `RandomizedDelaySec=12h` | Refresh package lists. |
| `apt-daily-upgrade.timer` | `OnCalendar=*-*-* 6:00`, `RandomizedDelaySec=60m` | Run the unattended upgrade once a day. |

Both have `Persistent=true`. The randomized delay spreads devices out; it is not
a fixed maintenance window. `Persistent=true` means a run missed while the
device was off is started after the next boot, once the clock is usable.

The two jobs do not form a push pipeline. The upgrade service uses the package
lists that are present; `apt-daily.timer` refreshes them twice a day. With the
stock timers, a newly published release is commonly installed within a day.
If a release is published just after a list refresh and the timer offsets are
unlucky, allow roughly two days. A device that is off or offline takes longer
and catches up on a later boot and run.

This is not an immediate deployment mechanism. For an urgent rollout, refresh
the lists and run the upgrade now:

```sh
sudo apt-get update
sudo unattended-upgrade -d
```

Preview that with `--dry-run -d` first. Running
`sudo systemctl start apt-daily-upgrade.service` starts the daily job with the
lists already on disk.

The periodic switches are explicit:

```sh
apt-config dump \
  | grep -E 'APT::Periodic::(Update-Package-Lists|Unattended-Upgrade)'
```

Expected:

```text
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
```

## Trust chain and repository identity

The trust anchor is the archive public key, not a project updater:

- apt downloads `InRelease`, which is the clearsigned `Release` file, from the
  project repository.
- apt verifies the signature with the key at
  `/usr/share/keyrings/weather-pi-archive.gpg`, the path named by `signed-by=`
  in the source line.
- apt verifies the hashes and sizes in `Release` for `Packages`, `Packages.gz`,
  and each `.deb`.
- apt refuses unsigned metadata, a signature from an unknown key, a hash
  mismatch, expired metadata, and a package whose hash does not match.

The project release carries `Origin: weather-pi`, `Suite: trixie`, and
`Codename: trixie`. `origin=weather-pi,archive=trixie` matches the first two
fields (`archive` is apt's alias for the suite). The origin pin keeps these
packages associated with `o=weather-pi`.

The project fragment adds to the distribution's list; apt appends list values
across `apt.conf.d` fragments. The image build copies the project fragment out
of the way, snapshots `Unattended-Upgrade::Origins-Pattern`, restores it, and
asserts that every distribution entry survived. It also asserts that the project
entry is present. `check-update-config.sh` cannot move the fragment, so it
performs the read-only part: it requires at least one Debian, Raspbian,
Raspberry Pi Foundation, or Raspberry Pi OS origin.

The repository's `Valid-Until` is seven days after the metadata is generated,
and the image sets:

```text
Acquire::Check-Valid-Until "true";
```

Consequences:

- Expired project metadata is refused; no package from the project repository
  is installed. The installed application keeps running.
- If no release is published for more than seven days, the project metadata
  expires until the next release regenerates it. `apt-get update` then reports
  an expired `Release` file for the project source, and the daily job logs the
  failure. This affects discovery of new project releases, not the installed
  application. A new release restores the repository.
- There is no replay counter beyond apt's version ordering and the
  `Valid-Until` window. An old snapshot served inside the validity window is an
  accepted residual risk, together with a compromised archive key.

Downloaded archives are retained by apt because the image sets:

```text
APT::Keep-Downloaded-Packages "true";
```

`unattended-upgrades` has a separate cleanup switch,
`Unattended-Upgrade::Keep-Debs-After-Install`, which the image does not enable.
After a successful automatic install it removes the archive it just downloaded.
The cache is therefore a best-effort offline fallback, not a guaranteed copy of
every installed version: a version installed earlier by apt-get (including the
image build, if its cache was not cleaned) may still be present, while the
archive from the latest automatic run usually is not. Check before relying on
it:

```sh
ls -1 /var/cache/apt/archives/weather-pi_*.deb
```

If the version you need is absent, use the repository's retained versions.
Running `apt-get clean` removes everything; do not do that if you rely on an
offline rollback.

### Key rotation

Archive key rotation is a repository operation, documented in
[`docs/releasing.md`](releasing.md). The device-side contract is:

1. A new keyring package contains both the old and new public keys and is
   published while the repository is still signed by the old key.
2. Devices install it through the normal unattended path. The keyring package
   is itself a project package and is allowed by the same origin.
3. Only after the overlap keyring is published is repository metadata signed
   with the new key.
4. A later keyring package drops the old key.

Do not hold or downgrade `weather-pi-archive-keyring` during a rotation. A
device that missed the overlap needs the keyring package from the release
assets or a reflash; without the new key it cannot verify metadata signed only
by the new key.

### Package traffic and the tunnel

Package traffic is ordinary HTTPS from the device to the repository host. It
does not go through the SSH tunnel used for operator access. The tunnel is only
a management path; if the device's network permits SSH to the VPS but not
outbound HTTPS, apt cannot update. No apt proxy is configured by the image:

```sh
apt-config dump | grep -iE 'Acquire::(http|https)::Proxy' \
  || echo 'no apt proxy configured'
```

If a proxy is required, configure it deliberately with apt; that changes the
network path described here.

## Logs

The authoritative log is the unattended-upgrades file:

```sh
sudo tail -n 50 /var/log/unattended-upgrades/unattended-upgrades.log
sudo tail -n 100 /var/log/unattended-upgrades/unattended-upgrades-dpkg.log
```

A successful run looks like this (timestamps, versions, and origin lists vary):

```text
2026-11-27 06:07:12,345 INFO Starting unattended upgrades script
2026-11-27 06:07:12,346 INFO Allowed origins are: origin=weather-pi,archive=trixie, origin=Debian,codename=trixie,label=Debian, ...
2026-11-27 06:07:14,123 INFO Packages that will be upgraded: weather-pi
2026-11-27 06:07:14,124 INFO Writing dpkg log to /var/log/unattended-upgrades/unattended-upgrades-dpkg.log
2026-11-27 06:07:18,999 INFO All upgrades installed
```

An up-to-date run ends with:

```text
2026-11-27 06:08:02,456 INFO No packages found that can be upgraded unattended and no pending auto-removals
```

A conffile that the new package also changed is reported like this, and the
package is left installed at its old version:

```text
2026-11-27 06:08:02,457 WARNING Package weather-pi has conffile prompt and needs to be upgraded manually
```

A failed install records the error and points at the dpkg log:

```text
2026-11-27 06:08:03,000 ERROR Installing the upgrades failed!
2026-11-27 06:08:03,001 ERROR error message: ...
2026-11-27 06:08:03,002 ERROR dpkg returned a error! See /var/log/unattended-upgrades/unattended-upgrades-dpkg.log for details
```

The journal shows the systemd jobs and the application restart. The
unattended-upgrades package does not enable syslog logging by default, so the
main update record is the file above, not the journal:

```sh
sudo journalctl -u apt-daily-upgrade.service --since '7 days ago' --no-pager
sudo journalctl -u weather-pi.service --since '7 days ago' --no-pager
```

Representative journal lines:

```text
Nov 27 06:07:11 weather-pi systemd[1]: Starting apt-daily-upgrade.service - Daily apt upgrade and clean activities...
Nov 27 06:07:19 weather-pi systemd[1]: Finished apt-daily-upgrade.service - Daily apt upgrade and clean activities.
Nov 27 06:07:18 weather-pi systemd[1]: Stopping weather-pi e-ink display service...
Nov 27 06:07:18 weather-pi systemd[1]: Started weather-pi e-ink display service.
```

Use `journalctl -f` while triggering an urgent update if you want to watch the
service lifecycle. `unattended-upgrade -d` also prints its debug output to the
terminal.

## What the automatic path does and does not do

**No downgrade.** apt selects a candidate only when it is newer than the
installed version; `Unattended-Upgrade::Allow-downgrade` is not enabled. If the
repository offers only an older version, the automatic run does nothing. Only
an explicit `apt-get install --allow-downgrades` changes the installed version
to an older one.

**No health gate.** Installation success is the only automatic criterion. The
package restarts `weather-pi.service`, and `Restart=on-failure` handles a
crashing binary. A release that installs and runs but draws the panel badly is
not detected. Validation on hardware before publication is the only guard.

**No automatic rollback.** There is no recorded "last good" version and no
automatic reversal. A bad release stays installed until the operator pins an
older retained or cached version, or publishes a fix. The cache and the
repository's five-version retention make that possible; they do not make it
automatic.

**An offline repository is a no-op for the application.** If the host is
unreachable, apt logs a download failure and installs nothing. The installed
version and running service are unchanged, and the next daily run retries. If
the project metadata has expired, apt refuses it until a new release regenerates
it. No rollback or restart is triggered by a failed update.

**Only project packages come from the project origin.** The repository contains
`weather-pi` and `weather-pi-archive-keyring`; the origin pattern does not allow
other project packages, and the distribution's own origins remain allowed.
Debian and Raspberry Pi OS updates continue through their normal entries.

**apt serializes access.** The daily job and a manual `apt-get` use apt's lock;
the image sets `DPkg::Lock::Timeout "120"`. If a manual command waits, let the
daily job finish rather than removing lock files. `systemctl status
apt-daily-upgrade.service` and the log show whether a run is active.

**Conffiles can hold a package back.** This is covered in the next section; it
is the one common case where an update is visible but not installed.

## Pinning, holding, and downgrading

A hold prevents the daily job from upgrading a package. It is the simplest way
to stay on a version while you investigate a bad release.

```sh
# Show anything currently held.
apt-mark showhold

# Stop automatic upgrades of the application.
sudo apt-mark hold weather-pi

# Resume automatic upgrades.
sudo apt-mark unhold weather-pi
```

Find an older version that is still in the repository or in the local cache:

```sh
apt-cache madison weather-pi
ls -1 /var/cache/apt/archives/weather-pi_*.deb
sudo dpkg-deb -f '/var/cache/apt/archives/weather-pi_<version>_<arch>.deb' Version
```

`<arch>` is `armhf` on a Pi Zero and `arm64` on a Pi Zero 2 W; check it with:

```sh
dpkg --print-architecture
```

Downgrade from the repository:

```sh
sudo apt-get update
sudo apt-get install --allow-downgrades 'weather-pi=<version>'
systemctl status weather-pi.service --no-pager
```

Downgrade from the retained archive when the repository no longer carries that
version (this also works without network access to the repository):

```sh
sudo apt-get install --allow-downgrades \
  '/var/cache/apt/archives/weather-pi_<version>_<arch>.deb'
systemctl status weather-pi.service --no-pager
```

If `weather-pi` is held, unhold it first. apt may also require
`--allow-change-held-packages` for an explicit version change; unholding is
clearer.

After a downgrade, the next daily run will normally upgrade to the newest
available version again. To stay on the older version, hold it:

```sh
sudo apt-mark hold weather-pi
```

When the fix is ready, unhold it and either wait for the daily run or refresh and
run now:

```sh
sudo apt-mark unhold weather-pi
sudo apt-get update
sudo unattended-upgrade -d
```

The package's maintainer scripts restart `weather-pi.service` after an install
or downgrade. Verify the unit and the display after the command; if the service
was not restarted, `sudo systemctl restart weather-pi` is the restart-only
recovery.

There is no separate updater CLI, no `last-good` marker, and no version that is
automatically preferred. The operator chooses the version explicitly.

## Conffiles and configuration

`/etc/weather-pi/greeter.toml` and `/etc/weather-pi/countdown.toml` are Debian
conffiles. List the registered files with:

```sh
dpkg-query -W -f='${Conffiles}\n' weather-pi
```

The unattended path never prompts. Its default behaviour is:

- If the new package leaves a conffile unchanged, your edited file is kept and
  the upgrade proceeds.
- If the new package also changes that conffile, dpkg would need a decision.
  `unattended-upgrades` detects that and holds the package back, logging
  `has conffile prompt and needs to be upgraded manually`; your file is not
  overwritten and the package stays at its old version.

The project image does not set a global `--force-confold`. With the stock
unattended-upgrades configuration, this safe hold-back is the default. Resolve
it deliberately after backing up.

### Back up and restore

Back up the whole configuration directory, including ownership and timestamps:

```sh
sudo tar -C /etc -cpzf "/root/weather-pi-etc-$(date -u +%Y%m%dT%H%M%SZ).tar.gz" weather-pi
sudo tar -tzf '/root/weather-pi-etc-<timestamp>.tar.gz'
```

Restore a backup after stopping the service:

```sh
sudo systemctl stop weather-pi.service
sudo tar -C /etc -xpzf '/root/weather-pi-etc-<timestamp>.tar.gz'
sudo systemctl start weather-pi.service
```

If you only want a copy before editing a file:

```sh
sudo cp -a /etc/weather-pi/greeter.toml /root/greeter.toml.before
```

### Choose the conffile policy deliberately

To install the pending upgrade and keep your current file:

```sh
sudo apt-get -o Dpkg::Options::="--force-confold" install weather-pi
```

dpkg keeps the local file and writes the packaged version next to it as
`<file>.dpkg-dist`, for example
`/etc/weather-pi/greeter.toml.dpkg-dist`. Compare and merge the two files, then
restart the service.

To take the packaged file and keep a copy of the old one:

```sh
sudo systemctl stop weather-pi.service
sudo cp -a /etc/weather-pi /root/weather-pi-etc-before-confnew
sudo apt-get -o Dpkg::Options::="--force-confnew" install --reinstall weather-pi
sudo systemctl start weather-pi.service
```

dpkg saves the old local file as `<file>.dpkg-old`. Use `--reinstall` when the
candidate is already the installed version and you want to reapply the packaged
conffiles; for a pending upgrade, omit it.

These `-o` options apply to that one apt command. If you deliberately want every
unattended run to keep local conffiles instead of holding packages back, add a
local fragment such as:

```text
Dpkg::Options {
    "--force-confold";
};
```

That applies to every package, including Debian security updates, so only add it
if you accept losing new packaged defaults and resolving them manually. The
image does not do this by default.

After any manual conffile change, restart the application so it rereads the
files:

```sh
sudo systemctl restart weather-pi.service
systemctl status weather-pi.service --no-pager
```

## Recovery

Start with triage; these commands are safe and do not change package state:

```sh
sudo dpkg --audit
dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' \
  weather-pi weather-pi-archive-keyring
apt-cache policy weather-pi
systemctl status weather-pi.service --no-pager
sudo tail -n 50 /var/log/unattended-upgrades/unattended-upgrades.log
sudo tail -n 100 /var/log/unattended-upgrades/unattended-upgrades-dpkg.log
```

`dpkg --audit` prints nothing when the package database is consistent. If it
reports a package that is unpacked but not configured, or a half-installed
package, complete the standard recovery path.

### Interrupted installation or power loss

The device boots even if the application package was interrupted. The tunnel
unit is independent of `weather-pi.service`, so remote access should still come
up; if it does not, use the local console or reflash. Power loss during dpkg can
leave the package unconfigured, but the previous files are generally still
present and the package database knows what was interrupted.

Complete it in this order:

```sh
sudo dpkg --audit
sudo dpkg --configure -a
sudo apt-get -f install
sudo apt-get install --reinstall weather-pi
sudo systemctl restart weather-pi.service
systemctl status weather-pi.service --no-pager
```

- `dpkg --configure -a` finishes any package that was unpacked but not
  configured.
- `apt-get -f install` repairs a broken dependency state left by the interrupted
  run.
- `apt-get install --reinstall weather-pi` replaces a half-unpacked or otherwise
  inconsistent application package. If the candidate is not the version you
  want, name the installed version explicitly or install the cached `.deb` as
  described above.
- `systemctl restart weather-pi` is enough when the package is correctly
  installed but the service did not come back or is running with old
  configuration.

The next non-dry unattended-upgrades run may also detect an unclean dpkg state
and run `dpkg --configure -a` itself, but do not rely on waiting for it. The
manual path above is immediate and uses the same commands.

If `dpkg --audit` reports a package in a "reinst-required" state,
`apt-get install --reinstall weather-pi` is the standard repair. If apt cannot
proceed because the repository is unreachable, install the matching cached
archive directly:

```sh
sudo apt-get install --reinstall \
  '/var/cache/apt/archives/weather-pi_<version>_<arch>.deb'
sudo dpkg --configure -a
```

If the image itself or the boot process is broken, package recovery is out of
scope: reflash the device image. This guide covers package-level recovery only.

### A bad release that installs but misbehaves

There is no automatic rollback. Recover with an explicit version pin:

```sh
apt-cache madison weather-pi
ls -1 /var/cache/apt/archives/weather-pi_*.deb
sudo apt-get install --allow-downgrades 'weather-pi=<known-good-version>'
# If that version is no longer in the index, use the cached archive:
# sudo apt-get install --allow-downgrades '/var/cache/apt/archives/weather-pi_<version>_<arch>.deb'
sudo apt-mark hold weather-pi
systemctl status weather-pi.service --no-pager
```

The hold prevents the next daily run from immediately reinstalling the bad
version. When a fixed release is published, unhold and update. If the bad
release is still newer than the fixed one, the repository's version ordering is
what prevents an automatic downgrade; publish a new version rather than relying
on a re-tagged old one.

### Restart-only recovery

If the package version is correct and only the process is stuck:

```sh
sudo systemctl restart weather-pi.service
systemctl status weather-pi.service --no-pager
sudo journalctl -u weather-pi.service -n 100 --no-pager
```

If the unit is not found, the package is not installed correctly; use the
interrupted-installation path above. If the unit is in a failed state, inspect
the journal before restarting in a loop.

### apt is busy

If a manual apt command waits or fails with a lock message, the daily job is
probably running. Do not delete lock files. Wait, then check:

```sh
systemctl status apt-daily-upgrade.service --no-pager
sudo tail -n 20 /var/log/unattended-upgrades/unattended-upgrades.log
```

`DPkg::Lock::Timeout "120"` lets apt wait for a short time. After the run
finishes, repeat the command.

## Verification checklist

Run these after boot, after a repository or key change, and after any manual
recovery. Expected results are for a healthy, up-to-date device.

| Check | Command | Expected |
| --- | --- | --- |
| Repository refresh | `sudo apt-get update` | Exit 0; project `InRelease` fetched; no `NO_PUBKEY`, `EXPKEYSIG`, hash error, or expired `Release`. |
| Installed and candidate | `apt-cache policy weather-pi` | `Installed` is the expected version; `Candidate` is equal or newer; project entries show priority `500`. |
| Package database | `dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' weather-pi weather-pi-archive-keyring` | Both lines end in `install ok installed`. |
| Static config and dry run | `sudo /usr/lib/weather-pi/check-update-config.sh` | `Summary: ... 0 failed ...` and `RESULT: PASS`; dry run lists the project origin and either a candidate or "No packages found". |
| Periodic switches | `apt-config dump \| grep -E 'APT::Periodic::(Update-Package-Lists\|Unattended-Upgrade)'` | Both values are `"1"`. |
| Validity and cache | `apt-config dump \| grep -E 'Acquire::Check-Valid-Until\|APT::Keep-Downloaded-Packages'` | `"true"` for both. |
| Project origin | `apt-config dump \| grep -F 'origin=weather-pi,archive=trixie'` | One matching line. |
| Distribution origins | `apt-config dump \| grep -E 'origin=(Debian\|Raspbian\|Raspberry Pi)'` | At least one distribution origin remains. |
| Timers enabled | `systemctl is-enabled apt-daily.timer apt-daily-upgrade.timer` | `enabled` twice. |
| Timers active | `systemctl is-active apt-daily.timer apt-daily-upgrade.timer` | `active` twice. |
| Next runs | `systemctl list-timers apt-daily.timer apt-daily-upgrade.timer` | Both timers have a `NEXT` time. |
| Timer configuration | `systemctl cat apt-daily.timer apt-daily-upgrade.timer` | Randomized delay and `Persistent=true` are present. |
| Dry run detail | `sudo unattended-upgrade --dry-run -d` | Exit 0; `Allowed origins are:` includes the project origin; no package is installed. |
| Recent run | `sudo tail -n 50 /var/log/unattended-upgrades/unattended-upgrades.log` | Recent `Starting`, `Allowed origins`, and `All upgrades installed` or `No packages found`. |
| Download cache | `ls -1 /var/cache/apt/archives/weather-pi_*.deb` | May be empty. A retained archive enables an offline rollback; without one, use the repository's retained versions. |
| Holds | `apt-mark showhold` | No `weather-pi` unless a hold is intentional. |
| Package consistency | `sudo dpkg --audit` | No output. |

If a check fails, read the relevant section above and the unattended-upgrades
log before changing package state. Do not remove apt or dpkg lock files while a
process is alive, and do not run `apt-get clean` if you need the cached rollback
archive.

## Related documentation

- [`docs/releasing.md`](releasing.md) covers the repository layout, archive key
  ceremony, key rotation, and release publication.
- The image stages under `image/stage-weather-pi/` contain the source line, pin,
  apt configuration, and unattended-upgrades fragments.
- `scripts/check-update-config.sh` is the repository copy of the verification
  helper installed at `/usr/lib/weather-pi/check-update-config.sh`.
