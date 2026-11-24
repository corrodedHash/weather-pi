#!/usr/bin/env bash
# Compatibility wrapper. Builds are driven by mise; see mise.toml and README.md.
set -euo pipefail
exec mise run build:armv6
