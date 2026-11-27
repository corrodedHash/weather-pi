#!/usr/bin/env bash
# Build the weather-pi device image with a pinned pi-gen checkout.
#
# The build is opt-in and needs a working Docker daemon with privileged
# container support: pi-gen creates loop devices and runs the armhf chroot
# through QEMU. The repository URL and archive keyring are inputs because the
# image installs packages from the signed apt repository.
#
#   WEATHER_PI_REPO_URL=https://example.invalid/weather-pi/ \
#   WEATHER_PI_ARCHIVE_KEYRING=packaging/keyring/weather-pi-archive.gpg \
#   mise run image
#
# IMAGE_PREPARE_ONLY=1 stops after the pi-gen tree and the stage are assembled,
# which is useful for inspecting the payload without a Docker build.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Pinned upstream revision of RPi-Distro/pi-gen: the armhf, trixie release tag
# 2026-10-06-raspios-trixie-armhf.
PIGEN_REPO="${PIGEN_REPO:-https://github.com/RPi-Distro/pi-gen.git}"
PIGEN_REV="${PIGEN_REV:-291c62c1108d03f594dbed65507e97eb0d9a2b0e}"

IMAGE_BUILD_DIR="${IMAGE_BUILD_DIR:-$repo_root/target/image}"
PIGEN_DIR="$IMAGE_BUILD_DIR/pi-gen"
STAGE_NAME="stage-weather-pi"
STAGE_SRC="$repo_root/image/$STAGE_NAME"
CONFIG="$IMAGE_BUILD_DIR/config"

REPO_URL="${WEATHER_PI_REPO_URL:-https://corrodedhash.github.io/weather-pi/}"
KEYRING="${WEATHER_PI_ARCHIVE_KEYRING:-$repo_root/packaging/keyring/weather-pi-archive.gpg}"

die() {
    echo "image/build.sh: $*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "required tool '$1' is not installed"
}

escape_sed() {
    printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

need git
need docker

[[ -d "$STAGE_SRC" ]] || die "stage source not found at $STAGE_SRC"
[[ -s "$KEYRING" ]] || die "archive keyring not found at $KEYRING
Export the public archive key first, or set WEATHER_PI_ARCHIVE_KEYRING."

mkdir -p "$IMAGE_BUILD_DIR"

if [[ ! -d "$PIGEN_DIR/.git" ]]; then
    rm -rf "$PIGEN_DIR"
    git clone --filter=blob:none "$PIGEN_REPO" "$PIGEN_DIR"
fi

if ! git -C "$PIGEN_DIR" cat-file -e "$PIGEN_REV^{commit}" 2>/dev/null; then
    git -C "$PIGEN_DIR" fetch --depth 1 origin "$PIGEN_REV"
fi
git -C "$PIGEN_DIR" checkout --detach --force "$PIGEN_REV"
git -C "$PIGEN_DIR" clean -ffdx

# The stage is copied into the pi-gen tree so build-docker.sh can see it from
# inside the container; pi-gen does not mount arbitrary host directories.
rm -rf "${PIGEN_DIR:?}/$STAGE_NAME"
cp -a "$STAGE_SRC" "$PIGEN_DIR/$STAGE_NAME"
install -D -m 0644 "$KEYRING" \
    "$PIGEN_DIR/$STAGE_NAME/00-apt/files/usr/share/keyrings/weather-pi-archive.gpg"

repo_url_escaped="$(escape_sed "$REPO_URL")"
while IFS= read -r file; do
    sed -i "s|@WEATHER_PI_REPO_URL@|$repo_url_escaped|g" "$file"
done < <(grep -rlF '@WEATHER_PI_REPO_URL@' "$PIGEN_DIR/$STAGE_NAME")

# stage2 would otherwise export its own intermediate image.
touch "$PIGEN_DIR/stage2/SKIP_IMAGES"

cp "$repo_root/image/config" "$CONFIG"

if [[ "${IMAGE_PREPARE_ONLY:-0}" == "1" ]]; then
    echo "pi-gen prepared at $PIGEN_DIR"
    echo "stage prepared at $PIGEN_DIR/$STAGE_NAME"
    echo "config prepared at $CONFIG"
    exit 0
fi

(
    cd "$PIGEN_DIR"
    ./build-docker.sh -c "$CONFIG"
)

echo
echo "Images are in $PIGEN_DIR/deploy:"
ls -1 "$PIGEN_DIR/deploy"/*.img 2>/dev/null || ls -1 "$PIGEN_DIR/deploy"
