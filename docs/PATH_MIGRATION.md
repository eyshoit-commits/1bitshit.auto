# BitShit path and data migration

## Canonical locations

BitShit uses one public runtime home on every supported platform:

- Linux: `${BITSHIT_HOME:-$HOME/.bitshit}`
- Windows: `${BITSHIT_HOME:-$HOME/.bitshit}`

The source checkout defaults to `$BITSHIT_HOME/source`. Downloaded model weights
remain visible in that checkout under `models/dl`; the curated store metadata is
kept under `models/library`.

`CLUAIZ_HOME` is retained only as an internal compatibility environment variable
for crates and FFI components that still use the historical name. Installers set
it to the same canonical directory as `BITSHIT_HOME`. New public data must not be
written to `~/.cluaiz` or `~/.1bitshit`.

## Legacy migration

Two historical runtime locations are recognized:

1. `~/.1bitshit`, the short-lived interim BitShit path.
2. `~/.cluaiz`, the original runtime path.

They can be overridden for testing or recovery with `BITSHIT_INTERIM_HOME` and
`CLUAIZ_LEGACY_HOME`.

Migration has the following contract:

1. It is idempotent on Linux and Windows.
2. Existing files under `BITSHIT_HOME` always win and are never overwritten.
3. Historical files are copied, not deleted or moved.
4. `~/.1bitshit` is processed before `~/.cluaiz`, because it is the newer source.
5. Each source receives its own marker:
   - `$BITSHIT_HOME/.migrated-from-1bitshit`
   - `$BITSHIT_HOME/.migrated-from-cluaiz`
6. Marker files record source, target, UTC timestamp, and `mode=copy-missing`.
7. Model files are copied separately into `BITSHIT_MODELS_DIR` because model
   storage can be outside the runtime home.
8. `--no-migrate` on Unix-like launchers and `-NoMigrate` on PowerShell disable
   both automatic migrations.

Keeping both historical directories intact is deliberate. A failed build must
not turn a rebrand into an improvised data-loss utility, a niche nobody requested.

## Installer backends

Linux supports `auto`, `cpu`, `cuda`, and `rocm`. Windows supports `auto`, `cpu`,
and `cuda` through MSYS2 UCRT64. Explicit GPU selections fail when the required
toolchain is absent; they do not silently fall back to CPU.

Examples:

```bash
./install.sh --backend auto --yes
./install.sh --backend cpu --yes
./install.sh --backend cuda --yes
./install.sh --backend rocm --yes
```

```powershell
.\scripts\setup-windows.ps1 -Backend auto -Yes
.\scripts\setup-windows.ps1 -Backend cpu -Yes
.\scripts\setup-windows.ps1 -Backend cuda -Yes
```

## Result metadata

A successful installation writes `$BITSHIT_HOME/install.json`. Both platform
installers now emit the same migration-related fields:

- `runtime`: canonical `BITSHIT_HOME`
- `interim_source`: the `.1bitshit` source
- `legacy_source`: the `.cluaiz` source
- `migration_mode`: `copy-missing`

Internal engine filenames may still contain `cluaiz` until the ABI migration is
completed; that does not change their canonical storage root.
