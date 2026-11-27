#!/usr/bin/env bash
# Build all Debian packages for the given Rust targets.
#
#   scripts/build-packages.sh [TARGET...]
#
# Default targets are the two supported device architectures. Packages are
# written to $DIST_DIR (default: dist).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

DIST_DIR="${DIST_DIR:-dist}"
REPO_URL="${WEATHER_PI_REPO_URL:-https://corrodedhash.github.io/weather-pi/}"
VERSION="${WEATHER_PI_VERSION:-$(scripts/version.sh from-git)}"

targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then
    targets=(arm-unknown-linux-gnueabihf aarch64-unknown-linux-gnu)
fi

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "build-packages.sh: required tool '$1' is not installed" >&2
        exit 1
    }
}

deb_arch() {
    case "$1" in
        arm-unknown-linux-gnueabihf | armv7-unknown-linux-gnueabihf) echo armhf ;;
        aarch64-unknown-linux-gnu) echo arm64 ;;
        x86_64-unknown-linux-gnu) echo amd64 ;;
        *) echo "build-packages.sh: unsupported target '$1'" >&2; exit 1 ;;
    esac
}

stage_deb() {
    local name="$1" arch="$2" control_template="$3" payload_dir="$4" keyring="${5:-}"
    local stage="target/packaging/${name}_${arch}"

    rm -rf "$stage"
    mkdir -p "$stage/DEBIAN"

    if [[ -n "$payload_dir" ]]; then
        cp -a "$payload_dir/." "$stage/"
    fi

    if [[ -n "$keyring" ]]; then
        install -D -m 0644 "$keyring" "$stage/usr/share/keyrings/weather-pi-archive.gpg"
    fi

    sed -e "s|@VERSION@|$VERSION|g" -e "s|@ARCH@|$arch|g" -e "s|@REPO_URL@|$REPO_URL|g" \
        "$control_template" >"$stage/DEBIAN/control"

    local size
    size="$(du -sk --exclude=DEBIAN "$stage" | awk '{print $1}')"
    sed -i "/^Priority:/a Installed-Size: $size" "$stage/DEBIAN/control"

    # Every file under /etc is a conffile.
    (cd "$stage" && { find etc -type f -printf '/%p\n' 2>/dev/null || true; } | sort) \
        >"$stage/DEBIAN/conffiles"
    if [[ ! -s "$stage/DEBIAN/conffiles" ]]; then
        rm -f "$stage/DEBIAN/conffiles"
    fi

    # dpkg -V needs an md5sums index to verify installed files.
    (
        cd "$stage"
        find . -path ./DEBIAN -prune -o -type f -printf '%P\0' |
            sort -z |
            xargs -0 -r md5sum >DEBIAN/md5sums
    )

    dpkg-deb --build --root-owner-group "$stage" "$DIST_DIR/${name}_${VERSION}_${arch}.deb"
}

mkdir -p "$DIST_DIR"

for target in "${targets[@]}"; do
    arch="$(deb_arch "$target")"
    echo "==> weather-pi $VERSION for $target ($arch)"

    if [[ "$target" == "$(rustc -vV | awk '/^host:/ { print $2 }')" ]]; then
        WEATHER_PI_VERSION="$VERSION" cargo build --target "$target" --release
    else
        WEATHER_PI_VERSION="$VERSION" mise x -- cross build --target "$target" --release
    fi

    mise x -- cargo deb --no-build \
        --target "$target" \
        --deb-version "$VERSION" \
        --output "$DIST_DIR/weather-pi_${VERSION}_${arch}.deb"
done

need dpkg-deb

keyring="${WEATHER_PI_ARCHIVE_KEYRING:-packaging/keyring/weather-pi-archive.gpg}"
if [[ ! -f "$keyring" ]]; then
    echo "build-packages.sh: archive keyring not found at $keyring" >&2
    echo "Export the public archive key with:" >&2
    echo "  gpg --export --armor <key-id> | gpg --dearmor > $keyring" >&2
    exit 1
fi

for target in "${targets[@]}"; do
    arch="$(deb_arch "$target")"
    echo "==> weather-pi-archive-keyring $VERSION ($arch)"
    stage_deb weather-pi-archive-keyring "$arch" \
        packaging/keyring/control \
        "" \
        "$keyring"
done

echo
echo "Packages in $DIST_DIR:"
ls -1 "$DIST_DIR"/*.deb

if command -v sha256sum >/dev/null 2>&1; then
    (cd "$DIST_DIR" && sha256sum ./*.deb >SHA256SUMS)
fi
