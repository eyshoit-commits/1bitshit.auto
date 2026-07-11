# BitShit migration and compatibility contract

This document defines the supported transition from legacy Cluaiz installations to BitShit. It is intentionally explicit because silent path changes and native runtime renames are an excellent way to turn user data into archaeology.

## Public product identity

The public command, documentation and installation target are now:

- command: `bitshit`
- Unix data directory: `~/.bitshit`
- Windows data directory: `%USERPROFILE%\.bitshit`
- primary runtime environment variable: `BITSHIT_HOME`
- primary API port variable: `BITSHIT_PORT`
- repository: `eyshoit-commits/bitshit.cpu`

The names `cluaiz`, `CLUAIZ_HOME` and `cluaiz_PORT` are legacy compatibility identifiers only. They must not be introduced in new public documentation, messages or installer output.

## Installer migration behavior

Both unified installers perform a one-time, non-destructive migration when a legacy data directory exists and the BitShit data directory is not already marked as migrated.

The migration contract is:

1. copy legacy data into the BitShit data directory;
2. never delete or rewrite the original legacy directory;
3. never overwrite files already present in the BitShit directory;
4. preserve symbolic links on POSIX systems;
5. create `.migrated-from-cluaiz` after a successful migration;
6. record the legacy source path in `install.json`;
7. allow migration to be disabled with `--no-migrate` on POSIX or `-NoMigrate` on Windows.

The marker makes repeated installer runs idempotent. Removing the marker manually requests another merge-style migration, not destructive replacement.

## Binary compatibility

The installed binary is `bitshit`.

Installers may create a temporary `cluaiz` alias for existing scripts. Users can disable it with:

```bash
./install.sh --no-legacy-alias
```

```powershell
.\install.ps1 -NoLegacyAlias
```

The alias is transitional and must not be used by new examples, services or release packaging.

## Runtime environment precedence

Runtime configuration must resolve variables in this order:

1. `BITSHIT_HOME` / `BITSHIT_PORT`
2. legacy `CLUAIZ_HOME` / `cluaiz_PORT`
3. platform default (`~/.bitshit`, port `8000`)

Legacy values are fallback inputs only. Whenever the runtime writes configuration or reports active paths, it should use BitShit terminology.

## Backend build contract

The unified installer supports these source-build selections:

| Backend | POSIX installer | Windows installer | Required toolchain |
|---|---:|---:|---|
| CPU | yes | yes | C/C++ compiler, CMake, Rust |
| NVIDIA CUDA | yes | yes | NVIDIA driver and `nvcc` |
| AMD ROCm | yes | not yet exposed | `hipcc` and `rocminfo` |
| Apple Metal | macOS only | no | Xcode command-line tools |

Backend variables are set explicitly for every build so stale shell state cannot accidentally combine CUDA, ROCm and Metal flags.

## Internal compatibility boundary

Several Rust crates, modules, FFI symbols and native artifact names still contain `cluaiz`. These identifiers are not automatically safe to rename because they participate in:

- Cargo dependency names;
- native library lookup;
- C ABI symbols;
- serialized configuration paths;
- plugin and registry compatibility;
- existing user caches.

Internal renames therefore require one of the following:

- a Rust package alias;
- an exported compatibility symbol;
- dual-path lookup with BitShit preferred;
- a versioned data migration;
- or an explicit breaking-change release note.

A repository-wide blind replacement is prohibited until these boundaries are removed. Search-and-replace remains a tool, not a migration strategy, despite humanity's recurring optimism.

## CI expectations

The repository workflow must verify:

- shell and PowerShell installer syntax;
- public binary target `bitshit`;
- Cargo metadata on Linux, Windows and macOS;
- a real CPU release build;
- backend selection contracts for CPU, CUDA, ROCm and Metal;
- absence of obsolete remote installer URLs;
- presence and idempotence of legacy data migration.

Real vendor-backed GPU compilation requires matching SDKs and hardware. Hosted runners may validate configuration contracts, while CUDA, ROCm and Metal compilation should run on dedicated self-hosted runners.

## Current limitation

The public CLI source still contains visible legacy strings in `cmd/src/main.rs`, including Clap metadata, error prefixes, log naming, daemon text and the old API port variable. That file is the next public-runtime migration block. Internal crate references such as `cluaiz_shared` remain valid compatibility identifiers until their dependency and FFI migration is implemented.
