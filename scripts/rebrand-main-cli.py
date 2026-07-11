#!/usr/bin/env python3
"""Apply or verify the public BitShit CLI identity in cmd/src/main.rs.

This intentionally leaves internal crate, API and FFI symbols untouched.  It is
safe to run repeatedly and exits non-zero when expected legacy source patterns
are missing, preventing a half-applied search-and-replace migration.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TARGET = ROOT / "cmd" / "src" / "main.rs"

REPLACEMENTS: tuple[tuple[str, str], ...] = (
    ("// ── Cluaiz CLI Definition", "// ── BitShit CLI Definition"),
    ('#[command(name = "cluaiz", about = "Cluaiz-OS: Sovereign Neural Kernel"',
     '#[command(name = "bitshit", about = "BitShit: Sovereign Neural Kernel"'),
    ("/// Manage cluaiz Plugins", "/// Manage BitShit plugins"),
    ("/// Open the cluaiz Main Menu.", "/// Open the BitShit main menu."),
    ("/// 🛠️ Sync compiled development artifacts (engines, drivers) to ~/.cluaiz manually",
     "/// 🛠️ Sync compiled development artifacts (engines, drivers) to ~/.bitshit manually"),
    ("/// Setup Cluaiz Node Profile and Identity", "/// Setup BitShit node profile and identity"),
    ("run the global 'cluaiz' command", "run the global 'bitshit' command"),
    ('join("cluaiz_Core.log")', 'join("bitshit-core.log")'),
    ("// 🚀 Cluaiz BOOTSTRAP", "// 🚀 BitShit BOOTSTRAP"),
    ("[Cluaiz]", "[BitShit]"),
    ("Starting cluaiz API Daemon", "Starting BitShit API daemon"),
)


def transform(source: str) -> tuple[str, list[str]]:
    result = source
    missing: list[str] = []
    for old, new in REPLACEMENTS:
        if old in result:
            result = result.replace(old, new)
        elif new not in result:
            missing.append(old)

    # Environment variables require ordered primary/fallback semantics rather
    # than a blind token replacement.
    old_port = '''let port: u16 = std::env::var("cluaiz_PORT")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(8000);'''
    new_port = '''let port: u16 = std::env::var("BITSHIT_PORT")
                .or_else(|_| std::env::var("CLUAIZ_PORT"))
                .or_else(|_| std::env::var("cluaiz_PORT"))
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(8000);'''
    if old_port in result:
        result = result.replace(old_port, new_port)
    elif new_port not in result:
        missing.append("legacy serve port block")

    old_home_set = 'std::env::set_var("cluaiz_HOME", global_dir.to_string_lossy().to_string());'
    new_home_set = '''std::env::set_var("BITSHIT_HOME", global_dir.to_string_lossy().to_string());
            // Temporary compatibility for internal crates not yet migrated.
            std::env::set_var("CLUAIZ_HOME", global_dir.to_string_lossy().to_string());
            std::env::set_var("cluaiz_HOME", global_dir.to_string_lossy().to_string());'''
    if old_home_set in result:
        result = result.replace(old_home_set, new_home_set)
    elif new_home_set not in result:
        missing.append("legacy DevSync home assignment")

    old_home_remove = 'std::env::remove_var("cluaiz_HOME");'
    new_home_remove = '''std::env::remove_var("BITSHIT_HOME");
            std::env::remove_var("CLUAIZ_HOME");
            std::env::remove_var("cluaiz_HOME");'''
    if old_home_remove in result:
        result = result.replace(old_home_remove, new_home_remove)
    elif new_home_remove not in result:
        missing.append("legacy DevSync home cleanup")

    return result, missing


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET)
    parser.add_argument("--check", action="store_true", help="verify the file is already transformed")
    args = parser.parse_args()

    source = args.target.read_text(encoding="utf-8")
    transformed, missing = transform(source)
    if missing:
        print("Refusing partial CLI rebrand; expected source patterns were not found:", file=sys.stderr)
        for pattern in missing:
            print(f"  - {pattern}", file=sys.stderr)
        return 2

    if args.check:
        if source != transformed:
            print(f"{args.target} still contains public Cluaiz identity; run {Path(__file__).name}", file=sys.stderr)
            return 1
        print("Public BitShit CLI identity is consistent.")
        return 0

    if source == transformed:
        print(f"{args.target} already uses the public BitShit identity.")
        return 0

    args.target.write_text(transformed, encoding="utf-8")
    print(f"Updated {args.target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
