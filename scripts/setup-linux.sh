#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND=""
PASS_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend) BACKEND="$2"; PASS_ARGS+=(--backend "$2"); shift 2 ;;
    --yes|-y|--no-legacy-alias|--no-migrate|--no-launch) PASS_ARGS+=("$1"); shift ;;
    *) printf 'FEHLER: Unbekannte Option: %s\n' "$1" >&2; exit 1 ;;
  esac
done

[[ "$(uname -s)" == "Linux" ]] || { echo 'FEHLER: setup-linux.sh ist nur fuer Linux.' >&2; exit 1; }

if [[ $EUID -eq 0 ]]; then
  SUDO=""
elif command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  echo 'FEHLER: sudo fehlt. Starte als root oder installiere sudo.' >&2
  exit 1
fi

missing=0
for cmd in git cargo rustc cmake make; do
  command -v "$cmd" >/dev/null 2>&1 || missing=1
done
command -v c++ >/dev/null 2>&1 || command -v clang++ >/dev/null 2>&1 || command -v g++ >/dev/null 2>&1 || missing=1

if [[ $missing -eq 1 ]]; then
  echo '[bitshit] Installiere Linux Build-Umgebung.'
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
    echo 'FEHLER: Nicht unterstuetzter Paketmanager. Unterstuetzt: apt, dnf, pacman, apk.' >&2
    exit 1
  fi
fi

exec bash "$REPO_ROOT/scripts/app-linux.sh" "${PASS_ARGS[@]}"
