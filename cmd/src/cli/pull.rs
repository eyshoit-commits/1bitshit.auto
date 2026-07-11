use color_eyre::Result;
use colored::Colorize;
use engines::models::registry::CoreRoster;
use sysinfo::System;

/// `bitshit pull <model-id>` — pulls a GGUF model and initiates a native chat session.
pub async fn execute(model_id: &str) -> Result<()> {
    let model_id = model_id.trim();
    if model_id.is_empty() {
        return Err(color_eyre::eyre::eyre!(
            "Model ID must not be empty. Example: bitshit pull owner/model-GGUF"
        ));
    }

    let logo = crate::assets::logos::logo_gallery::LOGO_VARIANTS[9];
    println!("{}", logo.cyan());
    println!(
        "\n  {} [bitshit] Initializing kernel for '{}'...",
        "⚙️".yellow(),
        model_id.bold()
    );

    let mut manifest: Option<engines::models::registry::ModelManifest> = None;
    let mut resolved_id = model_id.to_string();
    if !resolved_id.starts_with("hf://")
        && !resolved_id.starts_with("https://")
        && resolved_id.contains('/')
    {
        resolved_id = format!("hf://{}", resolved_id);
    }

    if resolved_id.starts_with("hf://")
        || resolved_id.starts_with("https://huggingface.co/")
    {
        let repo_id = resolved_id
            .replace("hf://", "")
            .replace("https://huggingface.co/", "");
        let repo_id = repo_id.trim_end_matches('/').to_string();

        println!(
            "  {} Scanning HuggingFace Hub for '{}'...",
            "🔍".cyan(),
            repo_id
        );

        let variants = engines::models::manager::hf_hub::HuggingFaceHub::list_variants(&repo_id)
            .await
            .map_err(|e| color_eyre::eyre::eyre!(e))?;

        let options: Vec<String> = variants
            .iter()
            .map(|v| format!("{} ({:.2} GB)", v.filename, v.size_gb))
            .collect();
        let selection = inquire::Select::new("Select GGUF variant to download:", options)
            .prompt()
            .map_err(|e| color_eyre::eyre::eyre!("Selection cancelled: {}", e))?;

        let selected_filename = selection
            .split(" (")
            .next()
            .ok_or_else(|| color_eyre::eyre::eyre!("Invalid model selection"))?
            .to_string();

        if !selected_filename.to_ascii_lowercase().ends_with(".gguf") {
            return Err(color_eyre::eyre::eyre!(
                "Selected file '{}' is not a GGUF model.",
                selected_filename
            ));
        }

        let roster = engines::models::registry::CoreRoster::load_roster();
        if let Some(existing) = roster.iter().find(|m| {
            m.huggingface_repo.eq_ignore_ascii_case(&repo_id)
                && m.huggingface_filename
                    .eq_ignore_ascii_case(&selected_filename)
        }) {
            println!(
                "\n  {} Warning: This exact variant is already downloaded locally under ID: '{}'",
                "⚠️".yellow(),
                existing.id.cyan()
            );
            println!(
                "     Delete it first with: bitshit rm {}\n",
                existing.id.red()
            );
            return Ok(());
        }

        let selected_size_str = selection
            .split(" (")
            .nth(1)
            .unwrap_or("0 GB)")
            .replace(" GB)", "");
        let selected_size_gb: f64 = selected_size_str.parse().unwrap_or(0.0);

        println!("  {} Fetching precise metadata...", "📡".cyan());
        manifest = Some(
            engines::models::manager::hf_hub::HuggingFaceHub::build_manifest(
                &repo_id,
                &selected_filename,
                selected_size_gb,
            )
            .await
            .map_err(|e| color_eyre::eyre::eyre!(e))?,
        );
    } else {
        let roster = CoreRoster::load_roster();
        manifest = roster
            .into_iter()
            .find(|m| m.id.eq_ignore_ascii_case(model_id));

        if manifest.is_none() {
            println!(
                "  {} Model missing in local vault. Synchronizing with Neural Registry...",
                "🌐".yellow()
            );
            let remote_models = CoreRoster::fetch_external_registry(None)
                .await
                .map_err(|e| color_eyre::eyre::eyre!(e))?;
            manifest = remote_models
                .into_iter()
                .find(|m| m.id.eq_ignore_ascii_case(model_id));
        }
    }

    let mut manifest = manifest.ok_or_else(|| {
        color_eyre::eyre::eyre!("ID '{}' not found in any registry.", model_id)
    })?;

    let cached_path = engines::models::fetch::ModelDownloader::get_cached_path(
        &manifest.category,
        &manifest.id,
        &manifest.huggingface_filename,
    );
    if cached_path.is_some() {
        println!(
            "\n  {} Warning: Model '{}' is already downloaded locally.",
            "⚠️".yellow(),
            manifest.id.cyan()
        );
        println!("     Delete it first with: bitshit rm {}\n", manifest.id.red());
        return Ok(());
    }

    let bitshit_root = cluaiz_shared::environment::EnvironmentManager::current()
        .ensure_models_dir()
        .unwrap_or_else(|_| {
            cluaiz_shared::environment::EnvironmentManager::current().models_dir()
        });
    let manager = engines::models::manager::ModelManager::new(
        engines::models::registry::REGISTRY_URL.to_string(),
        bitshit_root.clone(),
    );

    println!("  {} Fetching Deep Metadata (GGUF Binary Probe)...", "📡".cyan());
    match engines::models::manager::hf_hub::HuggingFaceHub::fetch_partial_gguf_metadata(
        &manifest.download_url,
    )
    .await
    {
        Ok((metadata, _tensor_infos, tensor_count)) => {
            let arch = metadata
                .get("general.architecture")
                .cloned()
                .unwrap_or_else(|| "Unknown".to_string());
            let ctx = metadata
                .get(&format!("{}.context_length", arch))
                .or_else(|| metadata.get("llama.context_length"))
                .cloned()
                .unwrap_or_else(|| "Unknown".to_string());
            let ctx_display = ctx
                .parse::<u32>()
                .map(|value| {
                    if value >= 1024 {
                        format!("{} ({}K)", value, value / 1024)
                    } else {
                        value.to_string()
                    }
                })
                .unwrap_or_else(|_| ctx.clone());
            let params = metadata
                .get("general.parameter_count")
                .cloned()
                .unwrap_or_else(|| "Unknown".to_string());
            let file_type = metadata
                .get("general.file_type")
                .cloned()
                .unwrap_or_else(|| "Unknown".to_string());
            let blocks = metadata
                .get(&format!("{}.block_count", arch))
                .cloned()
                .unwrap_or_else(|| "Unknown".to_string());

            let num_layers = blocks.parse::<u64>().unwrap_or(32);
            let num_heads = metadata
                .get(&format!("{}.attention.head_count", arch))
                .and_then(|s| s.parse::<u64>().ok())
                .unwrap_or(32);
            let num_kv_heads = metadata
                .get(&format!("{}.attention.head_count_kv", arch))
                .and_then(|s| s.parse::<u64>().ok())
                .unwrap_or(num_heads);
            let hidden_size = metadata
                .get(&format!("{}.embedding_length", arch))
                .and_then(|s| s.parse::<u64>().ok())
                .unwrap_or(4096);
            let head_dim = hidden_size / num_heads.max(1);
            let kv_cache_bytes = 2_u64
                * 2
                * num_layers
                * num_kv_heads
                * head_dim
                * 8192;
            let kv_cache_gb = kv_cache_bytes as f64 / 1024_f64.powi(3);
            let base_engine_overhead_gb = 0.30;
            manifest.ram_required_gb =
                manifest.download_size_gb + base_engine_overhead_gb + kv_cache_gb;

            println!("    ├─ 🧠 Architecture: {}", arch.yellow());
            println!("    ├─ 📏 Context Window: {} tokens", ctx_display.green());
            println!("    ├─ 🧩 Parameters: {} B", params.green());
            println!("    ├─ 📦 Quantization / File Type: {}", file_type.cyan());
            println!("    ├─ 📚 Network Layers (Blocks): {}", blocks.magenta());
            println!("    ├─ ⚡ Tensor Count: {}", tensor_count.to_string().cyan());
            println!("    ├─ 💾 Download Size: {:.2} GB", manifest.download_size_gb);
            println!("    ├─ 🧮 KV Cache (8K tokens): {:.2} GB", kv_cache_gb);
            println!("    ├─ ⚙️ Base Engine Overhead: {:.2} GB", base_engine_overhead_gb);
        }
        Err(error) => {
            println!("    ├─ ⚠️ Could not probe remote GGUF header: {}", error);
            println!("    ├─ 💾 Download Size: {:.2} GB", manifest.download_size_gb);
        }
    }

    println!("\n  {} Conducting Pre-flight Silicon Audit...", "⚖️".cyan());

    let config_path = cluaiz_shared::hardware::governor::HardwareGovernor::resolve_engine_path()
        .join("system_control.json");
    let system_control = std::fs::read_to_string(config_path)
        .ok()
        .and_then(|content| {
            serde_json::from_str::<cluaiz_shared::hardware::schema::profiles::SystemControl>(
                &content,
            )
            .ok()
        });

    let (mut user_ram, mut user_vram) = (0.0_f64, 0.0_f64);
    if let Some(control) = &system_control {
        user_ram = control.silicon_truth.memory.total_capacity_gb;
        user_vram = control
            .silicon_truth
            .accelerators
            .gpus
            .first()
            .map(|gpu| gpu.vram_available_gb)
            .unwrap_or(0.0);
    }

    if !user_ram.is_finite() || user_ram <= 0.0 {
        let mut system = System::new();
        system.refresh_memory();
        user_ram = system.total_memory() as f64 / 1024_f64.powi(3);
        if user_ram > 0.0 {
            println!(
                "    ├─ ℹ️ Stored RAM profile was invalid; live system memory was used."
            );
        }
    }

    if !user_ram.is_finite() || user_ram <= 0.0 {
        return Err(color_eyre::eyre::eyre!(
            "Hardware audit failed: total system RAM could not be detected. Run `bitshit calibrate` and retry."
        ));
    }

    println!("    ├─ 🖥️ Host System RAM: {:.2} GB", user_ram);
    if user_vram > 0.0 {
        println!("    ├─ 🎮 Target VRAM (Primary GPU): {:.2} GB", user_vram);
    }

    let total_required = manifest.ram_required_gb;
    println!(
        "    ├─ 📊 Target Allocation: {:.2} GB (Weights + Engine + 8K Context)",
        total_required
    );

    if manifest.bit_depth > 0.0 && manifest.bit_depth < 3.0 {
        println!(
            "\n  {} [Pre-flight Warning] Experimental low-bit quantization detected.",
            "⚠️".yellow()
        );
        println!("     Model bit depth: {:.2}", manifest.bit_depth);
    }

    let projected_tps;
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
    );

    if total_required > user_ram + user_vram {
        return Err(color_eyre::eyre::eyre!(
            "Insufficient memory: model requires {:.2} GB, but only {:.2} GB RAM and {:.2} GB VRAM were detected.",
            total_required,
            user_ram,
            user_vram
        ));
    }

    let status = manager.audit_model_health(total_required as f32, manifest.requires_gpu);
    println!("    ├─ System Status: {:?}", status);
    if status == engines::models::manager::auditor::HealthStatus::Disabled {
        return Err(color_eyre::eyre::eyre!(
            "DENIED: Insufficient hardware resources for this model."
        ));
    }

    let confirm = inquire::Confirm::new(
        "Audit passed. All metadata exposed. Proceed with model initialization?",
    )
    .with_default(true)
    .prompt()?;
    if !confirm {
        return Err(color_eyre::eyre::eyre!("Initialization aborted by user."));
    }

    if resolved_id.starts_with("hf://")
        || resolved_id.starts_with("https://huggingface.co/")
    {
        manager
            .pull_model_with_manifest(&manifest)
            .await
            .map_err(|e| color_eyre::eyre::eyre!(e))?;
        println!("\n  {} HuggingFace model downloaded successfully!", "✅".green());
    } else {
        manager
            .pull_model(&resolved_id)
            .await
            .map_err(|e| color_eyre::eyre::eyre!(e))?;
    }

    let safe_id = manifest.id.replace(':', "-");
    let model_path = bitshit_root.join(&manifest.category).join(&safe_id);
    let model_file = model_path.join(&manifest.huggingface_filename);
    if !model_file.exists() {
        return Err(color_eyre::eyre::eyre!(
            "Model file not found at: {:?}",
            model_file
        ));
    }

    let dna = cluaiz_shared::StructuralDNA::default();
    let context = cluaiz_shared::cluaizContext::boot(
        dna,
        cluaiz_shared::TemplateManager::default(),
    );
    let engine = engines::runtime::execution::hub::HardwareOrchestrator::instantiate(
        model_file
            .to_str()
            .ok_or_else(|| color_eyre::eyre::eyre!("Model path is not valid UTF-8"))?,
        "gguf",
        context,
    )
    .await
    .map_err(|e| color_eyre::eyre::eyre!(e))?;

    println!("  {} Handshake Success. Entering Dashboard...\n", "✅".green());

    use crate::core::state::AppState;
    use tokio::sync::mpsc;

    let mut state = AppState::new(None);
    {
        let mut lock = state.Core_engine.router.lock().await;
        lock.active_backend = engines::api::router::Backend::cluaiz(engine);
    }
    state._active_model_id = Some(manifest.id.clone());

    let (tx, mut rx) = mpsc::unbounded_channel();
    let mut mode = crate::app_enums::Mode::Running;
    crate::core::dashboard::DashboardEngine::run_native(
        &mut state,
        &tx,
        &mut rx,
        &mut mode,
    )?;

    Ok(())
}
