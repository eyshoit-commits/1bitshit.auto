#!/usr/bin/env python3
"""Apply model-runtime fixes required by every BitShit source build.

The migration is idempotent and tolerant of already-modernized source. It keeps
model files visible under models/dl, prevents duplicate ONNX lazy-loads after a
successful GGUF handshake, removes invented TPS projections, wires Model Hub
switching to concrete local GGUF files, and routes the main-menu Model Hub entry
to the real registry instead of an immediate Hugging Face prompt.
"""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
PULL = ROOT / "cmd" / "src" / "cli" / "pull.rs"
DETAILS = ROOT / "cmd" / "src" / "ui" / "apps" / "registry" / "details.rs"
REGISTRY = ROOT / "cmd" / "src" / "ui" / "apps" / "registry" / "mod.rs"
MENU = ROOT / "cmd" / "src" / "ui" / "menu.rs"
ENVIRONMENT = ROOT / "Inference-engine" / "engines" / "cluaiz-shared" / "src" / "environment" / "mod.rs"
DEFAULT_MODEL_ROOT = ROOT / "models" / "dl"


def replace_once(path: Path, old: str, new: str) -> bool:
    source = path.read_text(encoding="utf-8")
    if new in source:
        return False
    if old not in source:
        print(f"Source layout already changed; skipped historical patch in {path.relative_to(ROOT)}")
        return False
    path.write_text(source.replace(old, new, 1), encoding="utf-8")
    return True


def copy_missing(source: Path, target: Path) -> int:
    copied = 0
    if source.is_dir():
        target.mkdir(parents=True, exist_ok=True)
        for child in source.iterdir():
            copied += copy_missing(child, target / child.name)
        return copied
    if target.exists():
        return 0
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    return 1


def model_root() -> Path:
    configured = os.environ.get("BITSHIT_MODELS_DIR")
    return Path(configured).expanduser() if configured else DEFAULT_MODEL_ROOT


def legacy_home() -> Path:
    configured = os.environ.get("CLUAIZ_LEGACY_HOME")
    return Path(configured).expanduser() if configured else Path.home() / ".cluaiz"


def migrate_legacy_models() -> int:
    target_root = model_root()
    source_root = legacy_home() / "models"
    target_root.mkdir(parents=True, exist_ok=True)
    try:
        if not source_root.is_dir() or source_root.resolve() == target_root.resolve():
            return 0
    except FileNotFoundError:
        return 0
    copied = copy_missing(source_root, target_root)
    if copied:
        print(f"Copied {copied} legacy model file(s): {source_root} -> {target_root}")
    return copied


def main() -> int:
    changed = False

    changed |= replace_once(
        MENU,
        '''            "🧠 Model Hub" => {
                let m_opts = vec!["⬇️ Pull New Model", "🗑️ Delete Downloaded Model", "🔙 Back"];
                if let Ok(m_ans) = Select::new("Model Hub:", m_opts).with_render_config(config.clone()).prompt() {
                    print!("\\x1B[1A\\x1B[2K\\r"); stdout().flush()?;
                    match m_ans {
                        "⬇️ Pull New Model" => {
                            if let Ok(id) = inquire::Text::new("Enter Model ID to Pull:").prompt() {
                                let _ = crate::cli::pull::execute(&id).await;
                            }
                        }
                        "🗑️ Delete Downloaded Model" => {
                            let roster = engines::models::registry::CoreRoster::load_roster();
                            let mut downloaded: Vec<_> = roster.into_iter().filter(|m| {
                                m.local_path.is_some() || engines::models::fetch::ModelDownloader::get_cached_path(&m.category, &m.id, &m.huggingface_filename).is_some()
                            }).collect();
                            
                            downloaded.sort_by(|a, b| a.name.cmp(&b.name));
                            downloaded.dedup_by(|a, b| a.name == b.name);
                            
                            if downloaded.is_empty() {
                                println!("  {} No downloaded models found.", "ℹ️".blue());
                                std::thread::sleep(std::time::Duration::from_secs(2));
                            } else {
                                let options: Vec<String> = downloaded.iter().map(|m| format!("{} [{}]", m.name, m.architecture_type)).collect();
                                if let Ok(ans) = Select::new("Select Model to Delete:", options).with_render_config(config.clone()).prompt() {
                                    if let Some(model) = downloaded.iter().find(|m| format!("{} [{}]", m.name, m.architecture_type) == ans) {
                                        let _ = crate::cli::rm::execute(&model.id).await;
                                    }
                                }
                            }
                        }
                        _ => {}
                    }
                }
            }''',
        '''            "🧠 Model Hub" => {
                // Open the real model registry. Hugging Face input is offered
                // only after the user explicitly selects Pull from Hugging Face.
                crate::ui::apps::registry::RegistryApp::show(state, tx)?;
            }''',
    )

    changed |= replace_once(
        PULL,
        '''        let mut lock = state.Core_engine.router.lock().await;
        lock.active_backend = engines::api::router::Backend::cluaiz(engine);
    }
    state._active_model_id = Some(manifest.id.clone());''',
        '''        let mut lock = state.Core_engine.router.lock().await;
        lock.active_backend = engines::api::router::Backend::cluaiz(engine);
    }
    state.Core_engine.is_loaded.store(true, std::sync::atomic::Ordering::SeqCst);
    state._active_model_id = Some(manifest.id.clone());''',
    )

    changed |= replace_once(
        PULL,
        '''    let projected_tps;
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
    );''',
        '''    if user_vram > 0.0 {
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

    println!("    ├─ 🚀 Measured Speed: unavailable until real generation");''',
    )

    changed |= replace_once(
        DETAILS,
        '''        if !rec.is_cached {
            options.push("📥  INITIATE DOWNLOAD".to_string());
            back_btn_idx = 1;
        }

        options.push("↩  BACK".to_string());

        if rec.is_cached {
            options.push(format!("{}", "🗑️  DELETE MODEL".red().bold()));
        }''',
        '''        if !rec.is_cached {
            options.push("📥  INITIATE DOWNLOAD".to_string());
            back_btn_idx = 1;
        } else {
            options.push("▶  LOAD / SWITCH MODEL".to_string());
            back_btn_idx = 1;
        }

        options.push("↩  BACK".to_string());

        if rec.is_cached {
            options.push(format!("{}", "🗑️  DELETE MODEL".red().bold()));
        }''',
    )

    changed |= replace_once(
        DETAILS,
        '''                } else if choice.contains("DELETE") {''',
        '''                } else if choice.contains("LOAD / SWITCH MODEL") {
                    for _ in 0..lines_printed + 3 {
                        print!("\\x1B[1A\\x1B[2K\\r");
                    }
                    let _ = stdout().flush();
                    return Ok(Some("LOAD".to_string()));
                } else if choice.contains("DELETE") {''',
    )

    changed |= replace_once(
        ENVIRONMENT,
        '''    pub fn models_dir(&self) -> PathBuf {
        self.global_dir.join("models")
    }''',
        '''    pub fn models_dir(&self) -> PathBuf {
        if let Ok(path) = std::env::var("BITSHIT_MODELS_DIR") {
            return PathBuf::from(path);
        }
        let current = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        if current.join("Cargo.toml").is_file() && current.join("models").is_dir() {
            return current.join("models").join("dl");
        }
        if let Ok(home) = std::env::var("BITSHIT_HOME") {
            let installed_source = PathBuf::from(home).join("source");
            if installed_source.join("Cargo.toml").is_file() {
                return installed_source.join("models").join("dl");
            }
        }
        if let Some(home) = dirs::home_dir() {
            let installed_source = home.join(".bitshit").join("source");
            if installed_source.join("Cargo.toml").is_file() {
                return installed_source.join("models").join("dl");
            }
        }
        self.global_dir.join("models").join("dl")
    }''',
    )

    copied = migrate_legacy_models()
    if changed:
        print("BitShit model runtime source was updated.")
    elif copied:
        print("BitShit source was already current; legacy models were copied.")
    else:
        print("BitShit model runtime is current or already superseded by newer source code.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Model runtime migration failed: {exc}", file=sys.stderr)
        raise SystemExit(2)
