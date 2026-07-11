param(
    [ValidateSet('auto','cpu','cuda')]
    [string]$Backend = 'auto',
    [switch]$Yes,
    [switch]$NoLegacyAlias,
    [switch]$NoMigrate,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
if ($env:OS -ne 'Windows_NT') { throw '[bitshit] scripts/app-windows.ps1 supports Windows only.' }

$Repo = 'https://github.com/eyshoit-commits/1bitshit.auto.git'
$HomeDir = if ($env:BITSHIT_HOME) { $env:BITSHIT_HOME } else { Join-Path $HOME '.bitshit' }
$InterimHome = if ($env:BITSHIT_INTERIM_HOME) { $env:BITSHIT_INTERIM_HOME } else { Join-Path $HOME '.1bitshit' }
$LegacyHome = if ($env:CLUAIZ_LEGACY_HOME) { $env:CLUAIZ_LEGACY_HOME } else { Join-Path $HOME '.cluaiz' }
$SourceDir = if ($env:BITSHIT_SOURCE_DIR) { $env:BITSHIT_SOURCE_DIR } else { Join-Path $HomeDir 'source' }
$BinDir = if ($env:BITSHIT_INSTALL_DIR) { $env:BITSHIT_INSTALL_DIR } else { Join-Path $HomeDir 'bin' }
$Profile = if ($env:BITSHIT_PROFILE) { $env:BITSHIT_PROFILE } else { 'release' }
$TargetProfileDir = if ($Profile -eq 'dev') { 'debug' } else { $Profile }
$RustTarget = 'x86_64-pc-windows-gnu'
$MsysRoot = if ($env:BITSHIT_MSYS2_ROOT) { $env:BITSHIT_MSYS2_ROOT } else { 'C:\msys64' }
$UcrtBin = Join-Path $MsysRoot 'ucrt64\bin'
$Cargo = Join-Path $UcrtBin 'cargo.exe'
$Rustc = Join-Path $UcrtBin 'rustc.exe'
$Python = Join-Path $UcrtBin 'python.exe'
$CMake = Join-Path $UcrtBin 'cmake.exe'
$Ninja = Join-Path $UcrtBin 'ninja.exe'
$Gcc = Join-Path $UcrtBin 'gcc.exe'
$Gxx = Join-Path $UcrtBin 'g++.exe'
$Ar = Join-Path $UcrtBin 'ar.exe'
$PkgConfig = Join-Path $UcrtBin 'pkg-config.exe'

function Step([string]$Message) { Write-Host "[bitshit] $Message" }
function Fail([string]$Message) { throw "[bitshit] $Message" }
function Require-File([string]$Path) { if (-not (Test-Path $Path)) { Fail "Missing required tool: $Path" } }
function Has-Cuda { return [bool](Get-Command nvcc.exe -ErrorAction SilentlyContinue) -and [bool](Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue) }

function Copy-MissingTree([string]$Source, [string]$MarkerName) {
    if ([string]::IsNullOrWhiteSpace($Source) -or $Source -eq $HomeDir -or -not (Test-Path $Source)) { return }

    $Marker = Join-Path $HomeDir $MarkerName
    if (Test-Path $Marker) { return }

    Step "Migrating missing data from $Source to $HomeDir"
    New-Item -ItemType Directory -Force -Path $HomeDir | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        $Destination = Join-Path $HomeDir $_.Name
        if (-not (Test-Path -LiteralPath $Destination)) {
            Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
        }
    }

    @(
        "source=$Source"
        "target=$HomeDir"
        "migrated_at=$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
        'mode=copy-missing'
    ) | Set-Content -Encoding UTF8 $Marker
}

$MachinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
$UserPath = [Environment]::GetEnvironmentVariable('Path','User')
$env:Path = "$UcrtBin;$MsysRoot\usr\bin;$MachinePath;$UserPath"

foreach ($Tool in @($Cargo,$Rustc,$Python,$CMake,$Ninja,$Gcc,$Gxx,$Ar,$PkgConfig)) {
    Require-File $Tool
}

$env:CC = $Gcc
$env:CXX = $Gxx
$env:AR = $Ar
$env:CMAKE_GENERATOR = 'Ninja'
$env:CMAKE_MAKE_PROGRAM = $Ninja
$env:CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER = $Gcc
$env:CARGO_TARGET_X86_64_PC_WINDOWS_GNU_AR = $Ar
$env:PKG_CONFIG = $PkgConfig
$env:PKG_CONFIG_PATH = "$MsysRoot\ucrt64\lib\pkgconfig;$MsysRoot\ucrt64\share\pkgconfig"
$env:OPENSSL_DIR = "$MsysRoot\ucrt64"
$env:OPENSSL_LIB_DIR = "$MsysRoot\ucrt64\lib"
$env:OPENSSL_INCLUDE_DIR = "$MsysRoot\ucrt64\include"

$HostTriple = (& $Rustc -vV | Select-String '^host:' | ForEach-Object { $_.Line.Split(':',2)[1].Trim() })
if ($HostTriple -ne 'x86_64-pc-windows-gnu') {
    Fail "Wrong Rust host selected: $HostTriple. Expected x86_64-pc-windows-gnu from $Rustc"
}

$HasCuda = Has-Cuda
if ($Backend -eq 'auto') { $Backend = if ($HasCuda) { 'cuda' } else { 'cpu' } }
if (-not $Yes) {
    Write-Host "Detected backend: $Backend"
    Write-Host '1) Auto  2) CPU only  3) NVIDIA CUDA'
    $Choice = Read-Host 'Select backend'
    switch ($Choice) { '2' { $Backend = 'cpu' }; '3' { $Backend = 'cuda' }; default { $Backend = if ($HasCuda) { 'cuda' } else { 'cpu' } } }
}
if ($Backend -eq 'cuda' -and -not (Has-Cuda)) { Fail 'CUDA selected but nvcc and nvidia-smi are required.' }

if (-not $NoMigrate) {
    # .1bitshit is newer than .cluaiz, so it receives first chance to populate
    # missing files. Existing canonical .bitshit data is never overwritten.
    Copy-MissingTree $InterimHome '.migrated-from-1bitshit'
    Copy-MissingTree $LegacyHome '.migrated-from-cluaiz'
}

New-Item -ItemType Directory -Force -Path $HomeDir, $BinDir | Out-Null
if (Test-Path (Join-Path $SourceDir '.git')) {
    Step 'Updating source checkout'
    git -C $SourceDir remote set-url origin $Repo
    git -C $SourceDir fetch origin --prune
    git -C $SourceDir checkout -q main
    git -C $SourceDir reset --hard origin/main
} else {
    if (Test-Path $SourceDir) { Remove-Item -Recurse -Force $SourceDir }
    Step 'Cloning BitShit'
    git clone --recurse-submodules $Repo $SourceDir
}
if ($LASTEXITCODE -ne 0) { Fail 'Repository checkout failed.' }

git -C $SourceDir submodule sync --recursive
git -C $SourceDir submodule update --init --recursive
$env:BITSHIT_HOME = $HomeDir
$env:BITSHIT_INTERIM_HOME = $InterimHome
$env:BITSHIT_MODELS_DIR = Join-Path $SourceDir 'models\dl'
$env:CLUAIZ_HOME = $HomeDir
$env:CLUAIZ_LEGACY_HOME = $LegacyHome
$env:GGML_CUDA = if ($Backend -eq 'cuda') { 'ON' } else { 'OFF' }
$env:GGML_HIPBLAS = 'OFF'
$env:GGML_METAL = 'OFF'
Remove-Item Env:CARGO_FEATURE_CUDA -ErrorAction SilentlyContinue
if ($Backend -eq 'cuda') { $env:CARGO_FEATURE_CUDA = '1' }

Step 'Applying public runtime and model-path migrations'
Push-Location $SourceDir
try {
    & $Python scripts/rebrand-main-cli.py
    if ($LASTEXITCODE -ne 0) { Fail "Runtime migration failed with exit code $LASTEXITCODE." }
    & $Python scripts/fix-model-runtime.py
    if ($LASTEXITCODE -ne 0) { Fail "Model runtime migration failed with exit code $LASTEXITCODE." }
} finally { Pop-Location }

Step "Building backend=$Backend profile=$Profile target=$RustTarget"
Push-Location $SourceDir
try {
    Step 'Refreshing Cargo.lock for the current workspace'
    & $Cargo generate-lockfile
    if ($LASTEXITCODE -ne 0) { Fail "Cargo lockfile generation failed with exit code $LASTEXITCODE." }
    & $Cargo build --locked --target $RustTarget --profile $Profile -p cmd --bin bitshit
    if ($LASTEXITCODE -ne 0) { Fail "Cargo build failed with exit code $LASTEXITCODE." }
} finally { Pop-Location }

$Built = Join-Path $SourceDir "target\$RustTarget\$TargetProfileDir\bitshit.exe"
if (-not (Test-Path $Built)) { Fail "Build completed without producing $Built" }
$Target = Join-Path $BinDir 'bitshit.exe'
Copy-Item -Force $Built $Target
if (-not $NoLegacyAlias) { Copy-Item -Force $Built (Join-Path $BinDir 'cluaiz.exe') }
@{
    product='bitshit'
    platform='windows'
    toolchain='msys2-ucrt64'
    rust_host=$HostTriple
    rust_target=$RustTarget
    backend=$Backend
    profile=$Profile
    binary=$Target
    source=$SourceDir
    runtime=$HomeDir
    interim_source=$InterimHome
    legacy_source=$LegacyHome
    migration_mode='copy-missing'
    models=$env:BITSHIT_MODELS_DIR
} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $HomeDir 'install.json')
Step "Installed $Target"
Step "Runtime synchronized to $HomeDir"
Step "Models stored in $env:BITSHIT_MODELS_DIR"
if (-not $NoLaunch) {
    & $Target --version
}
