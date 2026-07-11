fn main() {
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

        let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap();
        let icon_path = std::path::Path::new(&manifest_dir)
            .parent()
            .unwrap()
            .join("assets")
            .join("logo.ico");
        res.set_icon(icon_path.to_str().unwrap());

        if let Err(e) = res.compile() {
            eprintln!("Failed to compile Windows resources: {}", e);
        }
    }
}
