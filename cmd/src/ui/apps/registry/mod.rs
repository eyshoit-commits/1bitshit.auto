use color_eyre::Result;
use tokio::sync::mpsc;
use engines::DownloadEvent;
use crate::core::state::AppState;
use inquire::{Select, Text, ui::{Attributes, RenderConfig, Styled, Color}};
use colored::Colorize;
use serde::Deserialize;
use std::collections::HashSet;
use std::io::Write;
use std::path::PathBuf;

pub mod table;
pub mod details;
use crate::ui::apps::registry::table::{RegistryTable, ColumnWidths};

const MODEL_LIBRARY_JSON: &str = include_str!("../../../../../models/library/catalog.json");
const ACTION_PULL_HF: &str = "⬇  Pull from Hugging Face";
const ACTION_MODEL_STORE: &str = "🏪  Browse Model Store";
const ACTION_CANCEL: &str = "↩  Cancel";

#[derive(Debug, Deserialize)]
struct ModelLibrary {
    models: Vec<ModelStoreEntry>,
}

#[derive(Debug, Deserialize)]
struct ModelStoreEntry {
    name: String,
    repo: String,
    category: String,
    description: String,
}

pub struct RegistryApp;

impl RegistryApp {
    fn resolve_local_gguf(manifest: &engines::models::registry::ModelManifest) -> Option<PathBuf> {
        let mut candidates = Vec::new();

        if let Some(local_path) = &manifest.local_path {
            candidates.push(PathBuf::from(local_path));
        }

        if let Some(cached) = engines::models::fetch::ModelDownloader::get_cached_path(
            &manifest.category,
            &manifest.id,
            &manifest.huggingface_filename,
        ) {
            candidates.push(cached);
        }

        for mut path in candidates {
            if path.is_dir() {
                path = path.join(&manifest.huggingface_filename);
            }
            if path.is_file()
                && path
                    .extension()
                    .and_then(|value| value.to_str())
                    .map(|value| value.eq_ignore_ascii_case("gguf"))
                    .unwrap_or(false)
            {
                return Some(path);
            }
        }

        None
    }

    fn refresh_models(state: &mut AppState) {
        let mut seen = HashSet::new();
        let mut models = engines::CoreRoster::get_recommendations(
            &state.hardware.to_hardware_truth(),
            state.ram_gb,
        );

        for model in &mut models {
            model.is_cached = Self::resolve_local_gguf(&model.manifest).is_some();
        }

        models.retain(|model| {
            let key = format!(
                "{}|{}|{}",
                model.manifest.id.to_ascii_lowercase(),
                model.manifest.huggingface_repo.to_ascii_lowercase(),
                model.manifest.huggingface_filename.to_ascii_lowercase(),
            );
            seen.insert(key)
        });

        models.sort_by(|a, b| {
            let (_, score_a, _) = RegistryTable::calculate_health(a, &state.hardware);
            let (_, score_b, _) = RegistryTable::calculate_health(b, &state.hardware);
            score_b
                .cmp(&score_a)
                .then_with(|| a.manifest.name.cmp(&b.manifest.name))
        });

        state.sorted_models = models;
    }

    fn run_pull(repo_id: String) -> Result<()> {
        let repo_id = repo_id.trim().to_string();
        if repo_id.is_empty() {
            return Ok(());
        }

        tokio::task::block_in_place(|| {
            tokio::runtime::Handle::current()
                .block_on(crate::cli::pull::execute(&repo_id))
        })
    }

    fn pull_from_hugging_face() -> Result<()> {
        let repo_id = Text::new("Hugging Face repository:")
            .with_placeholder("owner/model-GGUF")
            .prompt()?;
        Self::run_pull(repo_id)
    }

    fn browse_model_store() -> Result<()> {
        let library: ModelLibrary = serde_json::from_str(MODEL_LIBRARY_JSON)
            .map_err(|error| color_eyre::eyre::eyre!("Invalid models/library/catalog.json: {}", error))?;

        if library.models.is_empty() {
            println!("  {} Model Store is empty.", "⚠️".yellow());
            return Ok(());
        }

        let mut choices: Vec<String> = library.models.iter()
            .map(|entry| {
                format!(
                    "{}  [{}]  {}  —  {}",
                    entry.name,
                    entry.category,
                    entry.repo,
                    entry.description
                )
            })
            .collect();
        choices.push(ACTION_CANCEL.to_string());

        let selection = Select::new("Model Store:", choices)
            .with_page_size(15)
            .prompt()?;

        if selection == ACTION_CANCEL {
            return Ok(());
        }

        let entry = library.models.iter()
            .find(|entry| selection.contains(&entry.repo))
            .ok_or_else(|| color_eyre::eyre::eyre!("Selected Model Store entry could not be resolved."))?;

        Self::run_pull(entry.repo.clone())
    }

    pub fn show(state: &mut AppState, tx: &mpsc::UnboundedSender<DownloadEvent>) -> Result<()> {
        Self::refresh_models(state);

        let total_ram = state.ram_gb;
        let mut history_segment: Option<String> = None;
        let base_path = format!("{} ❯ {}", "🏠︎".dimmed(), "Model Hub".dimmed());

        loop {
            let widths = ColumnWidths::compute(&state.sorted_models);
            let table_header = RegistryTable::get_header_string(&widths);
            let current_crumb = if let Some(ref seg) = history_segment {
                format!("{} ❯ {}", base_path, seg)
            } else {
                base_path.clone()
            };

            println!("{}", current_crumb);
            println!("{}", table_header);

            let mut choices = vec![
                ACTION_PULL_HF.to_string(),
                ACTION_MODEL_STORE.to_string(),
            ];
            choices.extend(
                state.sorted_models.iter().enumerate()
                    .map(|(i, model)| RegistryTable::format_row(i, model, &widths, &state.hardware))
            );
            choices.push(ACTION_CANCEL.to_string());

            let config = RenderConfig::default()
                .with_prompt_prefix(Styled::new("🔍 ").with_fg(Color::LightCyan))
                .with_answered_prompt_prefix(Styled::new("🔍 ").with_fg(Color::LightCyan))
                .with_highlighted_option_prefix(
                    Styled::new("➤")
                        .with_fg(Color::LightCyan)
                        .with_attr(Attributes::BOLD),
                );

            let ans = Select::new("Search:", choices)
                .with_page_size(15)
                .with_render_config(config)
                .prompt();

            match ans {
                Ok(ans) => {
                    if ans == ACTION_CANCEL {
                        for _ in 0..3 { print!("\x1B[1A\x1B[2K\r"); }
                        println!("{} {}", "↩".dimmed(), "Back".dimmed());
                        let _ = std::io::stdout().flush();
                        return Ok(());
                    }

                    if ans == ACTION_PULL_HF {
                        Self::pull_from_hugging_face()?;
                        Self::refresh_models(state);
                        history_segment = Some("Hugging Face".dimmed().to_string());
                        continue;
                    }

                    if ans == ACTION_MODEL_STORE {
                        Self::browse_model_store()?;
                        Self::refresh_models(state);
                        history_segment = Some("Model Store".dimmed().to_string());
                        continue;
                    }

                    let idx_str = ans.split_whitespace().next().unwrap_or("0").trim();
                    let idx = idx_str.parse::<usize>().unwrap_or(1).saturating_sub(1);

                    if let Some(rec) = state.sorted_models.get_mut(idx) {
                        let name = rec.manifest.name.clone();
                        let (_, score, _) = RegistryTable::calculate_health(rec, &state.hardware);

                        if score == 0 {
                            println!("\n  {} {}", "⚪".white(), "Action Blocked: Model incompatible with hardware.".bold());
                            std::thread::sleep(std::time::Duration::from_millis(1200));
                            for _ in 0..5 { print!("\x1B[1A\x1B[2K\r"); }
                            continue;
                        }

                        for _ in 0..4 { print!("\x1B[1A\x1B[2K\r"); }
                        let _ = std::io::stdout().flush();

                        let model_id = rec.manifest.id.clone();
                        let action = details::show_details(idx, rec, total_ram, &base_path, tx)?;

                        if matches!(action.as_deref(), Some("LOAD")) {
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
                        } else if matches!(action.as_deref(), Some("DELETE")) {
                            history_segment = Some(format!("{} ❯ {} {}", name.dimmed(), "🗑️".dimmed(), "Deleted".dimmed()));
                        } else {
                            history_segment = Some(name.dimmed().to_string());
                        }

                        Self::refresh_models(state);
                    }
                }
                Err(_) => {
                    for _ in 0..3 { print!("\x1B[1A\x1B[2K\r"); }
                    println!("{} {}", "↩".dimmed(), "Back".dimmed());
                    let _ = std::io::stdout().flush();
                    break;
                }
            }
        }

        Ok(())
    }
}
