#!/usr/bin/env bash
set -Eeuo pipefail

format="${1:-text}"

os="$(uname -s 2>/dev/null || echo unknown)"
arch="$(uname -m 2>/dev/null || echo unknown)"
cpu="unknown"
ram_mb=0
gpu_vendor="none"
gpu_name="none"
nvidia_driver=false
cuda_toolkit=false
rocm_runtime=false
metal_available=false
selected_backend="cpu"

if command -v lscpu >/dev/null 2>&1; then
  cpu="$(lscpu | awk -F: '/Model name/ {sub(/^[ \t]+/, "", $2); print $2; exit}')"
elif [[ -r /proc/cpuinfo ]]; then
  cpu="$(awk -F: '/model name/ {sub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo)"
fi

if [[ -r /proc/meminfo ]]; then
  ram_mb="$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 ))"
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  if gpu_line="$(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -n1)" && [[ -n "$gpu_line" ]]; then
    gpu_vendor="nvidia"
    gpu_name="${gpu_line%%,*}"
    nvidia_driver=true
  fi
fi

if command -v nvcc >/dev/null 2>&1; then
  cuda_toolkit=true
fi

if [[ "$gpu_vendor" == "none" ]] && command -v rocminfo >/dev/null 2>&1; then
  if rocminfo >/dev/null 2>&1; then
    gpu_vendor="amd"
    gpu_name="AMD ROCm device"
    rocm_runtime=true
  fi
fi

if command -v hipcc >/dev/null 2>&1 && command -v rocminfo >/dev/null 2>&1; then
  if rocminfo >/dev/null 2>&1; then
    rocm_runtime=true
  fi
fi

if [[ "$os" == "Darwin" ]] && command -v xcrun >/dev/null 2>&1; then
  if xcrun --find metal >/dev/null 2>&1 || xcrun --find clang >/dev/null 2>&1; then
    metal_available=true
    gpu_vendor="apple"
    gpu_name="Apple Metal"
  fi
fi

if [[ "$nvidia_driver" == true && "$cuda_toolkit" == true ]]; then
  selected_backend="cuda"
elif [[ "$rocm_runtime" == true ]]; then
  selected_backend="rocm"
elif [[ "$metal_available" == true ]]; then
  selected_backend="metal"
fi

if [[ "$format" == "json" ]]; then
  python3 - "$os" "$arch" "$cpu" "$ram_mb" "$gpu_vendor" "$gpu_name" "$nvidia_driver" "$cuda_toolkit" "$rocm_runtime" "$metal_available" "$selected_backend" <<'PY'
import json, sys
keys = ["os","arch","cpu","ram_mb","gpu_vendor","gpu_name","nvidia_driver","cuda_toolkit","rocm_runtime","metal_available","selected_backend"]
vals = sys.argv[1:]
for i in (3,): vals[i] = int(vals[i])
for i in (6,7,8,9): vals[i] = vals[i].lower() == "true"
print(json.dumps(dict(zip(keys, vals)), ensure_ascii=False, indent=2))
PY
else
  printf 'OS: %s\n' "$os"
  printf 'Architektur: %s\n' "$arch"
  printf 'CPU: %s\n' "$cpu"
  printf 'RAM MB: %s\n' "$ram_mb"
  printf 'GPU Anbieter: %s\n' "$gpu_vendor"
  printf 'GPU: %s\n' "$gpu_name"
  printf 'NVIDIA Treiber: %s\n' "$nvidia_driver"
  printf 'CUDA Toolkit: %s\n' "$cuda_toolkit"
  printf 'ROCm Runtime: %s\n' "$rocm_runtime"
  printf 'Metal: %s\n' "$metal_available"
  printf 'Empfohlenes Backend: %s\n' "$selected_backend"
fi
