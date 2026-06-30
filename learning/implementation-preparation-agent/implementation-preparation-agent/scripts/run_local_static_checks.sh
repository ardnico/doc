#!/usr/bin/env bash
set -euo pipefail

# Local static check helper.
# Adjust commands for the target project.

ROOT="${1:-$(pwd)}"
cd "$ROOT"

echo "== local static checks =="
echo "root: $ROOT"

if command -v git >/dev/null 2>&1; then
  echo "-- changed files --"
  git status --short || true
fi

if command -v make >/dev/null 2>&1 && [ -f Makefile ]; then
  echo "-- make dry target candidates --"
  echo "Project has Makefile. Add project-specific build command here."
fi

if command -v clang-format >/dev/null 2>&1; then
  echo "-- clang-format availability --"
  clang-format --version
else
  echo "clang-format: NOT FOUND"
fi

if command -v cppcheck >/dev/null 2>&1; then
  echo "-- cppcheck changed C files --"
  FILES=$(git diff --name-only -- '*.c' '*.h' 2>/dev/null || true)
  if [ -n "$FILES" ]; then
    # shellcheck disable=SC2086
    cppcheck --enable=warning,style,performance,portability --inline-suppr $FILES
  else
    echo "No changed C/H files detected."
  fi
else
  echo "cppcheck: NOT FOUND"
fi

echo "== done =="
