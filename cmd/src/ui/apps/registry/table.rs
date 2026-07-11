use colored::Colorize;
use engines::ModelRecommendation;

pub struct ColumnWidths {
    pub name: usize,
    pub size: usize,
    pub ram: usize,
    pub params: usize,
    pub tokens: usize,
    pub ctx: usize,
    pub term_width: u16,
    pub show_tokens: bool,
    pub show_ctx: bool,
    pub show_params: bool,
}

impl ColumnWidths {
    pub fn compute(models: &[ModelRecommendation]) -> Self {
        let (term_width, _) = crossterm::terminal::size().unwrap_or((120, 40));

        let mut widths = Self {
            name: 24,
            size: 8,
            ram: 6,
            params: 10,
            tokens: 10,
            ctx: 8,
            term_width,
            show_tokens: term_width > 120,
            show_ctx: term_width > 140,
            show_params: term_width > 100,
        };

        for m in models {
            widths.name = widths.name.max(m.manifest.name.len());
            widths.size = widths
                .size
                .max(format!("{:.1} GB", m.manifest.download_size_gb).len());
            widths.ram = widths
                .ram
                .max(format!("{:.1} GB", m.manifest.ram_required_gb).len());
            widths.params = widths.params.max(m.manifest.parameters.len());
            widths.tokens = widths.tokens.max(m.manifest.training_tokens.len());
            widths.ctx = widths.ctx.max(m.manifest.context_window.len());
        }

        if term_width < 80 {
            widths.name = 20;
        }

        widths
    }
}

pub struct RegistryTable;

impl RegistryTable {
    pub fn get_header_string(w: &ColumnWidths) -> String {
        let mut header = format!(
            "  {:<2}  {:<name_w$}  {:<size_w$}  {:<ram_w$}",
            "ID",
            "MODEL NAME",
            "SIZE",
            "RAM",
            name_w = w.name,
            size_w = w.size,
            ram_w = w.ram
        );
        let mut sep = format!(
            "  {:-<2}  {:-<name_w$}  {:-<size_w$}  {:-<ram_w$}",
            "",
            "",
            "",
            "",
            name_w = w.name,
            size_w = w.size,
            ram_w = w.ram
        );

        if w.show_params {
            header.push_str(&format!("  {:<params_w$}", "PARAMS", params_w = w.params));
            sep.push_str(&format!("  {:-<params_w$}", "", params_w = w.params));
        }
        if w.show_tokens {
            header.push_str(&format!("  {:<tokens_w$}", "TOKENS", tokens_w = w.tokens));
            sep.push_str(&format!("  {:-<tokens_w$}", "", tokens_w = w.tokens));
        }
        if w.show_ctx {
            header.push_str(&format!("  {:<ctx_w$}", "CONTEXT", ctx_w = w.ctx));
            sep.push_str(&format!("  {:-<ctx_w$}", "", ctx_w = w.ctx));
        }

        header.push_str("  STATUS");
        sep.push_str("  ------------");

        format!("{}\n{}", header.cyan().bold(), sep.bright_black())
    }

    pub fn format_row(
        idx: usize,
        model: &ModelRecommendation,
        w: &ColumnWidths,
        hardware: &cluaiz_shared::hardware::schema::profiles::cluaizProfile,
    ) -> String {
        let size = format!("{:.1} GB", model.manifest.download_size_gb);
        let ram = format!("{:.1} GB", model.manifest.ram_required_gb);

        let mut name = model.manifest.name.clone();
        if name.len() > w.name {
            name.truncate(w.name.saturating_sub(3));
            name.push_str("...");
        }

        let mut row = format!(
            "{:02}  {:<name_w$}  {:<size_w$}  {:<ram_w$}",
            idx + 1,
            name,
            size,
            ram,
            name_w = w.name,
            size_w = w.size,
            ram_w = w.ram
        );

        if w.show_params {
            row.push_str(&format!(
                "  {:<params_w$}",
                model.manifest.parameters,
                params_w = w.params
            ));
        }
        if w.show_tokens {
            row.push_str(&format!(
                "  {:<tokens_w$}",
                model.manifest.training_tokens,
                tokens_w = w.tokens
            ));
        }
        if w.show_ctx {
            row.push_str(&format!(
                "  {:<ctx_w$}",
                model.manifest.context_window,
                ctx_w = w.ctx
            ));
        }

        let (dot, score, status) = Self::calculate_health(model, hardware);
        row.push_str(&format!("  {} {}", dot, status));

        if score == 0 {
            row.dimmed().to_string()
        } else {
            row
        }
    }

    pub fn calculate_health(
        model: &ModelRecommendation,
        hardware: &cluaiz_shared::hardware::schema::profiles::cluaizProfile,
    ) -> (colored::ColoredString, i32, String) {
        let report = cluaiz_shared::hardware::speed_checker::predict_performance(
            &model.manifest.parameters,
            model.manifest.bit_depth,
            &model.manifest.context_window,
            model.manifest.requires_gpu,
            hardware,
        );

        if report.status == cluaiz_shared::hardware::speed_checker::HealthStatus::Panic {
            return ("⚫ ".black(), 0, "incompatible".to_string());
        }

        if model.is_cached {
            return ("✔ ".green().bold(), 8, "downloaded".green().to_string());
        }

        use cluaiz_shared::hardware::speed_checker::HealthStatus;
        match report.status {
            HealthStatus::GodMode => ("🟣 ".magenta(), 7, "available".to_string()),
            HealthStatus::HyperSpeed => ("🔵 ".blue(), 6, "available".to_string()),
            HealthStatus::Instant => ("🟢 ".green(), 5, "available".to_string()),
            HealthStatus::Moderate => ("🟡 ".yellow(), 4, "available".to_string()),
            HealthStatus::Lagging => ("🟠 ".truecolor(255, 165, 0), 3, "slow".to_string()),
            HealthStatus::Critical => ("🔴 ".red(), 2, "critical".to_string()),
            HealthStatus::Panic => ("⚫ ".black(), 0, "incompatible".to_string()),
        }
    }
}
