#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# This audit deliberately distinguishes public product identity from internal
# compatibility symbols such as crate names, FFI modules and serialized keys.
# Public-facing Cluaiz references fail the build; internal references are only
# counted so they can be migrated in controlled blocks.

fail=0

public_checks=(
  'cmd/src/main.rs:command\(name = "cluaiz"'
  'cmd/src/main.rs:Cluaiz-OS'
  'cmd/src/main.rs:run the global .cluaiz. command'
  'cmd/src/main.rs:Starting cluaiz API Daemon'
  'cmd/src/main.rs:\[Cluaiz\]'
  'cmd/src/main.rs:cluaiz_Core\.log'
  'cmd/src/main.rs:std::env::var\("cluaiz_PORT"\)'
  'cmd/src/main.rs:std::env::set_var\("cluaiz_HOME"'
  'cmd/src/main.rs:Open the cluaiz Main Menu'
  'cmd/src/main.rs:Setup Cluaiz Node Profile'
)

for entry in "${public_checks[@]}"; do
  path="${entry%%:*}"
  pattern="${entry#*:}"
  if grep -nE "$pattern" "$path"; then
    printf '[PUBLIC-BRAND-FAIL] %s still exposes a legacy Cluaiz identity\n' "$path" >&2
    fail=1
  fi
done

# Positive assertions matter too. Merely deleting every brand string would make
# the audit green while producing a nameless binary, a very human form of success.
required_public_identity=(
  'cmd/src/main.rs:command\(name = "bitshit"'
  'cmd/src/main.rs:BitShit: Sovereign Neural Kernel'
  'cmd/src/main.rs:run the global .bitshit. command'
  'cmd/src/main.rs:Starting BitShit API daemon'
  'cmd/src/main.rs:\[BitShit\]'
  'cmd/src/main.rs:bitshit-core\.log'
  'cmd/src/main.rs:std::env::var\("BITSHIT_PORT"\)'
  'cmd/src/main.rs:std::env::set_var\("BITSHIT_HOME"'
)

for entry in "${required_public_identity[@]}"; do
  path="${entry%%:*}"
  pattern="${entry#*:}"
  if ! grep -qE "$pattern" "$path"; then
    printf '[PUBLIC-BRAND-FAIL] %s is missing required BitShit identity: %s\n' "$path" "$pattern" >&2
    fail=1
  fi
done

# Legacy fallbacks are allowed only when the new BitShit variable is present in
# the same source file. This prevents compatibility code becoming the primary API.
if grep -q 'cluaiz_PORT\|CLUAIZ_PORT' cmd/src/main.rs && ! grep -q 'BITSHIT_PORT' cmd/src/main.rs; then
  printf '[PUBLIC-BRAND-FAIL] legacy port variables exist without BITSHIT_PORT primary support\n' >&2
  fail=1
fi

if grep -q 'cluaiz_HOME\|CLUAIZ_HOME' cmd/src/main.rs && ! grep -q 'BITSHIT_HOME' cmd/src/main.rs; then
  printf '[PUBLIC-BRAND-FAIL] legacy home variables exist without BITSHIT_HOME primary support\n' >&2
  fail=1
fi

python3 -m py_compile scripts/rebrand-main-cli.py
if ! python3 scripts/rebrand-main-cli.py --check; then
  printf '[PUBLIC-BRAND-FAIL] deterministic CLI transformer reports an incomplete migration\n' >&2
  fail=1
fi

internal_count="$({ grep -RInE --exclude-dir=.git --exclude='Cargo.lock' \
  'cluaiz_shared|cluaiz_api|cluaizHealthChecker|cluaiz[_-](engine|runtime|ffi|shared)' \
  cmd inference-engine inference-cel 2>/dev/null || true; } | wc -l | tr -d ' ')"

printf 'Controlled internal compatibility references: %s\n' "$internal_count"

if [[ $fail -ne 0 ]]; then
  printf '\nPublic BitShit brand audit failed. Internal compatibility names are not the cause.\n' >&2
  exit 1
fi

printf '\nPublic BitShit brand audit passed.\n'
