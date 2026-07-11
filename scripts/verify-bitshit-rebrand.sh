#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0
TMP="${TMPDIR:-/tmp}/bitshit-rebrand-check.$$"
trap 'rm -f "$TMP"' EXIT

check_file_absent() {
  local pattern="$1"
  local path="$2"
  local label="$3"
  if grep -nE "$pattern" "$path" >"$TMP" 2>/dev/null; then
    printf '[FAIL] %s\n' "$label" >&2
    cat "$TMP" >&2
    fail=1
  else
    printf '[ OK ] %s\n' "$label"
  fi
}

check_file_present() {
  local pattern="$1"
  local path="$2"
  local label="$3"
  if grep -qE "$pattern" "$path"; then
    printf '[ OK ] %s\n' "$label"
  else
    printf '[FAIL] %s\n' "$label" >&2
    fail=1
  fi
}

check_file_present '^# BitShit$' README.md 'README uses the BitShit product name'
check_file_present 'eyshoit-commits/bitshit.cpu' README.md 'README uses the current repository'
check_file_present 'BITSHIT_HOME' README.md 'README documents the new runtime home'
check_file_present 'BITSHIT_PORT' README.md 'README documents the new API port variable'
check_file_absent 'raw\.githubusercontent\.com/cluaiz|github\.com/cluaiz/cluaiz' README.md 'README has no legacy installation URLs'

check_file_present 'default-run = "bitshit"' cmd/Cargo.toml 'Cargo default binary is bitshit'
check_file_present 'name = "bitshit"' cmd/Cargo.toml 'Cargo binary target is bitshit'
check_file_present 'eyshoit-commits/bitshit.cpu' Cargo.toml 'Workspace metadata uses the current repository'

check_file_present 'eyshoit-commits/bitshit.cpu' install.sh 'POSIX installer uses the BitShit repository'
check_file_present 'eyshoit-commits/bitshit.cpu' install.ps1 'PowerShell installer uses the BitShit repository'
check_file_present 'auto\|cpu\|cuda\|rocm\|metal' install.sh 'POSIX installer exposes all supported backends'
check_file_present "ValidateSet\('auto','cpu','cuda'\)" install.ps1 'PowerShell installer exposes backend selection'
check_file_present 'cargo build --locked.*--bin bitshit' install.sh 'POSIX installer builds the public BitShit binary'
check_file_present "--bin', 'bitshit'" install.ps1 'PowerShell installer builds the public BitShit binary'

check_file_present 'migrate_legacy_data' install.sh 'POSIX installer includes legacy data migration'
check_file_present 'Migrate-LegacyData' install.ps1 'PowerShell installer includes legacy data migration'
check_file_present '\.migrated-from-cluaiz' install.sh 'POSIX migration is idempotent'
check_file_present '\.migrated-from-cluaiz' install.ps1 'PowerShell migration is idempotent'
check_file_present 'original remains untouched' install.sh 'POSIX migration preserves legacy data'
check_file_present 'original remains untouched' install.ps1 'PowerShell migration preserves legacy data'
check_file_absent 'raw\.githubusercontent\.com/cluaiz|github\.com/cluaiz/cluaiz' install.sh 'POSIX installer has no legacy remote registry'
check_file_absent 'raw\.githubusercontent\.com/cluaiz|github\.com/cluaiz/cluaiz' install.ps1 'PowerShell installer has no legacy remote registry'

if [[ $fail -ne 0 ]]; then
  printf '\nBitShit rebrand verification failed.\n' >&2
  exit 1
fi

printf '\nBitShit rebrand verification passed.\n'
