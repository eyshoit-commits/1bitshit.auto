# BitShit

**BitShit** is a local-first AI runtime and orchestration stack written primarily in Rust. It combines GGUF inference, ONNX-based multimodal execution, model management, an OpenAI-compatible API, hardware-aware memory control, native plugins, WASM skills and local RAG.

> **Status:** active alpha development. Source builds are supported; prebuilt release binaries are not yet guaranteed for every platform and backend.

## Supported platforms

| Platform | CPU | NVIDIA CUDA | AMD ROCm | Apple Metal |
|---|:---:|:---:|:---:|:---:|
| Linux x86_64 | Yes | Yes | Yes | No |
| Linux arm64 | Yes | Platform-dependent | Platform-dependent | No |
| Windows x86_64 | Yes | Yes | Not yet in the unified installer | No |
| macOS arm64/x86_64 | Yes | No | No | Yes |

Backend support depends on the corresponding vendor toolchain and driver being installed before compilation.

## Requirements

The unified installers build BitShit from source. Install these tools first:

- Git
- Rust and Cargo
- CMake
- a C/C++ build toolchain
- backend SDK when using CUDA, ROCm or Metal

Linux additionally requires `make`. Windows requires Visual Studio Build Tools with the Desktop development with C++ workload.

## Installation

### Linux and macOS

```bash
git clone https://github.com/eyshoit-commits/bitshit.cpu.git
cd bitshit.cpu
./install.sh
```

Non-interactive examples:

```bash
./install.sh --backend auto --yes
./install.sh --backend cpu --yes
./install.sh --backend cuda --yes
./install.sh --backend rocm --yes
./install.sh --backend metal --yes
```

### Windows PowerShell

```powershell
git clone https://github.com/eyshoit-commits/bitshit.cpu.git
Set-Location bitshit.cpu
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Non-interactive examples:

```powershell
.\install.ps1 -Backend Auto -Yes
.\install.ps1 -Backend Cpu -Yes
.\install.ps1 -Backend Cuda -Yes
```

### Windows updates

Use the CMD bootstrap for updates. It refreshes `update.ps1` from GitHub before PowerShell parses its parameters, preventing stale installer versions from failing before they can update themselves.

```cmd
update.cmd auto
update.cmd cpu
update.cmd cuda
```

From Git Bash:

```bash
cmd.exe /c update.cmd cuda
```

## Installer behavior

The installers:

1. detect or validate the selected hardware backend;
2. clone or update the source checkout;
3. initialize all Git submodules;
4. compile the `bitshit` Cargo binary with `--locked`;
5. install the executable into the user binary directory;
6. create `~/.bitshit/install.json` or its Windows equivalent;
7. optionally create a temporary `cluaiz` command alias for compatibility.

Default locations on Linux and macOS:

```text
Binary:       ~/.local/bin/bitshit
Runtime data: ~/.bitshit
Source:       ~/.bitshit/source
```

Environment overrides:

```text
BITSHIT_INSTALL_DIR
BITSHIT_HOME
BITSHIT_SOURCE_DIR
BITSHIT_PROFILE
```

## Data migration

Existing data under `~/.cluaiz` is copied once into `~/.bitshit` when the new directory is empty. The old directory is preserved. A migration marker prevents repeated imports.

Disable automatic migration with:

```bash
./install.sh --no-migrate
```

```powershell
.\install.ps1 -NoMigrate
```

The complete migration, environment precedence and internal compatibility rules are defined in [docs/BITSHIT_MIGRATION.md](docs/BITSHIT_MIGRATION.md).

Internal crates and FFI symbols may temporarily retain legacy `cluaiz` names while compatibility-safe migration is completed. Those names are implementation details, not the public product identity.

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

Several directories and crate names still reflect the inherited codebase. Renaming them is being performed in controlled stages because blind replacement would break Cargo package references, native linkage, cache discovery and existing installations.

## Development

```bash
git clone --recurse-submodules https://github.com/eyshoit-commits/bitshit.cpu.git
cd bitshit.cpu
cargo build --locked -p cmd --bin bitshit
```

CPU-only build environment:

```bash
GGML_CUDA=OFF GGML_HIPBLAS=OFF GGML_METAL=OFF \
  cargo build --locked -p cmd --bin bitshit
```

Run the repository rebranding checks:

```bash
bash scripts/verify-bitshit-rebrand.sh
```

## Security and compatibility

- Runtime data remains local unless a configured component explicitly performs network access.
- Existing `.cluaiz` data is never deleted by the migration installer.
- The legacy command alias can be disabled with `--no-legacy-alias` or `-NoLegacyAlias`.
- Alpha builds may change configuration formats before a stable release.

## License

Apache License 2.0. See [LICENSE](LICENSE).
