#!/usr/bin/env bash
# Version helpers shared by packaging, repository generation and CI.
#
# A release tag is `vX.Y.Z` (for example `v0.2.0`). It maps to the Debian
# version `X.Y.Z-1`: upstream version from the tag, Debian revision 1. A
# packaging-only fix bumps the revision, never the tag.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/version.sh from-tag [TAG]        Print the Debian version for TAG
                                           (default: exact tag on HEAD)
  scripts/version.sh from-git              Print TAG-1 for the tag on HEAD
  scripts/version.sh check GREATER THAN FILE
                                           Fail unless every Version in FILE
                                           is strictly lower than GREATER

Environment:
  WEATHER_PI_VERSION   Explicit Debian version; overrides tag derivation
EOF
}

die() {
    echo "version.sh: $*" >&2
    exit 1
}

debian_version_from_tag() {
    local tag="${1:-}"
    if [[ -z "$tag" ]]; then
        tag="$(git describe --tags --exact-match 2>/dev/null || true)"
    fi
    [[ -n "$tag" ]] || die "no tag supplied and HEAD is not tagged"

    local upstream="${tag#v}"
    if [[ ! "$upstream" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        die "tag '$tag' is not of the form vX.Y.Z"
    fi

    local revision="${DEBIAN_REVISION:-1}"
    [[ "$revision" =~ ^[0-9]+$ ]] || die "DEBIAN_REVISION must be numeric"

    printf '%s-%s\n' "$upstream" "$revision"
}

check_strictly_greater() {
    local candidate="$1"
    local packages_file="$2"

    [[ -n "$candidate" ]] || die "candidate version is empty"
    [[ -f "$packages_file" ]] || return 0

    local version
    local -a versions=()
    while IFS= read -r version; do
        versions+=("$version")
    done < <(awk '/^Version:[[:space:]]/ { print $2 }' "$packages_file" | sort -u)

    for version in "${versions[@]}"; do
        if ! dpkg --compare-versions "$candidate" gt "$version"; then
            die "candidate $candidate is not strictly greater than published $version"
        fi
    done
}

command="${1:-}"
case "$command" in
    from-tag)
        shift
        if [[ -n "${WEATHER_PI_VERSION:-}" ]]; then
            printf '%s\n' "$WEATHER_PI_VERSION"
        else
            debian_version_from_tag "${1:-}"
        fi
        ;;
    from-git)
        if [[ -n "${WEATHER_PI_VERSION:-}" ]]; then
            printf '%s\n' "$WEATHER_PI_VERSION"
        elif tag="$(git describe --tags --exact-match 2>/dev/null)" && [[ -n "$tag" ]]; then
            debian_version_from_tag "$tag"
        else
            # Untagged local build: follow the crate version so `mise run
            # package` works before a release tag exists.
            upstream="$(awk -F'"' '/^version[[:space:]]*=/ { print $2; exit }' Cargo.toml)"
            [[ -n "$upstream" ]] || die "cannot read a version from Cargo.toml"
            printf '%s-%s\n' "$upstream" "${DEBIAN_REVISION:-1}"
        fi
        ;;
    check)
        shift
        [[ $# -eq 2 ]] || die "check requires GREATER and FILE"
        check_strictly_greater "$1" "$2"
        ;;
    -h | --help | help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
