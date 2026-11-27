#!/usr/bin/env bash
# Build and sign the weather-pi apt repository tree.
#
# Inputs:
#   $DIST_DIR           Directory with the .deb files (default: dist)
#   $REPO_DIR           Output repository tree (default: target/repo)
#   WEATHER_PI_ARCHIVE_KEY
#                       GPG key id used to sign InRelease (required)
#   WEATHER_PI_GPG_HOME Optional GNUPGHOME for the archive key
#
# The generated tree is safe to publish as static files. `InRelease` is written
# last so a client never accepts metadata before the packages it references are
# in place.
set -euo pipefail

# Release dates and Debian field values are ASCII; keep date month/day names
# stable regardless of the maintainer's locale.
export LC_ALL=C

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

DIST_DIR="${DIST_DIR:-dist}"
REPO_DIR="${REPO_DIR:-target/repo}"
DIST_NAME="${WEATHER_PI_DIST:-trixie}"
ORIGIN="weather-pi"
KEEP_VERSIONS="${WEATHER_PI_KEEP_VERSIONS:-5}"
# shellcheck disable=SC2206 # space-separated list is intentional
ARCHES=(${WEATHER_PI_ARCHES:-armhf arm64})

die() {
    echo "apt-repo.sh: $*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "required tool '$1' is not installed"
}

need apt-ftparchive
need dpkg
need dpkg-deb
need gpg
need gzip

[[ -n "${WEATHER_PI_ARCHIVE_KEY:-}" ]] || die "WEATHER_PI_ARCHIVE_KEY is not set"
[[ "$KEEP_VERSIONS" =~ ^[1-9][0-9]*$ ]] || die "WEATHER_PI_KEEP_VERSIONS must be a positive integer"
if [[ -n "${WEATHER_PI_GPG_HOME:-}" ]]; then
    export GNUPGHOME="$WEATHER_PI_GPG_HOME"
fi

# Sort "version filename" lines with Debian's comparison rules. `sort -V` is
# close but not identical to dpkg (for example 1.0.0+git sorts before
# 1.0.0-9 with sort -V, while Debian orders it after 1.0.0-10).
debian_version_sort() {
    local -a input=() sorted=()
    local line i pos

    mapfile -t input
    for line in "${input[@]}"; do
        pos=${#sorted[@]}
        for ((i = 0; i < ${#sorted[@]}; i++)); do
            if dpkg --compare-versions "${line%% *}" lt "${sorted[$i]%% *}"; then
                pos=$i
                break
            fi
        done
        sorted=("${sorted[@]:0:pos}" "$line" "${sorted[@]:pos}")
    done
    if [[ ${#sorted[@]} -gt 0 ]]; then
        printf '%s\n' "${sorted[@]}"
    fi
}

shopt -s nullglob
debs=("$DIST_DIR"/*.deb)
[[ ${#debs[@]} -gt 0 ]] || die "no .deb files in $DIST_DIR"
mapfile -t debs < <(printf '%s\n' "${debs[@]}" | sort)

pool_dir="$REPO_DIR/pool/main/w"
dists_dir="$REPO_DIR/dists/$DIST_NAME"
mkdir -p "$pool_dir" "${dists_dir}/main"

# Copy new packages into the pool, then prune old versions.
for deb in "${debs[@]}"; do
    package="$(dpkg-deb -f "$deb" Package)"
    version="$(dpkg-deb -f "$deb" Version)"
    arch="$(dpkg-deb -f "$deb" Architecture)"
    target_dir="$pool_dir/$package"
    mkdir -p "$target_dir"
    install -m 0644 "$deb" "$target_dir/${package}_${version}_${arch}.deb"
done

# Keep the newest $KEEP_VERSIONS versions per package and architecture. The
# Packages index is regenerated below, so pruned files disappear from it too.
for package_dir in "$pool_dir"/*/; do
    for arch in "${ARCHES[@]}"; do
        mapfile -t files < <(find "$package_dir" -maxdepth 1 -type f -name "*_${arch}.deb" -printf '%f\n')
        [[ ${#files[@]} -gt "$KEEP_VERSIONS" ]] || continue

        mapfile -t ordered < <(
            for file in "${files[@]}"; do
                printf '%s %s\n' "$(dpkg-deb -f "$package_dir/$file" Version)" "$file"
            done | debian_version_sort
        )

        remove_count=$((${#ordered[@]} - KEEP_VERSIONS))
        for ((i = 0; i < remove_count; i++)); do
            file="${ordered[$i]#* }"
            rm -f "$package_dir/$file"
        done
    done
done

# Generate Packages for each architecture from the shared pool.
for arch in "${ARCHES[@]}"; do
    arch_dir="${dists_dir}/main/binary-${arch}"
    mkdir -p "$arch_dir"

    (cd "$REPO_DIR" && apt-ftparchive packages pool) |
        awk -v RS= -v ORS='\n\n' -v arch="$arch" '
            $0 ~ ("(^|\n)Architecture: " arch "(\n|$)") { print }
        ' >"$arch_dir/Packages"

    gzip -9 -n -c "$arch_dir/Packages" >"$arch_dir/Packages.gz"

    # Acquire-By-Hash: publish content-addressed copies next to the index for
    # every hash algorithm listed in Release. apt prefers SHA512, then SHA256.
    for index in Packages Packages.gz; do
        declare -A hashes=(
            [MD5Sum]="$(md5sum "$arch_dir/$index" | awk '{print $1}')"
            [SHA1]="$(sha1sum "$arch_dir/$index" | awk '{print $1}')"
            [SHA256]="$(sha256sum "$arch_dir/$index" | awk '{print $1}')"
            [SHA512]="$(sha512sum "$arch_dir/$index" | awk '{print $1}')"
        )
        for algorithm in "${!hashes[@]}"; do
            mkdir -p "$arch_dir/by-hash/$algorithm"
            cp "$arch_dir/$index" "$arch_dir/by-hash/$algorithm/${hashes[$algorithm]}"
        done
        unset hashes
    done
done

# apt-ftparchive writes all hashes/sizes and the fields we configure here.
# Generate in a clean copy: scanning the live directory would otherwise hash
# the previous Release/InRelease into the new Release. Write the output outside
# the scanned tree so the temporary file cannot be indexed either.
valid_until="$(date -u -d '+7 days' '+%a, %d %b %Y %H:%M:%S UTC')"
release_config="$(mktemp)"
release_stage="$(mktemp -d)"
release_unsigned="$(mktemp)"
release_signed="$(mktemp)"
trap 'rm -rf "$release_config" "$release_stage" "$release_unsigned" "$release_signed"' EXIT

cat >"$release_config" <<EOF
APT::FTPArchive::Release {
    Origin "$ORIGIN";
    Label "$ORIGIN";
    Suite "$DIST_NAME";
    Codename "$DIST_NAME";
    Architectures "${ARCHES[*]}";
    Components "main";
    Description "weather-pi signed package archive";
    Acquire-By-Hash "yes";
    Valid-Until "$valid_until";
};
EOF

cp -a "$dists_dir/." "$release_stage/"
rm -f "$release_stage/Release" "$release_stage/InRelease" "$release_stage/Release.tmp" "$release_stage/InRelease.tmp"

(
    cd "$release_stage"
    apt-ftparchive -c "$release_config" release . >"$release_unsigned"
)

# apt-ftparchive does not emit Valid-Until itself; add it before signing so the
# signed metadata carries the expiry the design requires. Keep an existing field
# if a future apt version starts emitting it from the configuration above.
if ! grep -q '^Valid-Until: ' "$release_unsigned"; then
    sed -i "/^Date:/a Valid-Until: $valid_until" "$release_unsigned"
fi
grep -q '^Valid-Until: ' "$release_unsigned" || {
    echo "apt-repo.sh: failed to add Valid-Until to Release" >&2
    exit 1
}

for field in Origin Suite Codename Architectures Acquire-By-Hash Date Valid-Until; do
    grep -q "^${field}: " "$release_unsigned" || die "generated Release is missing '$field'"
done
grep -q '^Acquire-By-Hash: yes$' "$release_unsigned" || die "generated Release does not enable Acquire-By-Hash"

# Sign the new metadata before anything replaces the live Release/InRelease.
gpg_args=(--batch --yes --digest-algo SHA256 --local-user "$WEATHER_PI_ARCHIVE_KEY")
if [[ -n "${WEATHER_PI_ARCHIVE_PASSPHRASE:-}" ]]; then
    gpg_args+=(--pinentry-mode loopback --passphrase "$WEATHER_PI_ARCHIVE_PASSPHRASE")
fi
gpg "${gpg_args[@]}" --clearsign --output "$release_signed" "$release_unsigned"
gpg --batch --verify "$release_signed" >/dev/null 2>&1 || die "signed InRelease failed to verify"

# Publish Release first, InRelease last.
install -m 0644 "$release_unsigned" "$dists_dir/Release"
install -m 0644 "$release_signed" "$dists_dir/InRelease"

echo "Repository written to $REPO_DIR"
echo "  Origin:      $ORIGIN"
echo "  Suite:       $DIST_NAME"
echo "  Valid-Until: $valid_until"
echo "  Architectures: ${ARCHES[*]}"
