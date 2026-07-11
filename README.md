# BitShit

**BitShit** is a local-first AI runtime and orchestration stack written primarily in Rust. It combines GGUF inference, ONNX-based multimodal execution, model management, an OpenAI-compatible API, hardware-aware memory control, native plugins, WASM skills and local RAG.

> **Status:** active alpha development. Source builds are supported; prebuilt release binaries are not yet guaranteed for every platform and backend.

## Supported platforms

| Platform | CPU | NVIDIA CUDA | AMD ROCm |
|---|:---:|:---:|:---:|
| Linux x86_64 | Yes | Yes | Yes |
| Linux arm64 | Yes | Platform-dependent | Platform-dependent |
| Windows x86_64 | Yes | Yes | Not yet in the unified installer |

The unified installer currently supports Linux and Windows. Backend support depends on the corresponding vendor toolchain and driver being installed before compilation.

## Requirements

The unified installers build BitShit from source.

Linux requires Git, Rust/Cargo, CMake, Make, Python 3 and a C/C++ compiler. The installer can install the missing base toolchain through `apt`, `dnf`, `pacman` or `apk`.

Windows uses an MSYS2 UCRT64 toolchain and installs the required packages automatically. CUDA additionally requires a working NVIDIA driver and CUDA toolkit.

## Installation

### Linux

```bash
git clone https://github.com/eyshoit-commits/1bitshit.auto.git
cd 1bitshit.auto
./install.sh
```

Non-interactive examples:

```bash
./install.sh --backend auto --yes
./install.sh --backend cpu --yes
./install.sh --backend cuda --yes
./install.sh --backend rocm --yes
```

Install without starting the resulting binary afterwards:

```bash
./install.sh --yes --no-launch
```

### Windows PowerShell

```powershell
git clone https://github.com/eyshoit-commits/1bitshit.auto.git
Set-Location 1bitshit.auto
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Non-interactive examples:

```powershell
.\install.ps1 -Backend Auto -Yes
.\install.ps1 -Backend Cpu -Yes
.\install.ps1 -Backend Cuda -Yes
.\install.ps1 -Backend Auto -Yes -NoLaunch
```

GNU-style arguments are accepted by `install.ps1` as well:

```powershell
.\install.ps1 --backend cpu --yes --no-launch
```

## Updates

The updater refreshes the repository to `origin/main` and then invokes the same platform installer contract. It does not maintain a second, slightly haunted installation path.

### Linux updates

The previous backend is read from `~/.bitshit/install.json` when no backend is supplied. If no prior state exists, automatic hardware detection is used.

```bash
./update.sh
./update.sh cpu
./update.sh --backend cuda
./update.sh --backend rocm --no-launch
./update.sh --no-launch
./update.sh --no-migrate --no-legacy-alias
```

Supported Linux updater backends are `auto`, `cpu`, `cuda` and `rocm`. Metal is intentionally not accepted by the Linux installer.

### Windows updates

Use the CMD bootstrap for updates. It refreshes `update.ps1` from GitHub before PowerShell parses its parameters, preventing stale installer versions from failing before they can update themselves.

```cmd
update.cmd auto
update.cmd cpu
update.cmd cuda
update.cmd --backend cuda --no-launch
update.cmd --no-migrate --no-legacy-alias
```

PowerShell can be called directly with positional, PowerShell-style or GNU-style arguments:

```powershell
.\update.ps1 cpu
.\update.ps1 -Backend cuda -NoLaunch
.\update.ps1 --backend cuda --no-launch
```

From Git Bash:

```bash
cmd.exe /c update.cmd cuda
./update.sh --backend cuda --no-launch
```

The update entrypoints preserve `--no-launch`, `--no-migrate` and `--no-legacy-alias` through every forwarding layer. Updates remain non-interactive and pass `-Yes` to the underlying installer.

## Installer behavior

The installers:

1. detect or validate the selected hardware backend;
2. migrate missing data from previous runtime directories without overwriting canonical files;
3. clone or update the source checkout;
4. initialize all Git submodules;
5. apply the public BitShit branding and model-path compatibility migrations;
6. compile the `bitshit` Cargo binary with `--locked`;
7. synchronize runtime engine and kernel artifacts;
8. install the executable into the user binary directory;
9. create `~/.bitshit/install.json` or its Windows equivalent;
10. optionally create a temporary `cluaiz` command alias for compatibility;
11. run `bitshit --version` unless `--no-launch` or `-NoLaunch` was supplied.

Default locations on Linux:

```text
Binary:       ~/.local/bin/bitshit
Runtime data: ~/.bitshit
Source:       ~/.bitshit/source
```

Default locations on Windows:

```text
Binary:       ~/.bitshit/bin/bitshit.exe
Runtime data: ~/.bitshit
Source:       ~/.bitshit/source
```

Environment overrides:

```text
BITSHIT_INSTALL_DIR
BITSHIT_HOME
BITSHIT_INTERIM_HOME
BITSHIT_SOURCE_DIR
BITSHIT_PROFILE
CLUAIZ_LEGACY_HOME
```

## Data migration

Migration is non-destructive and follows this order:

1. `~/.1bitshit` is copied first into `~/.bitshit`;
2. `~/.cluaiz` then fills only still-missing files;
3. existing files under `~/.bitshit` always win;
4. neither historical directory is deleted.

Each source receives its own marker:

```text
~/.bitshit/.migrated-from-1bitshit
~/.bitshit/.migrated-from-cluaiz
```

Disable automatic migration with:

```bash
./install.sh --no-migrate
./update.sh --no-migrate
```

```powershell
.\install.ps1 -NoMigrate
.\update.ps1 -NoMigrate
```

The detailed migration contract is documented in [docs/PATH_MIGRATION.md](docs/PATH_MIGRATION.md).

Internal crates, native artifacts and FFI symbols may temporarily retain legacy `cluaiz` names while compatibility-safe migration is completed. Those names are implementation details, not the public product identity. They are not removed merely to make a grep result prettier.

## Usage

```bash
bitshit --help
bitshit status
bitshit calibrate
bitshit list
bitshit pull Qwen/Qwen3-VL-2B-Instruct-GGUF
bitshit run Qwen/Qwen3-VL-2B-Instruct-GGUF
bitshit serve
```

The API server is OpenAI-compatible where implemented and defaults to port `8000`. During the transition, some runtime components still accept legacy environment variable names. New integrations should use `BITSHIT_HOME` and `BITSHIT_PORT` as they are introduced across the workspace.

## Runtime architecture

BitShit currently combines:

- a Rust CLI and orchestration layer;
- `llama.cpp`-derived GGUF inference backends;
- ONNX Runtime for vision, embeddings and other multimodal workloads;
- hardware probing and memory governance;
- local model and artifact storage;
- native plugin, WASM skill and extension execution;
- local document ingestion and vector search;
- an Axum/Tokio API gateway.

Several directories and crate names still reflect the inherited codebase. Renaming them is performed in controlled stages because blind replacement would break Cargo package references, native linkage, cache discovery and existing installations.

## Development

```bash
git clone --recurse-submodules https://github.com/eyshoit-commits/1bitshit.auto.git
cd 1bitshit.auto
cargo build --locked -p cmd --bin bitshit
```

CPU-only build environment:

```bash
GGML_CUDA=OFF GGML_HIPBLAS=OFF GGML_METAL=OFF \
  cargo build --locked -p cmd --bin bitshit
```

Run the repository checks:

```bash
python3 tests/installer_contract.py
bash scripts/verify-bitshit-rebrand.sh
```

## Security and compatibility

- Runtime data remains local unless a configured component explicitly performs network access.
- Existing `.1bitshit` and `.cluaiz` data is never deleted by the migration installer.
- The legacy command alias can be disabled with `--no-legacy-alias` or `-NoLegacyAlias`.
- The post-install version invocation can be disabled with `--no-launch` or `-NoLaunch`.
- Alpha builds may change configuration formats before a stable release.

## License

Apache License 2.0. See [LICENSE](LICENSE).
