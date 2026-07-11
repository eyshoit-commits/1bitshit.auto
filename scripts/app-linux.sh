#!/usr/bin/env bash
set -Eeuo pipefail

PRODUCT="bitshit"
REPO="https://github.com/eyshoit-commits/1bitshit.auto.git"
INSTALL_DIR="${BITSHIT_INSTALL_DIR:-$HOME/.local/bin}"
DATA_DIR="${BITSHIT_HOME:-$HOME/.bitshit}"
INTERIM_DATA_DIR="${BITSHIT_INTERIM_HOME:-$HOME/.1bitshit}"
LEGACY_DATA_DIR="${CLUAIZ_LEGACY_HOME:-$HOME/.cluaiz}"
SOURCE_DIR="${BITSHIT_SOURCE_DIR:-$DATA_DIR/source}"
PROFILE="${BITSHIT_PROFILE:-release}"
TARGET_BIN="bitshit"
LEGACY_BIN="cluaiz"

log() { printf '\033[1;36m[bitshit]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[bitshit]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[bitshit]\033[0m %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

[[ "$(uname -s)" == "Linux" ]] || die "scripts/app-linux.sh supports Linux only."

BACKEND=""
ASSUME_YES=0
LEGACY_ALIAS=1
MIGRATE_LEGACY=1
LAUNCH_AFTER_INSTALL=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend) [[ $# -ge 2 ]] || die "--backend requires a value"; BACKEND="$2"; shift 2 ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --no-legacy-alias) LEGACY_ALIAS=0; shift ;;
    --no-migrate) MIGRATE_LEGACY=0; shift ;;
    --no-launch) LAUNCH_AFTER_INSTALL=0; shift ;;
    *) die "Unknown option: $1" ;;
  esac
done

need git
need cargo
need rustc
need cmake
need make
need python3

if command -v c++ >/dev/null 2>&1; then CXX_BIN="$(command -v c++)"
elif command -v clang++ >/dev/null 2>&1; then CXX_BIN="$(command -v clang++)"
elif command -v g++ >/dev/null 2>&1; then CXX_BIN="$(command -v g++)"
else die "Missing C++ compiler (c++, clang++, or g++)"
fi

has_cuda() { command -v nvcc >/dev/null 2>&1 && { command -v nvidia-smi >/dev/null 2>&1 || [[ -e /proc/driver/nvidia/version ]]; }; }
has_rocm() { command -v hipcc >/dev/null 2>&1 && command -v rocminfo >/dev/null 2>&1; }
auto_backend() { if has_cuda; then echo cuda; elif has_rocm; then echo rocm; else echo cpu; fi; }

if [[ -z "$BACKEND" ]]; then
  DETECTED="$(auto_backend)"
  if [[ $ASSUME_YES -eq 1 || ! -t 0 ]]; then BACKEND="$DETECTED"
  else
    printf '\nDetected backend: %s\n' "$DETECTED"
    printf 'Select backend:\n  1) Auto (%s)\n  2) CPU only\n  3) NVIDIA CUDA\n  4) AMD ROCm\n' "$DETECTED"
    read -r -p '> ' answer
    case "$answer" in 1|"") BACKEND="$DETECTED" ;; 2) BACKEND=cpu ;; 3) BACKEND=cuda ;; 4) BACKEND=rocm ;; *) die "Invalid selection" ;; esac
  fi
elif [[ "$BACKEND" == auto ]]; then BACKEND="$(auto_backend)"
fi

case "$BACKEND" in
  cpu) ;;
  cuda) has_cuda || die "CUDA selected but NVIDIA driver and nvcc are required." ;;
  rocm) has_rocm || die "ROCm selected but hipcc and rocminfo are required." ;;
  *) die "Invalid Linux backend: $BACKEND" ;;
esac

copy_missing_tree() {
  local source="$1"
  local marker_name="$2"
  local marker="$DATA_DIR/$marker_name"

  [[ "$source" != "$DATA_DIR" ]] || return 0
  [[ -d "$source" ]] || return 0
  [[ ! -e "$marker" ]] || return 0

  log "Migrating missing data from $source to $DATA_DIR"
  mkdir -p "$DATA_DIR"
  cp -a -n "$source"/. "$DATA_DIR"/ 2>/dev/null || true
  printf 'source=%s\ntarget=%s\nmigrated_at=%s\nmode=copy-missing\n' \
    "$source" "$DATA_DIR" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$marker"
}

if [[ $MIGRATE_LEGACY -eq 1 ]]; then
  # The short-lived .1bitshit path is newer than .cluaiz and therefore gets
  # first chance to populate missing files. Existing canonical files always win.
  copy_missing_tree "$INTERIM_DATA_DIR" ".migrated-from-1bitshit"
  copy_missing_tree "$LEGACY_DATA_DIR" ".migrated-from-cluaiz"
fi

mkdir -p "$DATA_DIR" "$INSTALL_DIR"
if [[ -d "$SOURCE_DIR/.git" ]]; then
  log "Updating source checkout"
  git -C "$SOURCE_DIR" remote set-url origin "$REPO"
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

# BITSHIT_HOME is canonical. CLUAIZ_HOME remains a compatibility variable for
# internal crates that have not yet been renamed, but points to the same data.
export BITSHIT_HOME="$DATA_DIR"
export BITSHIT_INTERIM_HOME="$INTERIM_DATA_DIR"
export CLUAIZ_HOME="$DATA_DIR"
export CLUAIZ_LEGACY_HOME="$LEGACY_DATA_DIR"
export BITSHIT_MODELS_DIR="$SOURCE_DIR/models/dl"
export CXX="$CXX_BIN"
export GGML_CUDA=OFF GGML_HIPBLAS=OFF GGML_METAL=OFF
[[ "$BACKEND" == cuda ]] && export GGML_CUDA=ON
[[ "$BACKEND" == rocm ]] && export GGML_HIPBLAS=ON

SOURCE_MIGRATIONS=(
  repair-openmp-duplicates.py
  rebrand-main-cli.py
  fix-public-branding.py
  fix-model-runtime.py
  fix-registry-cache.py
  fix-model-hub-load.py
)

log "Applying complete BitShit source migration pipeline"
(
  cd "$SOURCE_DIR"
  for migration in "${SOURCE_MIGRATIONS[@]}"; do
    [[ -f "scripts/$migration" ]] || die "Missing source migration: scripts/$migration"
    python3 "scripts/$migration"
  done
)

log "Building backend=$BACKEND profile=$PROFILE"
(
  cd "$SOURCE_DIR"
  [[ -f Cargo.lock ]] || cargo generate-lockfile
  cargo build --locked --profile "$PROFILE" -p cmd --bin "$TARGET_BIN"
)

TARGET_PROFILE_DIR="$PROFILE"; [[ "$PROFILE" == dev ]] && TARGET_PROFILE_DIR=debug
BUILT="$SOURCE_DIR/target/$TARGET_PROFILE_DIR/$TARGET_BIN"
[[ -x "$BUILT" ]] || die "Build completed without producing $BUILT"

log "Synchronizing local engine and kernel artifacts"
(
  cd "$SOURCE_DIR"
  "$BUILT" dev-sync all
)

ENGINE_EXT="so"
ENGINE_PATH="$DATA_DIR/engine/cluaiz-engine.$ENGINE_EXT"
KERNEL_PATH="$DATA_DIR/engine/cluaiz-llama.$ENGINE_EXT"
[[ -f "$ENGINE_PATH" ]] || die "Runtime synchronization did not produce $ENGINE_PATH"
[[ -f "$KERNEL_PATH" ]] || die "Runtime synchronization did not produce $KERNEL_PATH"

install -m 0755 "$BUILT" "$INSTALL_DIR/$TARGET_BIN"
[[ $LEGACY_ALIAS -eq 1 ]] && ln -sfn "$TARGET_BIN" "$INSTALL_DIR/$LEGACY_BIN"

cat > "$DATA_DIR/install.json" <<EOF
{"product":"bitshit","platform":"linux","backend":"$BACKEND","profile":"$PROFILE","binary":"$INSTALL_DIR/$TARGET_BIN","source":"$SOURCE_DIR","runtime":"$DATA_DIR","interim_source":"$INTERIM_DATA_DIR","legacy_source":"$LEGACY_DATA_DIR","migration_mode":"copy-missing","models":"$SOURCE_DIR/models/dl"}
EOF

log "Installed $INSTALL_DIR/$TARGET_BIN"
log "Runtime synchronized to $DATA_DIR"
log "Models stored in $SOURCE_DIR/models/dl"
if [[ $LAUNCH_AFTER_INSTALL -eq 1 ]]; then
  "$INSTALL_DIR/$TARGET_BIN" --version || true
else
  log "Launch skipped by --no-launch"
fi