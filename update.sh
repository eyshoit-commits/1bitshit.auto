#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_STATE="${BITSHIT_HOME:-$HOME/.bitshit}/install.json"
BACKEND="${1:-}"

say() {
  printf '%s\n' "$*"
}

fail() {
  printf 'FEHLER: %s\n' "$*" >&2
  exit 1
}

# Git Bash, MSYS2 and Cygwin run on Windows. Use the native PowerShell
# updater there so the Windows installer and toolchain checks are used.
case "$(uname -s 2>/dev/null || true)" in
  MINGW*|MSYS*|CYGWIN*)
    command -v powershell.exe >/dev/null 2>&1 || fail "powershell.exe wurde nicht gefunden."
    WINDOWS_SCRIPT="$REPO_ROOT/update.ps1"
    if command -v cygpath >/dev/null 2>&1; then
      WINDOWS_SCRIPT="$(cygpath -w "$WINDOWS_SCRIPT")"
    fi
    say "Windows Git Bash erkannt. Starte PowerShell Update."
    if [[ -n "$BACKEND" ]]; then
      exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WINDOWS_SCRIPT" "$BACKEND"
    else
      exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$WINDOWS_SCRIPT"
    fi
    ;;
esac

command -v git >/dev/null 2>&1 || fail "git wurde nicht gefunden."

cd "$REPO_ROOT"

say "BitShit Update startet."
say "Hole den aktuellen Stand von GitHub."

git fetch origin --prune

CURRENT_BRANCH="$(git branch --show-current)"
if [[ -z "$CURRENT_BRANCH" ]]; then
  CURRENT_BRANCH="main"
  git switch main
fi

if [[ "$CURRENT_BRANCH" != "main" ]]; then
  say "Wechsle von Branch $CURRENT_BRANCH auf main."
  git switch main
fi

git reset --hard origin/main

if [[ -z "$BACKEND" && -f "$INSTALL_STATE" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    BACKEND="$(python3 - "$INSTALL_STATE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        value = json.load(handle).get("backend", "")
    if value in {"cpu", "cuda", "rocm", "metal", "auto"}:
        print(value)
except Exception:
    pass
PY
)"
  fi
fi

if [[ -z "$BACKEND" ]]; then
  BACKEND="cpu"
  say "Kein früheres Backend gefunden. Verwende CPU."
else
  say "Verwende Backend: $BACKEND"
fi

case "$BACKEND" in
  auto|cpu|cuda|rocm|metal) ;;
  *) fail "Ungültiges Backend: $BACKEND. Erlaubt sind auto, cpu, cuda, rocm oder metal." ;;
esac

[[ -f "$REPO_ROOT/install.sh" ]] || fail "install.sh fehlt im Repository."

say "Starte Aktualisierung und Neuinstallation."
bash "$REPO_ROOT/install.sh" --backend "$BACKEND" --yes

say "BitShit Update abgeschlossen."
