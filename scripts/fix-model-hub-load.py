#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "cmd" / "src" / "ui" / "apps" / "registry" / "mod.rs"

OLD = '''                        if matches!(action.as_deref(), Some("LOAD")) {
                            let path = Self::resolve_local_gguf(&rec.manifest).ok_or_else(|| {
                                color_eyre::eyre::eyre!(
                                    "Model is not downloaded as a resolvable GGUF file: {}",
                                    model_id
                                )
                            })?;

                            tokio::task::block_in_place(|| {
                                tokio::runtime::Handle::current().block_on(state.Core_engine.load_model(path))
                            })
                            .map_err(|error| color_eyre::eyre::eyre!(error))?;

                            state._active_model_id = Some(model_id.clone());
                            state.Core_engine.is_loaded.store(
                                true,
                                std::sync::atomic::Ordering::SeqCst,
                            );
                            history_segment = Some(format!("{} ❯ loaded", name.dimmed()));
'''

NEW = '''                        if matches!(action.as_deref(), Some("LOAD")) {
                            let architecture = rec.manifest.architecture.to_ascii_lowercase();
                            if architecture.contains("bitnet") || architecture.contains("1.58") {
                                println!(
                                    "\\n  {} {}",
                                    "⚠️".yellow(),
                                    "This BitNet model requires a dedicated BitNet kernel and cannot be loaded through the GGUF llama backend yet.".bold()
                                );
                                std::thread::sleep(std::time::Duration::from_millis(1800));
                                history_segment = Some(format!("{} ❯ unsupported kernel", name.dimmed()));
                                Self::refresh_models(state);
                                continue;
                            }

                            let Some(path) = Self::resolve_local_gguf(&rec.manifest) else {
                                println!(
                                    "\\n  {} Model is not available as a local GGUF file: {}",
                                    "⚠️".yellow(),
                                    model_id
                                );
                                std::thread::sleep(std::time::Duration::from_millis(1500));
                                history_segment = Some(format!("{} ❯ missing GGUF", name.dimmed()));
                                Self::refresh_models(state);
                                continue;
                            };

                            let load_result = tokio::task::block_in_place(|| {
                                tokio::runtime::Handle::current().block_on(state.Core_engine.load_model(path))
                            });

                            match load_result {
                                Ok(()) => {
                                    state._active_model_id = Some(model_id.clone());
                                    state.Core_engine.is_loaded.store(
                                        true,
                                        std::sync::atomic::Ordering::SeqCst,
                                    );
                                    history_segment = Some(format!("{} ❯ loaded", name.dimmed()));
                                }
                                Err(error) => {
                                    state.Core_engine.is_loaded.store(
                                        false,
                                        std::sync::atomic::Ordering::SeqCst,
                                    );
                                    println!(
                                        "\\n  {} Model load failed without terminating BitShit: {}",
                                        "❌".red(),
                                        error
                                    );
                                    std::thread::sleep(std::time::Duration::from_millis(1800));
                                    history_segment = Some(format!("{} ❯ load failed", name.dimmed()));
                                }
                            }
'''

source = REGISTRY.read_text(encoding="utf-8")
if NEW in source:
    print("Model Hub load guard already applied.")
    raise SystemExit(0)
if OLD not in source:
    print("Model Hub source layout changed; load guard was not applied.")
    raise SystemExit(0)
REGISTRY.write_text(source.replace(OLD, NEW, 1), encoding="utf-8")
print("Applied Model Hub kernel guard and non-fatal load handling.")
