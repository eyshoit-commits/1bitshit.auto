#!/usr/bin/env python3
"""Apply or verify the public BitShit runtime identity.

The migration intentionally leaves internal crate and FFI identifiers untouched.
It updates visible CLI text and removes hard-coded speed estimates that were not
backed by a benchmark.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / "cmd" / "src" / "main.rs"
PULL = ROOT / "cmd" / "src" / "cli" / "pull.rs"

MAIN_REPLACEMENTS: tuple[tuple[str, str], ...] = (
    ("// ── Cluaiz CLI Definition", "// ── BitShit CLI Definition"),
    ('#[command(name = "cluaiz", about = "Cluaiz-OS: Sovereign Neural Kernel"',
     '#[command(name = "bitshit", about = "BitShit: Local Neural Runtime"'),
    ("/// Manage cluaiz Plugins", "/// Manage BitShit plugins"),
    ("/// Open the cluaiz Main Menu.", "/// Open the BitShit main menu."),
    ("/// 🛠️ Sync compiled development artifacts (engines, drivers) to ~/.cluaiz manually",
     "/// 🛠️ Sync compiled development artifacts (engines, drivers) to the BitShit runtime directory"),
    ("/// Setup Cluaiz Node Profile and Identity", "/// Setup BitShit node profile and identity"),
    ("run the global 'cluaiz' command", "run the global 'bitshit' command"),
    ('join("cluaiz_Core.log")', 'join("bitshit-core.log")'),
    ("// 🚀 Cluaiz BOOTSTRAP", "// 🚀 BitShit BOOTSTRAP"),
    ("[Cluaiz]", "[BitShit]"),
    ("Starting cluaiz API Daemon", "Starting BitShit API daemon"),
    ("Install a component from the cluaiz-hub registry", "Install a component from the BitShit registry"),
)

OLD_PORT = '''let port: u16 = std::env::var("cluaiz_PORT")
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(8000);'''
NEW_PORT = '''let port: u16 = std::env::var("BITSHIT_PORT")
                .or_else(|_| std::env::var("CLUAIZ_PORT"))
                .or_else(|_| std::env::var("cluaiz_PORT"))
                .ok()
                .and_then(|p| p.parse().ok())
                .unwrap_or(8000);'''

OLD_HOME_SET = 'std::env::set_var("cluaiz_HOME", global_dir.to_string_lossy().to_string());'
NEW_HOME_SET = '''std::env::set_var("BITSHIT_HOME", global_dir.to_string_lossy().to_string());
            // Temporary compatibility for internal crates not yet migrated.
            std::env::set_var("CLUAIZ_HOME", global_dir.to_string_lossy().to_string());
            std::env::set_var("cluaiz_HOME", global_dir.to_string_lossy().to_string());'''

OLD_HOME_REMOVE = 'std::env::remove_var("cluaiz_HOME");'
NEW_HOME_REMOVE = '''std::env::remove_var("BITSHIT_HOME");
            std::env::remove_var("CLUAIZ_HOME");
            std::env::remove_var("cluaiz_HOME");'''

OLD_TPS_BLOCK = '''    let projected_tps;
    if user_vram > 0.0 {
        if total_required <= user_vram {
            println!("    ├─ ⚡ Offload Status: Full GPU Acceleration (100% VRAM)");
            println!(
                "    ├─ 🧮 Remaining VRAM post-load: {:.2} GB",
                user_vram - total_required
            );
            projected_tps = 35.0;
        } else {
            let vram_ratio = (user_vram / total_required).clamp(0.0, 1.0);
            println!(
                "    ├─ ⚡ Offload Status: Partial GPU Acceleration ({:.0}% in VRAM)",
                vram_ratio * 100.0
            );
            println!(
                "    ├─ 🧮 Remaining System RAM post-load: {:.2} GB",
                user_ram - (total_required - user_vram)
            );
            projected_tps = if vram_ratio > 0.8 {
                22.0
            } else if vram_ratio > 0.5 {
                15.0
            } else {
                8.0
            };
        }
    } else {
        println!("    ├─ ⚡ Offload Status: CPU Inference (No dedicated VRAM)");
        println!(
            "    ├─ 🧮 Remaining System RAM post-load: {:.2} GB",
            user_ram - total_required
        );
        projected_tps = 5.0;
    }

    println!(
        "    ├─ 🚀 Projected Speed: ~{:.0} Tokens/Second (TPS)",
        projected_tps
    );'''

NEW_TPS_BLOCK = '''    if user_vram > 0.0 {
        if total_required <= user_vram {
            println!("    ├─ ⚡ Offload Status: Full GPU Acceleration (100% VRAM)");
            println!(
                "    ├─ 🧮 Remaining VRAM post-load: {:.2} GB",
                user_vram - total_required
            );
        } else {
            let vram_ratio = (user_vram / total_required).clamp(0.0, 1.0);
            println!(
                "    ├─ ⚡ Offload Status: Partial GPU Acceleration ({:.0}% in VRAM)",
                vram_ratio * 100.0
            );
            println!(
                "    ├─ 🧮 Remaining System RAM post-load: {:.2} GB",
                user_ram - (total_required - user_vram)
            );
        }
    } else {
        println!("    ├─ ⚡ Offload Status: CPU Inference (No dedicated VRAM)");
        println!(
            "    ├─ 🧮 Remaining System RAM post-load: {:.2} GB",
            user_ram - total_required
        );
    }

    println!("    ├─ 🚀 Measured Speed: unavailable until a real benchmark or generation run");'''


def replace_required(source: str, old: str, new: str, label: str, missing: list[str]) -> str:
    if old in source:
        return source.replace(old, new)
    if new not in source:
        missing.append(label)
    return source


def transform_main(source: str) -> tuple[str, list[str]]:
    missing: list[str] = []
    result = source
    for old, new in MAIN_REPLACEMENTS:
        result = replace_required(result, old, new, old, missing)
    result = replace_required(result, OLD_PORT, NEW_PORT, "legacy serve port block", missing)
    result = replace_required(result, OLD_HOME_SET, NEW_HOME_SET, "legacy DevSync home assignment", missing)
    result = replace_required(result, OLD_HOME_REMOVE, NEW_HOME_REMOVE, "legacy DevSync home cleanup", missing)
    return result, missing


def transform_pull(source: str) -> tuple[str, list[str]]:
    missing: list[str] = []
    result = replace_required(source, OLD_TPS_BLOCK, NEW_TPS_BLOCK, "hard-coded TPS projection block", missing)
    return result, missing


def process(path: Path, transformer, check: bool) -> tuple[bool, list[str]]:
    source = path.read_text(encoding="utf-8")
    transformed, missing = transformer(source)
    if missing:
        return False, [f"{path.relative_to(ROOT)}: {item}" for item in missing]
    if check:
        return source == transformed, ([] if source == transformed else [f"{path.relative_to(ROOT)} still needs migration"])
    if source != transformed:
        path.write_text(transformed, encoding="utf-8")
        print(f"Updated {path.relative_to(ROOT)}")
    return True, []


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    errors: list[str] = []
    for path, transformer in ((MAIN, transform_main), (PULL, transform_pull)):
        ok, current_errors = process(path, transformer, args.check)
        if not ok:
            errors.extend(current_errors)

    if errors:
        print("BitShit runtime migration is incomplete:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print("Public BitShit runtime identity and benchmark output are consistent.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
