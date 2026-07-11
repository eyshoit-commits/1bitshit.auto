param(
    [ValidateSet('auto','cpu','cuda')]
    [string]$Backend = 'auto',
    [switch]$Yes,
    [switch]$NoLegacyAlias,
    [switch]$NoMigrate
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
if ($env:OS -ne 'Windows_NT') { throw '[bitshit] scripts/app-windows.ps1 supports Windows only.' }

$Repo = 'https://github.com/eyshoit-commits/1bitshit.auto.git'
$HomeDir = if ($env:BITSHIT_HOME) { $env:BITSHIT_HOME } else { Join-Path $HOME '.bitshit' }
$SourceDir = if ($env:BITSHIT_SOURCE_DIR) { $env:BITSHIT_SOURCE_DIR } else { Join-Path $HomeDir 'source' }
$BinDir = if ($env:BITSHIT_INSTALL_DIR) { $env:BITSHIT_INSTALL_DIR } else { Join-Path $HomeDir 'bin' }
$Profile = if ($env:BITSHIT_PROFILE) { $env:BITSHIT_PROFILE } else { 'release' }
$TargetProfileDir = if ($Profile -eq 'dev') { 'debug' } else { $Profile }
$RustTarget = 'x86_64-pc-windows-gnu'
$MsysRoot = if ($env:BITSHIT_MSYS2_ROOT) { $env:BITSHIT_MSYS2_ROOT } else { 'C:\msys64' }
$UcrtBin = Join-Path $MsysRoot 'ucrt64\bin'

function Step([string]$Message) { Write-Host "[bitshit] $Message" }
function Fail([string]$Message) { throw "[bitshit] $Message" }
function Need([string]$Command) { if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) { Fail "Missing required command: $Command" } }
function Has-Cuda { return [bool](Get-Command nvcc.exe -ErrorAction SilentlyContinue) -and [bool](Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue) }

$MachinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
$UserPath = [Environment]::GetEnvironmentVariable('Path','User')
$env:Path = "$UcrtBin;$MsysRoot\usr\bin;$MachinePath;$UserPath"

Need git
Need cargo
Need rustc
Need python.exe
Need cmake.exe
Need ninja.exe
Need gcc.exe
Need g++.exe

$env:CC = Join-Path $UcrtBin 'gcc.exe'
$env:CXX = Join-Path $UcrtBin 'g++.exe'
$env:AR = Join-Path $UcrtBin 'ar.exe'
$env:CMAKE_GENERATOR = 'Ninja'
$env:CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER = Join-Path $UcrtBin 'gcc.exe'
$env:CARGO_TARGET_X86_64_PC_WINDOWS_GNU_AR = Join-Path $UcrtBin 'ar.exe'

$HasCuda = Has-Cuda
if ($Backend -eq 'auto') { $Backend = if ($HasCuda) { 'cuda' } else { 'cpu' } }
if (-not $Yes) {
    Write-Host "Detected backend: $Backend"
    Write-Host '1) Auto  2) CPU only  3) NVIDIA CUDA'
    $Choice = Read-Host 'Select backend'
    switch ($Choice) { '2' { $Backend = 'cpu' }; '3' { $Backend = 'cuda' }; default { $Backend = if ($HasCuda) { 'cuda' } else { 'cpu' } } }
}
if ($Backend -eq 'cuda' -and -not (Has-Cuda)) { Fail 'CUDA selected but nvcc and nvidia-smi are required.' }

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
$env:CLUAIZ_HOME = $HomeDir
$env:GGML_CUDA = if ($Backend -eq 'cuda') { 'ON' } else { 'OFF' }
$env:GGML_HIPBLAS = 'OFF'
$env:GGML_METAL = 'OFF'
Remove-Item Env:CARGO_FEATURE_CUDA -ErrorAction SilentlyContinue
if ($Backend -eq 'cuda') { $env:CARGO_FEATURE_CUDA = '1' }

Step 'Applying public runtime migration'
Push-Location $SourceDir
try {
    & python.exe scripts/rebrand-main-cli.py
    if ($LASTEXITCODE -ne 0) { Fail "Runtime migration failed with exit code $LASTEXITCODE." }
} finally { Pop-Location }

Step "Building backend=$Backend profile=$Profile target=$RustTarget"
Push-Location $SourceDir
try {
    if (-not (Test-Path 'Cargo.lock')) { cargo generate-lockfile }
    cargo build --locked --target $RustTarget --profile $Profile -p cmd --bin bitshit
    if ($LASTEXITCODE -ne 0) { Fail "Cargo build failed with exit code $LASTEXITCODE." }
} finally { Pop-Location }

$Built = Join-Path $SourceDir "target\$RustTarget\$TargetProfileDir\bitshit.exe"
if (-not (Test-Path $Built)) { Fail "Build completed without producing $Built" }
$Target = Join-Path $BinDir 'bitshit.exe'
Copy-Item -Force $Built $Target
if (-not $NoLegacyAlias) { Copy-Item -Force $Built (Join-Path $BinDir 'cluaiz.exe') }
@{ product='bitshit'; platform='windows'; toolchain='msys2-ucrt64'; rust_target=$RustTarget; backend=$Backend; profile=$Profile; binary=$Target; source=$SourceDir } | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $HomeDir 'install.json')
Step "Installed $Target"
& $Target --version
