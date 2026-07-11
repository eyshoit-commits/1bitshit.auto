#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "cmd" / "src" / "ui" / "apps" / "registry" / "mod.rs"

source = REGISTRY.read_text(encoding="utf-8")

old = '''                        let model_id = rec.manifest.id.clone();
                        let action = details::show_details(idx, rec, total_ram, &base_path, tx)?;

                        if matches!(action.as_deref(), Some("LOAD")) {
                            let path = Self::resolve_local_gguf(&rec.manifest).ok_or_else(|| {
                                color_eyre::eyre::eyre!(
                                    "Model is not downloaded as a resolvable GGUF file: {}",
                                    model_id
                                )
                            })?;
'''

new = '''                        let model_id = rec.manifest.id.clone();
                        let resolved_gguf = Self::resolve_local_gguf(&rec.manifest);
                        rec.is_cached = resolved_gguf.is_some();
                        let action = details::show_details(idx, rec, total_ram, &base_path, tx)?;

                        if matches!(action.as_deref(), Some("LOAD")) {
                            let Some(path) = resolved_gguf else {
                                history_segment = Some(format!("{} ❯ not downloaded", name.dimmed()));
                                Self::refresh_models(state);
                                continue;
                            };
'''

if new in source:
    print("Registry cache truth is already enforced.")
elif old in source:
    REGISTRY.write_text(source.replace(old, new, 1), encoding="utf-8")
    print("Updated registry cache truth enforcement.")
else:
    print("Registry source layout already changed; no historical cache patch applied.")
