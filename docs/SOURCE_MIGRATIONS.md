# BitShit source migration pipeline

The installer and the Cargo build script apply the same ordered, idempotent source migration pipeline before compiling the public `bitshit` binary.

## Required order

1. `repair-openmp-duplicates.py`
   Repairs source damage left by older non-idempotent OpenMP migrations.
2. `rebrand-main-cli.py`
   Migrates the main CLI entry point and public binary naming to BitShit.
3. `fix-public-branding.py`
   Replaces remaining user-visible Cluaiz labels while preserving internal crate, ABI, FFI and compatibility identifiers.
4. `fix-model-runtime.py`
   Aligns model paths and runtime selection with the canonical BitShit data directory.
5. `fix-registry-cache.py`
   Repairs registry and cache handling needed by existing installations.
6. `fix-model-hub-load.py`
   Repairs local model discovery and model-hub loading, including GGUF routing fixes.
7. `fix-bitnet-routing.py`
   Extends the model-load guards for incomplete legacy manifests. BitNet is recognized from architecture, architecture type, model id, display name and the local filename, including `ggml-model-i2_s.gguf` and underscore variants. A BitNet artifact therefore cannot fall through to ONNX Vision or the generic llama/GGUF loader merely because its manifest says `unknown`.

## Execution points

The complete list is executed by all supported build paths:

- `scripts/app-linux.sh`
- `scripts/app-windows.ps1`
- `cmd/build.rs`

The installer runs the scripts explicitly before Cargo. `cmd/build.rs` repeats the same idempotent pipeline as a safety net for developers who invoke Cargo directly. A missing or failing migration is fatal; silently building a partly migrated runtime is not accepted.

## Compatibility rule

Public product text, commands and canonical data paths use **BitShit** and `.bitshit`. Existing internal names such as `cluaiz-engine`, `cluaiz-llama`, Rust crate names, FFI symbols and the optional `cluaiz` binary alias remain intact where renaming would break compatibility or remove functionality.

BitNet detection does not depend on a single manifest field. Historical downloads such as `ggml_model_i2_s:unknown:gguf:unknown` remain discoverable and deletable, but are never sent to an incompatible loader. This is a routing safety repair, not feature removal. A dedicated BitNet kernel can later replace the guarded unsupported path without changing model identity or stored data.

## CI contract

`tests/installer_contract.py` verifies that Linux, Windows and `cmd/build.rs` contain the same migration list in the same order. It also checks the incomplete-manifest BitNet signatures. The installer CI matrix compiles every Python migration script on Ubuntu and Windows before validating shell syntax.
