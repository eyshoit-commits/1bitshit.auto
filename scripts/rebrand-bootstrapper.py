#!/usr/bin/env python3
"""Deterministically migrate the public bootstrapper identity to BitShit.

Internal artifact names such as cluaiz-engine and cluaiz-llama intentionally stay
unchanged until their ABI and on-disk compatibility migration is handled.
"""

from __future__ import annotations

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "cmd" / "src" / "core" / "bootstrapper.rs"

REPLACEMENTS = (
    (
        'https://raw.githubusercontent.com/cluaiz/cluaiz/main/package.json',
        'https://raw.githubusercontent.com/eyshoit-commits/bitshit.cpu/main/package.json',
    ),
    ('cluaiz-Bootstrapper/', 'bitshit-bootstrapper/'),
    ('/// 🚀 cluaiz BOOTSTRAP:', '/// 🚀 BitShit bootstrap:'),
    ('[cluaiz] Igniting Neural Foundry', '[BitShit] Igniting Neural Foundry'),
    ('[cluaiz] Synchronizing Neural Registry', '[BitShit] Synchronizing Neural Registry'),
    ('[cluaiz] Update Available:', '[BitShit] Update available:'),
    ('[cluaiz] Provisioning Core Engine', '[BitShit] Provisioning core engine'),
    ('[cluaiz] Synchronizing Neural Kernel', '[BitShit] Synchronizing neural kernel'),
    ('[Cluaiz] Network sync skipped', '[BitShit] Network sync skipped'),
    ('[Cluaiz] Provisioning failed', '[BitShit] Provisioning failed'),
    ('[Cluaiz] Kernel sync failed', '[BitShit] Kernel sync failed'),
    ('Synchronizes local build artifacts to .cluaiz.', 'Synchronizes local build artifacts to the BitShit runtime directory.'),
    ('Automatically injects cluaiz into the Windows Global PATH.', 'Automatically injects BitShit into the Windows user PATH.'),
    ('check if cluaiz is in it', 'check if the BitShit bin directory is present'),
)


def transform(source: str) -> tuple[str, list[str]]:
    missing: list[str] = []
    result = source
    for old, new in REPLACEMENTS:
        if old in result:
            result = result.replace(old, new)
        elif new not in result:
            missing.append(old)
    return result, missing


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify the bootstrapper is fully migrated without changing it",
    )
    args = parser.parse_args()

    source = TARGET.read_text(encoding="utf-8")
    updated, missing = transform(source)

    if missing:
        print("Bootstrapper migration contract is incomplete; missing source markers:")
        for marker in missing:
            print(f"  - {marker}")
        return 2

    if args.check:
        if updated != source:
            print("Bootstrapper still contains public Cluaiz identity. Run scripts/rebrand-bootstrapper.py")
            return 1
        print("Bootstrapper public identity is fully migrated.")
        return 0

    if updated == source:
        print("Bootstrapper already migrated; no changes required.")
        return 0

    TARGET.write_text(updated, encoding="utf-8")
    print(f"Updated {TARGET.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
