param(
    [ValidateSet('auto','cpu','cuda')]
    [string]$Backend = 'auto',
    [switch]$Yes,
    [switch]$NoLegacyAlias,
    [switch]$NoMigrate
)

$ErrorActionPreference = 'Stop'
$Repo = 'https://github.com/eyshoit-commits/1bitshit.auto.git'
$HomeDir = if ($env:BITSHIT_HOME) { $env:BITSHIT_HOME } else { Join-Path $HOME '.bitshit' }
$LegacyHome = if ($env:CLUAIZ_HOME) { $env:CLUAIZ_HOME } else { Join-Path $HOME '.cluaiz' }
$SourceDir = if ($env:BITSHIT_SOURCE_DIR) { $env:BITSHIT_SOURCE_DIR } else { Join-Path $HomeDir 'source' }
$BinDir = if ($env:BITSHIT_INSTALL_DIR) { $env:BITSHIT_INSTALL_DIR } else { Join-Path $HomeDir 'bin' }
$Profile = if ($env:BITSHIT_PROFILE) { $env:BITSHIT_PROFILE } else { 'release' }
$TargetProfileDir = if ($Profile -eq 'dev') { 'debug' } else { $Profile }

function Step([string]$Message) { Write-Host "[bitshit] $Message" }
function Fail([string]$Message) { throw "[bitshit] $Message" }
function Need([string]$Command) { if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) { Fail "Missing required command: $Command" } }
function Has-Cuda { return [bool](Get-Command nvcc -ErrorAction SilentlyContinue) -and [bool](Get-Command nvidia-smi -ErrorAction SilentlyContinue) }

Need git
Need cargo
Need rustc
Need cmake
if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue) -and -not (Get-Command clang-cl.exe -ErrorAction SilentlyContinue)) {
    Fail 'Missing Windows C++ compiler. Run setup through install.sh from Git Bash or install Visual Studio Build Tools with Desktop development with C++.'
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

Step "Building backend=$Backend profile=$Profile"
Push-Location $SourceDir
try {
    if (Test-Path 'Cargo.lock') { cargo build --locked --profile $Profile -p cmd --bin bitshit }
    else { cargo generate-lockfile; if ($LASTEXITCODE -ne 0) { Fail 'Cargo lockfile generation failed.' }; cargo build --profile $Profile -p cmd --bin bitshit }
    if ($LASTEXITCODE -ne 0) { Fail "Cargo build failed with exit code $LASTEXITCODE." }
} finally { Pop-Location }

$Built = Join-Path $SourceDir "target\$TargetProfileDir\bitshit.exe"
if (-not (Test-Path $Built)) { Fail "Build completed without producing $Built" }
$Target = Join-Path $BinDir 'bitshit.exe'
Copy-Item -Force $Built $Target
if (-not $NoLegacyAlias) { Copy-Item -Force $Built (Join-Path $BinDir 'cluaiz.exe') }
@{ product='bitshit'; backend=$Backend; profile=$Profile; binary=$Target; source=$SourceDir } | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $HomeDir 'install.json')
Step "Installed $Target"
& $Target --version
