#!/usr/bin/env bash
set -Eeuo pipefail

BACKEND="${1:-}"
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

fail() { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }

case "$(uname -s 2>/dev/null || true)" in
  MINGW*|MSYS*|CYGWIN*)
    command -v powershell.exe >/dev/null 2>&1 || fail "powershell.exe wurde nicht gefunden."
    PS_SCRIPT="$(cygpath -w "$REPO_ROOT/bootstrap-windows.ps1")"
    if [[ -n "$BACKEND" ]]; then
      exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" "$BACKEND"
    else
      exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT"
    fi
    ;;
  Linux*)
    if [[ -n "$BACKEND" ]]; then
      exec bash "$REPO_ROOT/bootstrap-linux.sh" "$BACKEND"
    else
      exec bash "$REPO_ROOT/bootstrap-linux.sh"
    fi
    ;;
  *)
    fail "Nicht unterstuetztes Betriebssystem."
    ;;
esac
