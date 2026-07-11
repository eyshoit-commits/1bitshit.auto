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
written to `~/.cluaiz`.

## Legacy migration

The default legacy source is `~/.cluaiz`. It can be overridden with
`CLUAIZ_LEGACY_HOME` when testing or recovering a custom installation.

Migration has the following contract:

1. It is idempotent.
2. Existing BitShit files win and are never overwritten by legacy data.
3. Legacy files are copied, not deleted or moved.
4. Linux records the completed runtime migration in
   `$BITSHIT_HOME/.migrated-from-cluaiz`.
5. Model files are copied separately into `BITSHIT_MODELS_DIR` because model
   storage can be outside the runtime home.
6. `--no-migrate` disables automatic legacy migration.

Keeping the old directory intact is deliberate. A failed build must not turn a
rebrand into an improvised data-loss utility.

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

A successful installation writes `$BITSHIT_HOME/install.json`. The `runtime`
field must point to `BITSHIT_HOME`, while `legacy_source` identifies the old data
source when applicable. Internal engine filenames may still contain `cluaiz`
until the ABI migration is completed; that does not change their storage root.
