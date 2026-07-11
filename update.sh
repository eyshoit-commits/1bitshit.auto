#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_STATE="${BITSHIT_HOME:-$HOME/.bitshit}/install.json"
BACKEND=""
NO_LEGACY_ALIAS=0
NO_MIGRATE=0
NO_LAUNCH=0

say() { printf '%s\n' "$*"; }
fail() { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: ./update.sh [auto|cpu|cuda|rocm] [--backend VALUE]
                   [--no-legacy-alias] [--no-migrate] [--no-launch]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend)
      [[ $# -ge 2 ]] || fail "--backend requires a value"
      BACKEND="$2"
      shift 2
      ;;
    --backend=*) BACKEND="${1#*=}"; shift ;;
    auto|cpu|cuda|rocm)
      [[ -z "$BACKEND" ]] || fail "Backend was specified more than once."
      BACKEND="$1"
      shift
      ;;
    --no-legacy-alias) NO_LEGACY_ALIAS=1; shift ;;
    --no-migrate) NO_MIGRATE=1; shift ;;
    --no-launch) NO_LAUNCH=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) fail "Unknown option: $1" ;;
  esac
done

case "$(uname -s 2>/dev/null || true)" in
  MINGW*|MSYS*|CYGWIN*)
    command -v powershell.exe >/dev/null 2>&1 || fail "powershell.exe wurde nicht gefunden."
    WINDOWS_SCRIPT="$REPO_ROOT/update.ps1"
    if command -v cygpath >/dev/null 2>&1; then
      WINDOWS_SCRIPT="$(cygpath -w "$WINDOWS_SCRIPT")"
    fi
    PS_ARGS=(-NoProfile -ExecutionPolicy Bypass -File "$WINDOWS_SCRIPT")
    [[ -n "$BACKEND" ]] && PS_ARGS+=(--backend "$BACKEND")
    [[ $NO_LEGACY_ALIAS -eq 1 ]] && PS_ARGS+=(--no-legacy-alias)
    [[ $NO_MIGRATE -eq 1 ]] && PS_ARGS+=(--no-migrate)
    [[ $NO_LAUNCH -eq 1 ]] && PS_ARGS+=(--no-launch)
    say "Windows Git Bash erkannt. Starte PowerShell Update."
    exec powershell.exe "${PS_ARGS[@]}"
    ;;
esac

command -v git >/dev/null 2>&1 || fail "git wurde nicht gefunden."
cd "$REPO_ROOT"

say "BitShit Update startet."
say "Hole den aktuellen Stand von GitHub."
git fetch origin --prune

CURRENT_BRANCH="$(git branch --show-current)"
if [[ -z "$CURRENT_BRANCH" ]]; then
  git switch main
elif [[ "$CURRENT_BRANCH" != "main" ]]; then
  say "Wechsle von Branch $CURRENT_BRANCH auf main."
  git switch main
fi

git reset --hard origin/main

if [[ -z "$BACKEND" && -f "$INSTALL_STATE" ]] && command -v python3 >/dev/null 2>&1; then
  BACKEND="$(python3 - "$INSTALL_STATE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        value = json.load(handle).get("backend", "")
    if value in {"cpu", "cuda", "rocm", "auto"}:
        print(value)
except Exception:
    pass
PY
)"
fi

if [[ -z "$BACKEND" ]]; then
  BACKEND="auto"
  say "Kein früheres Backend gefunden. Verwende automatische Erkennung."
else
  say "Verwende Backend: $BACKEND"
fi

case "$BACKEND" in
  auto|cpu|cuda|rocm) ;;
  *) fail "Ungültiges Backend: $BACKEND. Erlaubt sind auto, cpu, cuda oder rocm." ;;
esac

[[ -f "$REPO_ROOT/install.sh" ]] || fail "install.sh fehlt im Repository."

INSTALL_ARGS=(--backend "$BACKEND" --yes)
[[ $NO_LEGACY_ALIAS -eq 1 ]] && INSTALL_ARGS+=(--no-legacy-alias)
[[ $NO_MIGRATE -eq 1 ]] && INSTALL_ARGS+=(--no-migrate)
[[ $NO_LAUNCH -eq 1 ]] && INSTALL_ARGS+=(--no-launch)

say "Starte Aktualisierung und Neuinstallation."
bash "$REPO_ROOT/install.sh" "${INSTALL_ARGS[@]}"
say "BitShit Update abgeschlossen."
