#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKEND=""
YES=0
NO_LEGACY_ALIAS=0
NO_MIGRATE=0

fail() { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend) [[ $# -ge 2 ]] || fail "--backend requires a value"; BACKEND="$2"; shift 2 ;;
    --yes|-y) YES=1; shift ;;
    --no-legacy-alias) NO_LEGACY_ALIAS=1; shift ;;
    --no-migrate) NO_MIGRATE=1; shift ;;
    --help|-h)
      printf '%s\n' 'Usage: ./install.sh [--backend auto|cpu|cuda|rocm] [--yes] [--no-legacy-alias] [--no-migrate]'
      exit 0
      ;;
    *) fail "Unknown option: $1" ;;
  esac
done

OS_NAME="$(uname -s 2>/dev/null || true)"
case "$OS_NAME" in
  Linux)
    SCRIPT="$REPO_ROOT/scripts/app-linux.sh"
    [[ -f "$SCRIPT" ]] || fail "Missing Linux installer: $SCRIPT"
    ARGS=()
    [[ -n "$BACKEND" ]] && ARGS+=(--backend "$BACKEND")
    [[ $YES -eq 1 ]] && ARGS+=(--yes)
    [[ $NO_LEGACY_ALIAS -eq 1 ]] && ARGS+=(--no-legacy-alias)
    [[ $NO_MIGRATE -eq 1 ]] && ARGS+=(--no-migrate)
    exec bash "$SCRIPT" "${ARGS[@]}"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    command -v powershell.exe >/dev/null 2>&1 || fail "powershell.exe wurde nicht gefunden."
    SCRIPT="$(cygpath -w "$REPO_ROOT/scripts/app-windows.ps1")"
    PS_ARGS=(-NoProfile -ExecutionPolicy Bypass -File "$SCRIPT")
    [[ -n "$BACKEND" ]] && PS_ARGS+=(-Backend "$BACKEND")
    [[ $YES -eq 1 ]] && PS_ARGS+=(-Yes)
    [[ $NO_LEGACY_ALIAS -eq 1 ]] && PS_ARGS+=(-NoLegacyAlias)
    [[ $NO_MIGRATE -eq 1 ]] && PS_ARGS+=(-NoMigrate)
    exec powershell.exe "${PS_ARGS[@]}"
    ;;
  *)
    fail "Nicht unterstuetztes Betriebssystem: ${OS_NAME:-unbekannt}"
    ;;
esac
