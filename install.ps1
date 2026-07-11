param(
    [ValidateSet('auto','cpu','cuda')]
    [string]$Backend = 'auto',
    [switch]$Yes,
    [switch]$NoLegacyAlias
)

$ErrorActionPreference = 'Stop'
$Repo = 'https://github.com/eyshoit-commits/bitshit.cpu.git'
$HomeDir = if ($env:BITSHIT_HOME) { $env:BITSHIT_HOME } else { Join-Path $HOME '.bitshit' }
$SourceDir = if ($env:BITSHIT_SOURCE_DIR) { $env:BITSHIT_SOURCE_DIR } else { Join-Path $HomeDir 'source' }
$BinDir = if ($env:BITSHIT_INSTALL_DIR) { $env:BITSHIT_INSTALL_DIR } else { Join-Path $HomeDir 'bin' }
$Profile = if ($env:BITSHIT_PROFILE) { $env:BITSHIT_PROFILE } else { 'release' }

function Write-Step([string]$Message) { Write-Host "[bitshit] $Message" -ForegroundColor Cyan }
function Fail([string]$Message) { throw "[bitshit] $Message" }
function Need([string]$Command) {
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) { Fail "Missing required command: $Command" }
}

Need git
Need cargo
Need rustc
Need cmake

$HasCuda = [bool](Get-Command nvidia-smi -ErrorAction SilentlyContinue)
if ($Backend -eq 'auto') { $Backend = if ($HasCuda) { 'cuda' } else { 'cpu' } }

if (-not $Yes) {
    Write-Host "Detected backend: $Backend"
    Write-Host '1) Auto  2) CPU only  3) NVIDIA CUDA'
    $Choice = Read-Host 'Select backend'
    switch ($Choice) {
        '2' { $Backend = 'cpu' }
        '3' { $Backend = 'cuda' }
        default { $Backend = if ($HasCuda) { 'cuda' } else { 'cpu' } }
    }
}

if ($Backend -eq 'cuda' -and -not $HasCuda) { Fail 'CUDA selected but nvidia-smi was not detected.' }

New-Item -ItemType Directory -Force -Path $HomeDir, $BinDir | Out-Null
if (Test-Path (Join-Path $SourceDir '.git')) {
    Write-Step 'Updating source checkout'
    git -C $SourceDir fetch --all --prune
    git -C $SourceDir reset --hard origin/main
} else {
    if (Test-Path $SourceDir) { Remove-Item -Recurse -Force $SourceDir }
    Write-Step 'Cloning BitShit'
    git clone --recurse-submodules $Repo $SourceDir
}

git -C $SourceDir submodule update --init --recursive
$env:BITSHIT_HOME = $HomeDir
$env:CLUAIZ_HOME = $HomeDir
$env:GGML_CUDA = if ($Backend -eq 'cuda') { 'ON' } else { 'OFF' }
$env:GGML_HIPBLAS = 'OFF'
$env:GGML_METAL = 'OFF'

Write-Step "Building backend=$Backend profile=$Profile"
Push-Location $SourceDir
try {
    cargo build --locked --profile $Profile -p cmd --bin bitshit
} finally {
    Pop-Location
}

$Built = Join-Path $SourceDir "target\$Profile\bitshit.exe"
if (-not (Test-Path $Built)) { Fail "Build completed without producing $Built" }
$Target = Join-Path $BinDir 'bitshit.exe'
Copy-Item -Force $Built $Target

if (-not $NoLegacyAlias) {
    Copy-Item -Force $Built (Join-Path $BinDir 'cluaiz.exe')
}

@{
    product = 'bitshit'
    backend = $Backend
    profile = $Profile
    binary = $Target
    source = $SourceDir
} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $HomeDir 'install.json')

$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($UserPath -notlike "*$BinDir*") {
    [Environment]::SetEnvironmentVariable('Path', ($UserPath.TrimEnd(';') + ';' + $BinDir), 'User')
}

Write-Step "Installed $Target"
& $Target --version
