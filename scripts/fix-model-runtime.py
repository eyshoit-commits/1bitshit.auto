#!/usr/bin/env python3
"""Apply the model-runtime fixes required by the BitShit source build.

The migration is strict, idempotent, and non-destructive. Source patches are
applied only to exact known blocks. Legacy model data is copied only when the
target file does not already exist.
"""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
PULL = ROOT / "cmd" / "src" / "cli" / "pull.rs"
ENVIRONMENT = ROOT / "Inference-engine" / "engines" / "cluaiz-shared" / "src" / "environment" / "mod.rs"
DEFAULT_MODEL_ROOT = ROOT / "models" / "dl"


def replace_once(path: Path, old: str, new: str) -> bool:
    source = path.read_text(encoding="utf-8")
    if new in source:
        return False
    if old not in source:
        raise RuntimeError(f"Expected source block not found in {path}")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")
    return True


def copy_missing(source: Path, target: Path) -> int:
    """Copy missing files recursively without replacing newer BitShit data."""
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
    if configured:
        return Path(configured).expanduser()
    return Path.home() / ".cluaiz"


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
        PULL,
        """        let mut lock = state.Core_engine.router.lock().await;\n        lock.active_backend = engines::api::router::Backend::cluaiz(engine);\n    }\n    state._active_model_id = Some(manifest.id.clone());""",
        """        let mut lock = state.Core_engine.router.lock().await;\n        lock.active_backend = engines::api::router::Backend::cluaiz(engine);\n    }\n    // The GGUF engine is already instantiated above. Mark it loaded so the\n    // dashboard does not launch a second lazy-load pass with a directory path\n    // and accidentally route the GGUF file through the ONNX backend.\n    state.Core_engine.is_loaded.store(true, std::sync::atomic::Ordering::SeqCst);\n    state._active_model_id = Some(manifest.id.clone());""",
    )

    changed |= replace_once(
        ENVIRONMENT,
        """    pub fn models_dir(&self) -> PathBuf {\n        self.global_dir.join(\"models\")\n    }""",
        """    pub fn models_dir(&self) -> PathBuf {\n        if let Ok(path) = std::env::var(\"BITSHIT_MODELS_DIR\") {\n            return PathBuf::from(path);\n        }\n\n        // Development and source installations keep large model files visible\n        // inside the repository instead of hiding them below the runtime home.\n        let current = std::env::current_dir().unwrap_or_else(|_| PathBuf::from(\".\"));\n        if current.join(\"Cargo.toml\").is_file() && current.join(\"models\").is_dir() {\n            return current.join(\"models\").join(\"dl\");\n        }\n\n        if let Ok(home) = std::env::var(\"BITSHIT_HOME\") {\n            let installed_source = PathBuf::from(home).join(\"source\");\n            if installed_source.join(\"Cargo.toml\").is_file() {\n                return installed_source.join(\"models\").join(\"dl\");\n            }\n        }\n\n        if let Some(home) = dirs::home_dir() {\n            let installed_source = home.join(\".bitshit\").join(\"source\");\n            if installed_source.join(\"Cargo.toml\").is_file() {\n                return installed_source.join(\"models\").join(\"dl\");\n            }\n        }\n\n        self.global_dir.join(\"models\").join(\"dl\")\n    }""",
    )

    copied = migrate_legacy_models()
    if changed:
        print("BitShit model runtime paths are consistent.")
    elif copied:
        print("BitShit source patches were already applied; legacy models were copied.")
    else:
        print("BitShit model runtime fixes already applied.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Model runtime migration failed: {exc}", file=sys.stderr)
        raise SystemExit(2)
