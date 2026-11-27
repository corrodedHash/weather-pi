#!/usr/bin/env bash
# Test the version mapping and the apt repository generator without a device.
#
# The repository half needs dpkg, dpkg-deb, apt-ftparchive, gpg and gzip. If a
# tool is missing the affected checks are reported as SKIP instead of passing
# silently. Everything is written to a temporary directory.
set -euo pipefail

# Valid-Until parsing and Release field output must not depend on the locale.
export LC_ALL=C

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/weather-pi-release-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

skipped=()

fail() {
    echo "test-release-pipeline.sh: $*" >&2
    exit 1
}

ok() {
    echo "ok: $*"
}

skip_section() {
    echo "SKIP: $*" >&2
    skipped+=("$*")
}

assert_eq() {
    local expected="$1" actual="$2" what="$3"
    [[ "$actual" == "$expected" ]] ||
        fail "$what: expected '$expected', got '$actual'"
}

# ---------------------------------------------------------------------------
# Version mapping and monotonicity
# ---------------------------------------------------------------------------

version="$(WEATHER_PI_VERSION='' DEBIAN_REVISION='' scripts/version.sh from-tag v1.2.3)"
assert_eq "1.2.3-1" "$version" "v1.2.3 mapping"
ok "v1.2.3 maps to 1.2.3-1"

if WEATHER_PI_VERSION='' DEBIAN_REVISION='' scripts/version.sh from-tag v1.2 >/dev/null 2>&1; then
    fail "accepted a non-semver tag"
fi
ok "non-semver tags are refused"

if command -v dpkg >/dev/null 2>&1; then
    packages="$tmp/Packages"
    {
        printf 'Package: weather-pi\nVersion: 1.2.3-1\n\n'
        printf 'Package: weather-pi-archive-keyring\nVersion: 1.2.1-1\n'
    } >"$packages"

    for candidate in 1.2.3-1 1.2.2-1 1.2.3-0; do
        if scripts/version.sh check "$candidate" "$packages" >/dev/null 2>&1; then
            fail "accepted non-increasing candidate $candidate"
        fi
    done
    ok "equal and lower versions are refused"

    scripts/version.sh check 1.2.4-1 "$packages"
    ok "a strictly greater version is accepted"

    : >"$tmp/empty-Packages"
    scripts/version.sh check 1.2.3-1 "$tmp/missing-Packages"
    scripts/version.sh check 1.2.3-1 "$tmp/empty-Packages"
    ok "a missing or empty published index does not block the first release"
else
    skip_section "dpkg is not installed; version comparison checks were skipped"
fi

# ---------------------------------------------------------------------------
# Signed repository generation and retention
# ---------------------------------------------------------------------------

missing=()
for tool in apt-ftparchive dpkg dpkg-deb gpg gzip; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    skip_section "repository checks were skipped; missing: ${missing[*]}"
else
    work="$tmp/repo-test"
    dist="$work/dist"
    repo="$work/repo"
    mkdir -p "$work/dist" "$work/repo" "$work/gnupg"
    chmod 700 "$work/gnupg"
    export GNUPGHOME="$work/gnupg"

    gpg --batch --passphrase '' --quick-generate-key \
        'weather-pi repository test <test@example.invalid>' rsa2048 sign 1d \
        >/dev/null 2>&1
    fingerprint="$(gpg --list-secret-keys --with-colons |
        awk -F: '/^fpr:/ { print $10; exit }')"
    [[ -n "$fingerprint" ]] || fail "could not read the test key fingerprint"
    gpg --batch --export "$fingerprint" >"$work/pub.gpg"

    make_deb() {
        local package="$1" package_version="$2" package_arch="$3"
        local pkg="$work/pkg"

        rm -rf "$pkg"
        mkdir -p "$pkg/DEBIAN" "$pkg/usr/share/$package"
        printf 'Package: %s\nVersion: %s\nArchitecture: %s\nMaintainer: Test <test@example.invalid>\nDescription: test package\n' \
            "$package" "$package_version" "$package_arch" >"$pkg/DEBIAN/control"
        printf 'test payload\n' >"$pkg/usr/share/$package/payload"
        dpkg-deb --build --root-owner-group "$pkg" \
            "$dist/${package}_${package_version}_${package_arch}.deb" >/dev/null
    }

    versions=(1.0.0-9 1.0.0-10 1.0.0+git 1.0.1-1 1.0.2-1 1.0.3-1 1.0.4-1)
    for arch in armhf arm64; do
        for package_version in "${versions[@]}"; do
            make_deb weather-pi "$package_version" "$arch"
        done
        make_deb weather-pi-archive-keyring 1.0.3-1 "$arch"
    done

    WEATHER_PI_ARCHIVE_KEY="$fingerprint" \
        WEATHER_PI_GPG_HOME="$GNUPGHOME" \
        DIST_DIR="$dist" \
        REPO_DIR="$repo" \
        scripts/apt-repo.sh >/dev/null
    ok "repository generated"

    release="$repo/dists/trixie/Release"
    inrelease="$repo/dists/trixie/InRelease"
    [[ -s "$release" ]] || fail "Release is missing"
    [[ -s "$inrelease" ]] || fail "InRelease is missing"

    grep -Fxq 'Origin: weather-pi' "$release" || fail "Release has no Origin field"
    grep -Fxq 'Suite: trixie' "$release" || fail "Release has no Suite field"
    grep -Fxq 'Codename: trixie' "$release" || fail "Release has no Codename field"
    grep -Fxq 'Architectures: armhf arm64' "$release" ||
        fail "Release has no expected Architectures field"
    grep -Fxq 'Acquire-By-Hash: yes' "$release" ||
        fail "Release does not enable Acquire-By-Hash"
    grep -q '^Valid-Until: ' "$release" || fail "Release has no Valid-Until field"
    grep -q '^Date: ' "$release" || fail "Release has no Date field"
    ok "Release carries the required fields"

    valid_until="$(sed -n 's/^Valid-Until: //p' "$release")"
    valid_epoch="$(date -u -d "$valid_until" +%s)" ||
        fail "Valid-Until is not a parseable date: $valid_until"
    now_epoch="$(date -u +%s)"
    ((valid_epoch > now_epoch)) || fail "Valid-Until is not in the future"
    ((valid_epoch <= now_epoch + 8 * 24 * 60 * 60)) ||
        fail "Valid-Until is more than eight days away"
    ok "Valid-Until is within the seven-day window"

    if command -v gpgv >/dev/null 2>&1; then
        gpgv --keyring "$work/pub.gpg" "$inrelease" >/dev/null 2>&1 ||
            fail "gpgv could not verify InRelease"
        ok "InRelease verifies with gpgv"
    else
        skip_section "gpgv is not installed; InRelease signature was not verified"
    fi

    kept=(1.0.0+git 1.0.1-1 1.0.2-1 1.0.3-1 1.0.4-1)
    pruned=(1.0.0-9 1.0.0-10)

    for arch in armhf arm64; do
        packages="$repo/dists/trixie/main/binary-$arch/Packages"
        packages_gz="$repo/dists/trixie/main/binary-$arch/Packages.gz"
        [[ -s "$packages" ]] || fail "missing Packages for $arch"
        [[ -s "$packages_gz" ]] || fail "missing Packages.gz for $arch"

        count="$(awk '/^Package: weather-pi$/ { n++ } END { print n + 0 }' "$packages")"
        [[ "$count" -eq 5 ]] || fail "expected five weather-pi versions for $arch, found $count"
        keyring_count="$(awk '/^Package: weather-pi-archive-keyring$/ { n++ } END { print n + 0 }' "$packages")"
        [[ "$keyring_count" -eq 1 ]] ||
            fail "expected one keyring version for $arch, found $keyring_count"

        for package_version in "${kept[@]}"; do
            grep -Fxq "Version: $package_version" "$packages" ||
                fail "Packages for $arch lost $package_version"
        done
        for package_version in "${pruned[@]}"; do
            if grep -Fxq "Version: $package_version" "$packages"; then
                fail "Packages for $arch still lists pruned $package_version"
            fi
        done
        gzip -dc "$packages_gz" | cmp -s - "$packages" ||
            fail "Packages.gz for $arch does not match Packages"
        ok "Packages for $arch lists the five retained versions"

        pool="$repo/pool/main/w/weather-pi"
        pool_count="$(find "$pool" -maxdepth 1 -type f -name "*_${arch}.deb" | wc -l | tr -d ' ')"
        [[ "$pool_count" -eq 5 ]] || fail "pool keeps $pool_count weather-pi files for $arch, expected 5"
        for package_version in "${kept[@]}"; do
            [[ -f "$pool/weather-pi_${package_version}_${arch}.deb" ]] ||
                fail "pool lost weather-pi_${package_version}_${arch}.deb"
        done
        for package_version in "${pruned[@]}"; do
            [[ ! -f "$pool/weather-pi_${package_version}_${arch}.deb" ]] ||
                fail "pool still contains pruned weather-pi_${package_version}_${arch}.deb"
        done
        ok "pool retains five versions for $arch"

        for index in Packages Packages.gz; do
            index_path="$repo/dists/trixie/main/binary-$arch/$index"
            hash="$(sha256sum "$index_path" | awk '{ print $1 }')"
            [[ -f "$repo/dists/trixie/main/binary-$arch/by-hash/SHA256/$hash" ]] ||
                fail "by-hash copy is missing for $index ($arch)"
            grep -Eq "^[[:space:]]+${hash}[[:space:]]+[0-9]+[[:space:]]+main/binary-${arch}/${index}$" \
                "$release" || fail "Release does not hash $index ($arch)"
        done
        ok "by-hash indexes match Release for $arch"
    done

    # Simulate a later CI run that restores the apt branch and adds one new
    # version: retention must still apply to the combined pool.
    increment="$work/increment"
    mkdir -p "$increment"
    dist="$increment"
    for arch in armhf arm64; do
        make_deb weather-pi 1.0.5-1 "$arch"
    done
    WEATHER_PI_ARCHIVE_KEY="$fingerprint" \
        WEATHER_PI_GPG_HOME="$GNUPGHOME" \
        DIST_DIR="$dist" \
        REPO_DIR="$repo" \
        scripts/apt-repo.sh >/dev/null

    for arch in armhf arm64; do
        packages="$repo/dists/trixie/main/binary-$arch/Packages"
        count="$(awk '/^Package: weather-pi$/ { n++ } END { print n + 0 }' "$packages")"
        [[ "$count" -eq 5 ]] ||
            fail "incremental publication kept $count weather-pi versions for $arch, expected 5"
        grep -Fxq 'Version: 1.0.5-1' "$packages" || fail "new version is missing for $arch"
        if grep -Fxq 'Version: 1.0.0+git' "$packages"; then
            fail "oldest retained version was not pruned for $arch"
        fi
    done
    ok "incremental publication prunes the combined pool"
fi

echo
if [[ ${#skipped[@]} -gt 0 ]]; then
    echo "Skipped checks:"
    printf ' - %s\n' "${skipped[@]}"
fi
echo "PASS: release pipeline checks completed"
