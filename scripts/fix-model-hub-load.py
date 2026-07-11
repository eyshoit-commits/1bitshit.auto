#!/usr/bin/env python3
from pathlib import Path

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


changed = False

# Model Hub: keep native load failures non-fatal and never send BitNet to llama/GGUF.
OLD_REGISTRY = '''                        if matches!(action.as_deref(), Some("LOAD")) {
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
NEW_REGISTRY = '''                        if matches!(action.as_deref(), Some("LOAD")) {
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
changed |= replace_once(REGISTRY, OLD_REGISTRY, NEW_REGISTRY, "non-fatal model load guard")

# Details view: cached BitNet artifacts may be deletable, but are not loadable by the GGUF backend.
OLD_DETAILS = '''        if !rec.is_cached {
            options.push("📥  INITIATE DOWNLOAD".to_string());
            back_btn_idx = 1;
        } else {
            options.push("▶  LOAD / SWITCH MODEL".to_string());
            back_btn_idx = 1;
        }

        options.push("↩  BACK".to_string());
'''
NEW_DETAILS = '''        let architecture = rec.manifest.architecture.to_ascii_lowercase();
        let bitnet_requires_dedicated_kernel =
            architecture.contains("bitnet") || architecture.contains("1.58");

        if !rec.is_cached {
            options.push("📥  INITIATE DOWNLOAD".to_string());
            back_btn_idx = 1;
        } else if !bitnet_requires_dedicated_kernel {
            options.push("▶  LOAD / SWITCH MODEL".to_string());
            back_btn_idx = 1;
        } else {
            println!("  {} Dedicated BitNet kernel is not available yet; this artifact cannot be loaded by the GGUF backend.", "⚠️".yellow());
            lines_printed += 1;
        }

        options.push("↩  BACK".to_string());
'''
changed |= replace_once(DETAILS, OLD_DETAILS, NEW_DETAILS, "BitNet Model Hub action guard")

# Dashboard boot fallback: only consider a concrete GGUF file. A directory or BitNet cache is not a model.
OLD_BOOT_FALLBACK = '''                boot_target = state.sorted_models.iter().find(|m| {
                    m.is_cached && m.manifest.category != "embedding" && m.manifest.architecture_type != "onnx"
                }).map(|m| (m.manifest.name.clone(), m.manifest.local_path.clone()));
'''
NEW_BOOT_FALLBACK = '''                boot_target = state.sorted_models.iter().find(|m| {
                    let architecture = m.manifest.architecture.to_ascii_lowercase();
                    let is_bitnet = architecture.contains("bitnet") || architecture.contains("1.58");
                    let has_real_gguf = m.manifest.local_path.as_ref().map(|path| {
                        let path = std::path::Path::new(path);
                        path.is_file()
                            && path.extension()
                                .and_then(|value| value.to_str())
                                .map(|value| value.eq_ignore_ascii_case("gguf"))
                                .unwrap_or(false)
                    }).unwrap_or(false);
                    m.is_cached
                        && !is_bitnet
                        && has_real_gguf
                        && m.manifest.category != "embedding"
                        && m.manifest.architecture_type != "onnx"
                }).map(|m| (m.manifest.name.clone(), m.manifest.local_path.clone()));
'''
changed |= replace_once(DASHBOARD, OLD_BOOT_FALLBACK, NEW_BOOT_FALLBACK, "safe auto-boot candidate filter")

# Dashboard lazy load: validate both model architecture and actual file before calling native code.
OLD_LAZY_LOAD = '''                            if let Some(model_id) = state._active_model_id.clone() {
                                if let Some(model) = state.sorted_models.iter().find(|m| m.manifest.id == model_id) {
                                    if let Some(local_path) = &model.manifest.local_path {
                                        let path = std::path::PathBuf::from(local_path);
                                        let is_gguf = path.extension().and_then(|s| s.to_str()) == Some("gguf");
                                        let runtime = if is_gguf {
                                            cluaiz_shared::BackendType::RuntimeB
                                        } else {
                                            cluaiz_shared::BackendType::RuntimeA
                                        };
                                        let rt = tokio::runtime::Handle::current();
                                        let load_res = tokio::task::block_in_place(|| {
                                            rt.block_on(state.Core_engine.load_model(path))
                                        });
                                        if load_res.is_ok() {
                                            state.Core_engine.is_loaded.store(true, Ordering::SeqCst);
                                        }
                                    }
                                }
                            }
'''
NEW_LAZY_LOAD = '''                            if let Some(model_id) = state._active_model_id.clone() {
                                if let Some(model) = state.sorted_models.iter().find(|m| m.manifest.id == model_id) {
                                    let architecture = model.manifest.architecture.to_ascii_lowercase();
                                    let is_bitnet = architecture.contains("bitnet") || architecture.contains("1.58");
                                    if let Some(local_path) = &model.manifest.local_path {
                                        let path = std::path::PathBuf::from(local_path);
                                        let is_gguf = path.is_file()
                                            && path.extension()
                                                .and_then(|value| value.to_str())
                                                .map(|value| value.eq_ignore_ascii_case("gguf"))
                                                .unwrap_or(false);
                                        if !is_bitnet && is_gguf {
                                            let rt = tokio::runtime::Handle::current();
                                            let load_res = tokio::task::block_in_place(|| {
                                                rt.block_on(state.Core_engine.load_model(path))
                                            });
                                            state.Core_engine.is_loaded.store(load_res.is_ok(), Ordering::SeqCst);
                                        } else {
                                            state.Core_engine.is_loaded.store(false, Ordering::SeqCst);
                                            state._active_model_id = None;
                                            println!("  {} Active model has no loadable GGUF weights. Select or download a GGUF model from the Model Hub.", "⚠️".yellow());
                                        }
                                    } else {
                                        state._active_model_id = None;
                                    }
                                } else {
                                    state._active_model_id = None;
                                }
                            }
'''
changed |= replace_once(DASHBOARD, OLD_LAZY_LOAD, NEW_LAZY_LOAD, "safe dashboard lazy-load validation")

if changed:
    print("Applied Model Hub and dashboard model-loading safety fixes.")
else:
    print("Model Hub and dashboard model-loading safety fixes are already current or superseded.")
