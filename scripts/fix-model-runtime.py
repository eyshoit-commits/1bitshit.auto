#!/usr/bin/env python3
"""Apply the model-runtime fixes required by the BitShit source build.

The migration is intentionally strict and idempotent. It edits only exact known
source blocks and refuses to continue when the expected code is not present.
"""
from __future__ import annotations

from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
PULL = ROOT / "cmd" / "src" / "cli" / "pull.rs"
ENVIRONMENT = ROOT / "Inference-engine" / "engines" / "cluaiz-shared" / "src" / "environment" / "mod.rs"
MODEL_ROOT = ROOT / "models" / "dl"


def replace_once(path: Path, old: str, new: str) -> bool:
    source = path.read_text(encoding="utf-8")
    if new in source:
        return False
    if old not in source:
        raise RuntimeError(f"Expected source block not found in {path}")
    path.write_text(source.replace(old, new, 1), encoding="utf-8")
    return True


def migrate_legacy_models() -> None:
    MODEL_ROOT.mkdir(parents=True, exist_ok=True)
    legacy = Path.home() / ".cluaiz" / "models"
    if not legacy.is_dir():
        return

    for item in legacy.iterdir():
        target = MODEL_ROOT / item.name
        if target.exists():
            continue
        try:
            shutil.move(str(item), str(target))
            print(f"Moved legacy model data: {item} -> {target}")
        except OSError:
            if item.is_dir():
                shutil.copytree(item, target)
            else:
                shutil.copy2(item, target)
            print(f"Copied legacy model data: {item} -> {target}")


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
        """    pub fn models_dir(&self) -> PathBuf {\n        if let Ok(path) = std::env::var(\"BITSHIT_MODELS_DIR\") {\n            return PathBuf::from(path);\n        }\n\n        // Development and source installations keep large model files visible\n        // inside the repository instead of hiding them below ~/.cluaiz.\n        let current = std::env::current_dir().unwrap_or_else(|_| PathBuf::from(\".\"));\n        if current.join(\"Cargo.toml\").is_file() && current.join(\"models\").is_dir() {\n            return current.join(\"models\").join(\"dl\");\n        }\n\n        if let Some(home) = dirs::home_dir() {\n            let installed_source = home.join(\".bitshit\").join(\"source\");\n            if installed_source.join(\"Cargo.toml\").is_file() {\n                return installed_source.join(\"models\").join(\"dl\");\n            }\n        }\n\n        self.global_dir.join(\"models\").join(\"dl\")\n    }""",
    )

    migrate_legacy_models()
    print("BitShit model runtime paths are consistent." if changed else "BitShit model runtime fixes already applied.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Model runtime migration failed: {exc}", file=sys.stderr)
        raise SystemExit(2)
