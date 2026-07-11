use std::path::Path;
use std::process::Command;

fn run_source_migration(repo_root: &Path, script: &str) {
    let script_path = repo_root.join("scripts").join(script);
    println!("cargo:rerun-if-changed={}", script_path.display());

    let candidates = if cfg!(windows) {
        ["python.exe", "python3.exe", "python"]
    } else {
        ["python3", "python", "python3"]
    };

    let mut last_error = None;
    for python in candidates {
        match Command::new(python)
            .arg(&script_path)
            .current_dir(repo_root)
            .status()
        {
            Ok(status) if status.success() => return,
            Ok(status) => {
                panic!(
                    "{} failed with exit code {:?}",
                    script_path.display(),
                    status.code()
                );
            }
            Err(error) => last_error = Some(error),
        }
    }

    panic!(
        "Could not run {}: no Python interpreter was available ({:?})",
        script_path.display(),
        last_error
    );
}

fn main() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR missing");
    let repo_root = Path::new(&manifest_dir)
        .parent()
        .expect("cmd must be inside the repository root");

    run_source_migration(repo_root, "rebrand-main-cli.py");
    run_source_migration(repo_root, "fix-model-runtime.py");

    println!("cargo:rerun-if-changed={}", repo_root.join("cmd/src/main.rs").display());
    println!("cargo:rerun-if-changed={}", repo_root.join("cmd/src/cli/pull.rs").display());

    #[cfg(windows)]
    {
        let mut res = winres::WindowsResource::new();
        res.set("InternalName", "bitshit.exe");
        res.set("FileDescription", "BitShit local neural runtime");
        res.set("ProductName", "BitShit");
        res.set("OriginalFilename", "bitshit.exe");
        res.set("LegalCopyright", "Copyright © 2026 BitShit Contributors");
        res.set("CompanyName", "BitShit Contributors");
        res.set("FileVersion", "0.1.0.0");
        res.set("ProductVersion", "0.1.0.0");

        res.set_manifest(
            r#"
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
<trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
        <requestedPrivileges>
            <requestedExecutionLevel level="asInvoker" uiAccess="false" />
        </requestedPrivileges>
    </security>
</trustInfo>
</assembly>
"#,
        );

        let icon_path = repo_root.join("assets").join("logo.ico");
        res.set_icon(icon_path.to_str().expect("icon path is not UTF-8"));

        if let Err(error) = res.compile() {
            eprintln!("Failed to compile Windows resources: {}", error);
        }
    }
}
