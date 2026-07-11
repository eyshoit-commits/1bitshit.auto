#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    target = ROOT / path
    if not target.is_file():
        raise AssertionError(f"missing required file: {path}")
    return target.read_text(encoding="utf-8")


def require(text: str, needle: str, path: str) -> None:
    if needle not in text:
        raise AssertionError(f"{path}: missing contract fragment: {needle!r}")


def forbid(text: str, needle: str, path: str) -> None:
    if needle in text:
        raise AssertionError(f"{path}: forbidden fragment returned: {needle!r}")


def assert_order(text: str, fragments: tuple[str, ...], path: str) -> None:
    positions = []
    for fragment in fragments:
        require(text, fragment, path)
        positions.append(text.index(fragment))
    if positions != sorted(positions):
        raise AssertionError(f"{path}: migration pipeline order is inconsistent")


def main() -> int:
    launcher = read("install.sh")
    windows_launcher = read("install.ps1")
    linux_setup = read("scripts/setup-linux.sh")
    windows_setup = read("scripts/setup-windows.ps1")
    linux = read("scripts/app-linux.sh")
    windows = read("scripts/app-windows.ps1")
    linux_update = read("update.sh")
    windows_update = read("update.ps1")
    cmd_update = read("update.cmd")
    build_rs = read("cmd/build.rs")
    docs = read("docs/PATH_MIGRATION.md")
    source_docs = read("docs/SOURCE_MIGRATIONS.md")
    bitnet_routing = read("scripts/fix-bitnet-routing.py")
    readme = read("README.md")

    for fragment in (
        "--backend auto|cpu|cuda|rocm",
        "--no-legacy-alias",
        "--no-migrate",
        "--no-launch",
    ):
        require(launcher, fragment, "install.sh")

    for fragment in (
        "$NoLaunch = $false",
        "--?no-launch",
        "$Forward.NoLaunch = $true",
    ):
        require(windows_launcher, fragment, "install.ps1")

    for fragment in (
        "--no-launch",
        "PASS_ARGS+=(\"$1\")",
    ):
        require(linux_setup, fragment, "scripts/setup-linux.sh")

    for fragment in (
        "[switch]$NoLaunch",
        "$AppArgs.NoLaunch = $true",
    ):
        require(windows_setup, fragment, "scripts/setup-windows.ps1")

    for fragment in (
        'DATA_DIR="${BITSHIT_HOME:-$HOME/.bitshit}"',
        'INTERIM_DATA_DIR="${BITSHIT_INTERIM_HOME:-$HOME/.1bitshit}"',
        'LEGACY_DATA_DIR="${CLUAIZ_LEGACY_HOME:-$HOME/.cluaiz}"',
        'copy_missing_tree "$INTERIM_DATA_DIR" ".migrated-from-1bitshit"',
        'copy_missing_tree "$LEGACY_DATA_DIR" ".migrated-from-cluaiz"',
        'mode=copy-missing',
        '"migration_mode":"copy-missing"',
        "--no-launch",
        '[[ $LAUNCH_AFTER_INSTALL -eq 1 ]]',
        'SOURCE_MIGRATIONS=(',
        'for migration in "${SOURCE_MIGRATIONS[@]}"',
    ):
        require(linux, fragment, "scripts/app-linux.sh")

    for fragment in (
        "Join-Path $HOME '.bitshit'",
        "Join-Path $HOME '.1bitshit'",
        "Join-Path $HOME '.cluaiz'",
        "Copy-MissingTree $InterimHome '.migrated-from-1bitshit'",
        "Copy-MissingTree $LegacyHome '.migrated-from-cluaiz'",
        "migration_mode='copy-missing'",
        "$env:CLUAIZ_HOME = $HomeDir",
        "[switch]$NoLaunch",
        "if (-not $NoLaunch)",
        '$SourceMigrations = @(',
        'foreach ($Migration in $SourceMigrations)',
    ):
        require(windows, fragment, "scripts/app-windows.ps1")

    source_migrations = (
        "repair-openmp-duplicates.py",
        "rebrand-main-cli.py",
        "fix-public-branding.py",
        "fix-model-runtime.py",
        "fix-registry-cache.py",
        "fix-model-hub-load.py",
        "fix-bitnet-routing.py",
    )
    for path, text in (
        ("scripts/app-linux.sh", linux),
        ("scripts/app-windows.ps1", windows),
        ("cmd/build.rs", build_rs),
    ):
        assert_order(text, source_migrations, path)

    for fragment in (
        'architecture_type',
        'ggml-model-i2_s',
        'ggml_model_i2_s',
        'i2-s',
        'local_path',
        'if is_bitnet',
    ):
        require(bitnet_routing, fragment, "scripts/fix-bitnet-routing.py")
    require(source_docs, "fix-bitnet-routing.py", "docs/SOURCE_MIGRATIONS.md")

    for fragment in (
        "--backend=*)",
        "--no-legacy-alias",
        "--no-migrate",
        "--no-launch",
        'INSTALL_ARGS=(--backend "$BACKEND" --yes)',
        'bash "$REPO_ROOT/install.sh" "${INSTALL_ARGS[@]}"',
        'auto|cpu|cuda|rocm)',
    ):
        require(linux_update, fragment, "update.sh")
    forbid(linux_update, "auto|cpu|cuda|rocm|metal", "update.sh")

    for fragment in (
        "$NoLegacyAlias = $false",
        "$NoMigrate = $false",
        "$NoLaunch = $false",
        "--?no-legacy-alias",
        "--?no-migrate",
        "--?no-launch",
        "$Forward.NoLegacyAlias = $true",
        "$Forward.NoMigrate = $true",
        "$Forward.NoLaunch = $true",
        "Yes = $true",
    ):
        require(windows_update, fragment, "update.ps1")

    require(cmd_update, '"%~dp0update.ps1" %*', "update.cmd")
    forbid(cmd_update, 'set "BACKEND=%~1"', "update.cmd")

    interim_pos = windows.index("Copy-MissingTree $InterimHome")
    legacy_pos = windows.index("Copy-MissingTree $LegacyHome")
    if interim_pos >= legacy_pos:
        raise AssertionError("Windows migration must process .1bitshit before .cluaiz")

    interim_pos = linux.index('copy_missing_tree "$INTERIM_DATA_DIR"')
    legacy_pos = linux.index('copy_missing_tree "$LEGACY_DATA_DIR"')
    if interim_pos >= legacy_pos:
        raise AssertionError("Linux migration must process .1bitshit before .cluaiz")

    for fragment in (
        "BITSHIT_INTERIM_HOME",
        "CLUAIZ_LEGACY_HOME",
        ".migrated-from-1bitshit",
        ".migrated-from-cluaiz",
        "copy-missing",
    ):
        require(docs, fragment, "docs/PATH_MIGRATION.md")

    for fragment in (
        "eyshoit-commits/1bitshit.auto",
        "--no-launch",
        "-NoLaunch",
        "~/.1bitshit",
        "~/.cluaiz",
        "./update.sh --no-launch",
        "update.cmd --no-launch",
    ):
        require(readme, fragment, "README.md")

    forbid(linux, 'LEGACY_DATA_DIR="${CLUAIZ_LEGACY_HOME:-${CLUAIZ_HOME:', "scripts/app-linux.sh")
    forbid(readme, "eyshoit-commits/bitshit.cpu", "README.md")

    print("BitShit installer, updater, migration and launch contract: OK")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        print(f"installer contract failed: {error}", file=sys.stderr)
        raise SystemExit(1)
