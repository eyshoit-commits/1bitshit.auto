#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKEND="${1:-cpu}"
PROFILE="release"
TARGET_BIN="bitshit"

say() { printf '%s\n' "$*"; }
fail() { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "$1 wurde nicht gefunden."; }

case "$BACKEND" in
  auto|cpu|cuda|rocm|metal) ;;
  *) fail "Ungültiges Backend: $BACKEND." ;;
esac

cd "$REPO_ROOT"
say "BitShit Test startet."
say "Verwende Backend: $BACKEND"

need git
need cargo
need rustc
need cmake

if [[ "$BACKEND" == "cuda" ]]; then
  need nvcc
  need nvidia-smi
elif [[ "$BACKEND" == "rocm" ]]; then
  need hipcc
  need rocminfo
elif [[ "$BACKEND" == "metal" ]]; then
  [[ "$(uname -s)" == "Darwin" ]] || fail "Metal ist nur unter macOS verfügbar."
  need xcrun
fi

export BITSHIT_HOME="${BITSHIT_HOME:-$HOME/.bitshit}"
export CLUAIZ_HOME="$BITSHIT_HOME"
export GGML_CUDA=OFF
export GGML_HIPBLAS=OFF
export GGML_METAL=OFF

case "$BACKEND" in
  cuda) export GGML_CUDA=ON ;;
  rocm) export GGML_HIPBLAS=ON ;;
  metal) export GGML_METAL=ON ;;
esac

say "Prüfe Cargo Workspace."
cargo metadata --no-deps --format-version 1 >/dev/null

if [[ ! -f Cargo.lock ]]; then
  say "Cargo.lock fehlt. Erzeuge Lockfile."
  cargo generate-lockfile
fi

say "Baue BitShit."
cargo build --locked --release -p cmd --bin "$TARGET_BIN"

BINARY="$REPO_ROOT/target/$PROFILE/$TARGET_BIN"
[[ -x "$BINARY" ]] || fail "Binary fehlt: $BINARY"

say "Prüfe Binary."
"$BINARY" --version

say "BitShit Test abgeschlossen."
