#!/usr/bin/env bash
set -u
for tool in git docker terraform kubectl helm; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '%-12s %s\n' "$tool" "$(command -v "$tool")"
  else
    printf '%-12s MISSING\n' "$tool"
  fi
done
