#!/usr/bin/env python3
"""Repair duplicated OpenMP preload code left by earlier source migrations."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / "cmd" / "src" / "main.rs"

BLOCK_RE = re.compile(
    r'''\n?#\[cfg\(all\(unix, not\(target_os = "macos"\)\)\)\]\n'''
    r'''fn preload_openmp_runtime\(\) -> Result<\(\)> \{.*?\n\}\n\n'''
    r'''#\[cfg\(any\(not\(unix\), target_os = "macos"\)\)\]\n'''
    r'''fn preload_openmp_runtime\(\) -> Result<\(\)> \{\n    Ok\(\(\)\)\n\}\n?''',
    re.DOTALL,
)


def main() -> int:
    source = MAIN.read_text(encoding="utf-8")
    matches = list(BLOCK_RE.finditer(source))
    changed = False

    if len(matches) > 1:
        keep = matches[0].group(0).strip("\n")
        source = BLOCK_RE.sub("", source)
        anchor = "use crate::core::bootstrapper::Bootstrapper;\n"
        if anchor not in source:
            raise RuntimeError("Bootstrapper import anchor missing while repairing OpenMP blocks")
        source = source.replace(anchor, anchor + "\n" + keep + "\n", 1)
        changed = True

    call = "    preload_openmp_runtime()?;\n"
    if source.count(call) > 1:
        first = source.find(call)
        before = source[: first + len(call)]
        after = source[first + len(call) :].replace(call, "")
        source = before + after
        changed = True

    if changed:
        MAIN.write_text(source, encoding="utf-8")
        print("Removed duplicated OpenMP preload definitions from cmd/src/main.rs")
    else:
        print("OpenMP preload definitions are already unique")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
