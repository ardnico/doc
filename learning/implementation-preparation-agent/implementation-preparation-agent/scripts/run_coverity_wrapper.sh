#!/usr/bin/env bash
set -euo pipefail

# Coverity wrapper template.
# This script intentionally does not assume your project build command.
# Edit BUILD_CMD and COVERITY_DIR for the target environment.

ROOT="${1:-$(pwd)}"
COVERITY_DIR="${COVERITY_DIR:-cov-int}"
BUILD_CMD="${BUILD_CMD:-make}"

cd "$ROOT"

echo "== coverity wrapper =="
echo "root: $ROOT"
echo "coverity dir: $COVERITY_DIR"
echo "build command: $BUILD_CMD"

if ! command -v cov-build >/dev/null 2>&1; then
  echo "ERROR: cov-build not found. Coverity was NOT EXECUTED." >&2
  exit 127
fi

if command -v cov-analyze >/dev/null 2>&1; then
  HAS_COV_ANALYZE=1
else
  HAS_COV_ANALYZE=0
fi

rm -rf "$COVERITY_DIR"

# shellcheck disable=SC2086
cov-build --dir "$COVERITY_DIR" $BUILD_CMD

if [ "$HAS_COV_ANALYZE" = "1" ]; then
  cov-analyze --dir "$COVERITY_DIR"
else
  echo "cov-analyze not found. Build capture completed only."
fi

echo "Coverity capture directory: $COVERITY_DIR"
echo "== done =="
