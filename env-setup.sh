#!/usr/bin/env bash
set -Eeuo pipefail

BACKEND="${1:-}"
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

say() { printf '%s\n' "$*"; }
fail() { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }

# Git Bash, MSYS2 and Cygwin run bash on Windows. Delegate to the native
# PowerShell bootstrapper so both entry points work from the same checkout.
case "$(uname -s 2>/dev/null || true)" in
  MINGW*|MSYS*|CYGWIN*)
    command -v powershell.exe >/dev/null 2>&1 || fail "powershell.exe wurde nicht gefunden."
    PS_SCRIPT="$(cygpath -w "$REPO_ROOT/env-setup.ps1")"
    say "Windows Git Bash erkannt. Starte PowerShell Umgebungs-Setup."
    if [[ -n "$BACKEND" ]]; then
      exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT" "$BACKEND"
    else
      exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS_SCRIPT"
    fi
    ;;
esac

if [[ $EUID -eq 0 ]]; then
  SUDO=""
elif command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  fail "sudo fehlt. Starte das Skript als root oder installiere sudo."
fi

say "BitShit Linux Umgebungs-Setup startet."

if command -v apt-get >/dev/null 2>&1; then
  $SUDO apt-get update
  $SUDO apt-get install -y --no-install-recommends git ca-certificates build-essential cmake clang libclang-dev pkg-config python3 cargo rustc
elif command -v dnf >/dev/null 2>&1; then
  $SUDO dnf install -y git ca-certificates gcc gcc-c++ make cmake clang clang-devel pkgconf-pkg-config python3 cargo rust
elif command -v pacman >/dev/null 2>&1; then
  $SUDO pacman -Sy --needed --noconfirm git ca-certificates base-devel cmake clang pkgconf python rust
elif command -v apk >/dev/null 2>&1; then
  $SUDO apk add --no-cache git ca-certificates build-base cmake clang clang-dev pkgconf python3 cargo rust
else
  fail "Nicht unterstuetzter Paketmanager. Unterstuetzt: apt, dnf, pacman, apk."
fi

for cmd in git cargo rustc cmake; do
  command -v "$cmd" >/dev/null 2>&1 || fail "$cmd wurde nach dem Setup nicht gefunden."
done

say "Umgebung bereit."
cd "$REPO_ROOT"
if [[ -n "$BACKEND" ]]; then
  bash "$REPO_ROOT/install.sh" --backend "$BACKEND"
else
  bash "$REPO_ROOT/install.sh"
fi
