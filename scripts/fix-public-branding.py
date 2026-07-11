#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOTS = [ROOT / "cmd" / "src"]

REPLACEMENTS = (
    ("[cluaiz]", "[BitShit]"),
    ("[Cluaiz]", "[BitShit]"),
    ("cluaiz v", "BitShit v"),
    ("Cluaiz v", "BitShit v"),
    ("Cluaiz-OS: Sovereign Neural Kernel", "BitShit: Local Neural Runtime"),
    ("run the global 'cluaiz' command", "run the global 'bitshit' command"),
    ("Open the cluaiz Main Menu", "Open the BitShit main menu"),
    ("Manage cluaiz Plugins", "Manage BitShit plugins"),
    ("Setup Cluaiz Node Profile and Identity", "Setup BitShit node profile and identity"),
    ("Install a component from the cluaiz-hub registry", "Install a component from the BitShit registry"),
    ("🚀 Cluaiz BOOTSTRAP", "🚀 BitShit BOOTSTRAP"),
    ("cluaiz RENDER CONFIG", "BitShit RENDER CONFIG"),
    ("cluaiz Startup Scan", "BitShit startup scan"),
    ("cluaiz TELEMETRY IGNITION", "BitShit telemetry ignition"),
    ("cluaiz AUTO-BOOT", "BitShit AUTO-BOOT"),
)

changed_files = []
for source_root in SOURCE_ROOTS:
    for path in source_root.rglob("*.rs"):
        source = path.read_text(encoding="utf-8")
        updated = source
        for old, new in REPLACEMENTS:
            updated = updated.replace(old, new)
        if updated != source:
            path.write_text(updated, encoding="utf-8")
            changed_files.append(path.relative_to(ROOT))

if changed_files:
    print("Updated public BitShit branding in:")
    for path in changed_files:
        print(f"  - {path}")
else:
    print("Public BitShit branding is already current.")
