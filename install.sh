#!/usr/bin/env bash
set -Eeuo pipefail

PRODUCT="bitshit"
REPO="https://github.com/eyshoit-commits/1bitshit.auto.git"
INSTALL_DIR="${BITSHIT_INSTALL_DIR:-$HOME/.local/bin}"
DATA_DIR="${BITSHIT_HOME:-$HOME/.bitshit}"
LEGACY_DATA_DIR="${CLUAIZ_HOME:-$HOME/.cluaiz}"
SOURCE_DIR="${BITSHIT_SOURCE_DIR:-$DATA_DIR/source}"
PROFILE="${BITSHIT_PROFILE:-release}"
TARGET_BIN="bitshit"
LEGACY_BIN="cluaiz"
MIGRATION_MARKER="$DATA_DIR/.migrated-from-cluaiz"

log() { printf '\033[1;36m[bitshit]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[bitshit]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[bitshit]\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

usage() {
  cat <<'EOF'
BitShit unified installer

Usage: ./install.sh [--backend auto|cpu|cuda|rocm|metal] [--yes] [--no-legacy-alias] [--no-migrate]

Environment:
  BITSHIT_INSTALL_DIR  Binary destination (default: ~/.local/bin)
  BITSHIT_HOME         Runtime data directory (default: ~/.bitshit)
  BITSHIT_SOURCE_DIR   Source checkout (default: ~/.bitshit/source)
  BITSHIT_PROFILE      Cargo profile (default: release)
  CLUAIZ_HOME          Legacy data source for one-time migration (default: ~/.cluaiz)
EOF
}

profile_target_dir() {
  case "$1" in
    dev) echo debug ;;
    release) echo release ;;
    *) echo "$1" ;;
  esac
}

BACKEND=""
ASSUME_YES=0
LEGACY_ALIAS=1
MIGRATE_LEGACY=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend)
      [[ $# -ge 2 && -n "${2:-}" ]] || die "--backend requires a value"
      BACKEND="$2"
      shift 2
      ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --no-legacy-alias) LEGACY_ALIAS=0; shift ;;
    --no-migrate) MIGRATE_LEGACY=0; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

case "${BACKEND:-auto}" in auto|cpu|cuda|rocm|metal) ;; *) die "Invalid backend: $BACKEND" ;; esac

need git
need cargo
need rustc
need cmake
need make

if command -v c++ >/dev/null 2>&1; then
  CXX_BIN="$(command -v c++)"
elif command -v clang++ >/dev/null 2>&1; then
  CXX_BIN="$(command -v clang++)"
elif command -v g++ >/dev/null 2>&1; then
  CXX_BIN="$(command -v g++)"
else
  die "Missing C++ compiler (c++, clang++, or g++)"
fi

has_cuda() {
  command -v nvcc >/dev/null 2>&1 &&
    { command -v nvidia-smi >/dev/null 2>&1 || [[ -e /proc/driver/nvidia/version ]]; }
}
has_rocm() { command -v hipcc >/dev/null 2>&1 && command -v rocminfo >/dev/null 2>&1; }
has_metal() {
  [[ "$(uname -s)" == "Darwin" ]] &&
    command -v xcrun >/dev/null 2>&1 &&
    xcrun --find clang >/dev/null 2>&1
}

auto_backend() {
  if has_cuda; then echo cuda
  elif has_rocm; then echo rocm
  elif has_metal; then echo metal
  else echo cpu
  fi
}

migrate_legacy_data() {
  [[ $MIGRATE_LEGACY -eq 1 ]] || return 0
  [[ "$LEGACY_DATA_DIR" != "$DATA_DIR" ]] || return 0
  [[ -d "$LEGACY_DATA_DIR" ]] || return 0
  [[ ! -e "$MIGRATION_MARKER" ]] || return 0

  log "Migrating legacy data from $LEGACY_DATA_DIR"
  mkdir -p "$DATA_DIR"

  # Merge without deleting or modifying the legacy tree. Existing BitShit files win.
  while IFS= read -r -d '' entry; do
    relative="${entry#"$LEGACY_DATA_DIR"/}"
    target="$DATA_DIR/$relative"

    if [[ -L "$entry" ]]; then
      if [[ ! -e "$target" && ! -L "$target" ]]; then
        mkdir -p "$(dirname "$target")"
        cp -a "$entry" "$target"
      fi
    elif [[ -d "$entry" ]]; then
      mkdir -p "$target"
    elif [[ ! -e "$target" ]]; then
      mkdir -p "$(dirname "$target")"
      cp -p "$entry" "$target"
    fi
  done < <(find "$LEGACY_DATA_DIR" -mindepth 1 -print0)

  printf 'source=%s\nmigrated_at=%s\n' "$LEGACY_DATA_DIR" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$MIGRATION_MARKER"
  log "Legacy data copied; original remains untouched"
}

if [[ -z "$BACKEND" ]]; then
  DETECTED="$(auto_backend)"
  if [[ $ASSUME_YES -eq 1 || ! -t 0 ]]; then
    BACKEND="$DETECTED"
  else
    printf '\nDetected backend: %s\n' "$DETECTED"
    printf 'Select backend:\n  1) Auto (%s)\n  2) CPU only\n  3) NVIDIA CUDA\n  4) AMD ROCm\n  5) Apple Metal\n' "$DETECTED"
    read -r -p '> ' answer
    case "$answer" in
      1|"") BACKEND="$DETECTED" ;;
      2) BACKEND=cpu ;;
      3) BACKEND=cuda ;;
      4) BACKEND=rocm ;;
      5) BACKEND=metal ;;
      *) die "Invalid selection" ;;
    esac
  fi
elif [[ "$BACKEND" == auto ]]; then
  BACKEND="$(auto_backend)"
fi

case "$BACKEND" in
  cuda) has_cuda || die "CUDA selected but both the CUDA toolkit (nvcc) and NVIDIA driver/device are required." ;;
  rocm) has_rocm || die "ROCm selected but both hipcc and rocminfo are required." ;;
  metal) has_metal || die "Metal selected but macOS with the Xcode command-line tools is required." ;;
esac

migrate_legacy_data
mkdir -p "$DATA_DIR" "$INSTALL_DIR"
if [[ -d "$SOURCE_DIR/.git" ]]; then
  log "Updating source checkout"
  git -C "$SOURCE_DIR" fetch origin --prune
  git -C "$SOURCE_DIR" checkout -q main
  git -C "$SOURCE_DIR" reset --hard origin/main
else
  rm -rf "$SOURCE_DIR"
  log "Cloning BitShit"
  git clone --recurse-submodules "$REPO" "$SOURCE_DIR"
fi

git -C "$SOURCE_DIR" submodule sync --recursive
git -C "$SOURCE_DIR" submodule update --init --recursive

export BITSHIT_HOME="$DATA_DIR"
export CLUAIZ_HOME="$DATA_DIR" # temporary internal compatibility during crate migration
export CXX="$CXX_BIN"
unset GGML_CUDA GGML_HIPBLAS GGML_METAL
case "$BACKEND" in
  cpu) export GGML_CUDA=OFF GGML_HIPBLAS=OFF GGML_METAL=OFF ;;
  cuda) export GGML_CUDA=ON GGML_HIPBLAS=OFF GGML_METAL=OFF ;;
  rocm) export GGML_CUDA=OFF GGML_HIPBLAS=ON GGML_METAL=OFF ;;
  metal) export GGML_CUDA=OFF GGML_HIPBLAS=OFF GGML_METAL=ON ;;
esac

log "Building backend=$BACKEND profile=$PROFILE"
(
  cd "$SOURCE_DIR"
  if [[ -f Cargo.lock ]]; then
    cargo build --locked --profile "$PROFILE" -p cmd --bin "$TARGET_BIN"
  else
    warn "Cargo.lock is missing; generating a lockfile before the build"
    cargo generate-lockfile
    cargo build --profile "$PROFILE" -p cmd --bin "$TARGET_BIN"
  fi
)

TARGET_PROFILE_DIR="$(profile_target_dir "$PROFILE")"
BUILT="$SOURCE_DIR/target/$TARGET_PROFILE_DIR/$TARGET_BIN"
[[ -x "$BUILT" ]] || die "Build completed without producing $BUILT"
install -m 0755 "$BUILT" "$INSTALL_DIR/$TARGET_BIN"

if [[ $LEGACY_ALIAS -eq 1 ]]; then
  ln -sfn "$TARGET_BIN" "$INSTALL_DIR/$LEGACY_BIN"
fi

cat > "$DATA_DIR/install.json" <<EOF
{
  "product": "bitshit",
  "backend": "$BACKEND",
  "profile": "$PROFILE",
  "binary": "$INSTALL_DIR/$TARGET_BIN",
  "source": "$SOURCE_DIR",
  "legacy_data_source": "$LEGACY_DATA_DIR"
}
EOF

log "Installed $INSTALL_DIR/$TARGET_BIN"
log "Runtime data: $DATA_DIR"
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  warn "$INSTALL_DIR is not in PATH. Add: export PATH=\"$INSTALL_DIR:\$PATH\""
fi
"$INSTALL_DIR/$TARGET_BIN" --version || true
