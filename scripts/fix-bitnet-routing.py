#!/usr/bin/env python3
"""Harden BitNet routing when registry metadata is incomplete.

Older downloaded manifests may report architecture=unknown while the model id,
name or local GGUF filename still clearly identifies Microsoft BitNet I2_S.
This migration extends the guards installed by fix-model-hub-load.py so those
artifacts are never passed to ONNX or the generic llama/GGUF loader.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "cmd" / "src" / "ui" / "apps" / "registry" / "mod.rs"
DETAILS = ROOT / "cmd" / "src" / "ui" / "apps" / "registry" / "details.rs"
DASHBOARD = ROOT / "cmd" / "src" / "core" / "dashboard.rs"


def replace_once(path: Path, old: str, new: str, label: str) -> bool:
    source = path.read_text(encoding="utf-8")
    if new in source:
        return False
    if old not in source:
        print(f"Skipped {label}: source layout already changed in {path.relative_to(ROOT)}")
        return False
    path.write_text(source.replace(old, new, 1), encoding="utf-8")
    print(f"Applied {label} in {path.relative_to(ROOT)}")
    return True


def bitnet_probe(prefix: str, manifest: str) -> str:
    return f'''{prefix}let bitnet_identity = format!(
{prefix}    "{{}} {{}} {{}} {{}}",
{prefix}    {manifest}.architecture,
{prefix}    {manifest}.architecture_type,
{prefix}    {manifest}.id,
{prefix}    {manifest}.name,
{prefix}).to_ascii_lowercase();
{prefix}let bitnet_path = {manifest}.local_path.as_deref().unwrap_or_default().to_ascii_lowercase();
{prefix}let is_bitnet = bitnet_identity.contains("bitnet")
{prefix}    || bitnet_identity.contains("1.58")
{prefix}    || bitnet_identity.contains("i2_s")
{prefix}    || bitnet_identity.contains("i2-s")
{prefix}    || bitnet_path.contains("bitnet")
{prefix}    || bitnet_path.contains("ggml-model-i2_s")
{prefix}    || bitnet_path.contains("ggml_model_i2_s")
{prefix}    || bitnet_path.contains("i2-s");'''


def main() -> int:
    changed = False

    changed |= replace_once(
        REGISTRY,
        '''                              let architecture = rec.manifest.architecture.to_ascii_lowercase();
                              if architecture.contains("bitnet") || architecture.contains("1.58") {''',
        bitnet_probe("                              ", "rec.manifest") + '''
                              if is_bitnet {''',
        "registry BitNet identity fallback",
    )

    changed |= replace_once(
        DETAILS,
        '''        let architecture = rec.manifest.architecture.to_ascii_lowercase();
        let bitnet_requires_dedicated_kernel =
            architecture.contains("bitnet") || architecture.contains("1.58");''',
        bitnet_probe("        ", "rec.manifest") + '''
        let bitnet_requires_dedicated_kernel = is_bitnet;''',
        "details BitNet identity fallback",
    )

    changed |= replace_once(
        DASHBOARD,
        '''                    let architecture = m.manifest.architecture.to_ascii_lowercase();
                    let is_bitnet = architecture.contains("bitnet") || architecture.contains("1.58");''',
        bitnet_probe("                    ", "m.manifest"),
        "auto-boot BitNet identity fallback",
    )

    changed |= replace_once(
        DASHBOARD,
        '''                                    let architecture = model.manifest.architecture.to_ascii_lowercase();
                                    let is_bitnet = architecture.contains("bitnet") || architecture.contains("1.58");''',
        bitnet_probe("                                    ", "model.manifest"),
        "lazy-load BitNet identity fallback",
    )

    if changed:
        print("Applied robust BitNet routing guards for incomplete manifests.")
    else:
        print("Robust BitNet routing guards are already current or superseded.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"BitNet routing migration failed: {exc}", file=sys.stderr)
        raise SystemExit(2)
