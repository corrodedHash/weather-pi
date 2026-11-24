#!/usr/bin/env bash
# Cut a release locally: validate the tag, build and sign the packages, and
# generate the repository tree. Publication is performed by CI (see
# .github/workflows/release.yml and docs/releasing.md).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

die() {
    echo "release.sh: $*" >&2
    exit 1
}

[[ -z "$(git status --porcelain)" ]] || die "working tree is dirty; commit or stash first"

tag="$(git describe --tags --exact-match 2>/dev/null || true)"
[[ -n "$tag" ]] || die "HEAD is not tagged; create a vX.Y.Z tag first"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "tag '$tag' is not of the form vX.Y.Z"

version="$(WEATHER_PI_VERSION='' scripts/version.sh from-tag "$tag")"
echo "==> Releasing $tag as Debian version $version"

if [[ -n "${WEATHER_PI_PUBLISHED_PACKAGES:-}" ]]; then
    scripts/version.sh check "$version" "$WEATHER_PI_PUBLISHED_PACKAGES"
else
    echo "==> WEATHER_PI_PUBLISHED_PACKAGES is unset; skipping the published-version check"
fi

scripts/build-packages.sh

scripts/apt-repo.sh

(cd dist && sha256sum ./*.deb >SHA256SUMS)

echo
echo "Release artifacts:"
find dist target/repo -maxdepth 4 -type f | sort
