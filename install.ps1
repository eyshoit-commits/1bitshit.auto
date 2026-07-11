param(
    [ValidateSet('auto','cpu','cuda')]
    [string]$Backend = 'auto',
    [switch]$Yes,
    [switch]$NoLegacyAlias,
    [switch]$NoMigrate
)

$ErrorActionPreference = 'Stop'
$Repo = 'https://github.com/eyshoit-commits/bitshit.cpu.git'
$HomeDir = if ($env:BITSHIT_HOME) { $env:BITSHIT_HOME } else { Join-Path $HOME '.bitshit' }
$LegacyHome = if ($env:CLUAIZ_HOME) { $env:CLUAIZ_HOME } else { Join-Path $HOME '.cluaiz' }
$SourceDir = if ($env:BITSHIT_SOURCE_DIR) { $env:BITSHIT_SOURCE_DIR } else { Join-Path $HomeDir 'source' }
$BinDir = if ($env:BITSHIT_INSTALL_DIR) { $env:BITSHIT_INSTALL_DIR } else { Join-Path $HomeDir 'bin' }
$Profile = if ($env:BITSHIT_PROFILE) { $env:BITSHIT_PROFILE } else { 'release' }
$MigrationMarker = Join-Path $HomeDir '.migrated-from-cluaiz'

function Write-Step([string]$Message) { Write-Host "[bitshit] $Message" -ForegroundColor Cyan }
function Fail([string]$Message) { throw "[bitshit] $Message" }
function Need([string]$Command) {
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) { Fail "Missing required command: $Command" }
}

function Migrate-LegacyData {
    if ($NoMigrate -or $LegacyHome -eq $HomeDir -or -not (Test-Path $LegacyHome) -or (Test-Path $MigrationMarker)) {
        return
    }

    Write-Step "Migrating legacy data from $LegacyHome"
    New-Item -ItemType Directory -Force -Path $HomeDir | Out-Null
    $legacyRoot = (Resolve-Path $LegacyHome).Path.TrimEnd('\')

    Get-ChildItem -LiteralPath $LegacyHome -Force -Recurse | ForEach-Object {
        $relative = $_.FullName.Substring($legacyRoot.Length).TrimStart('\')
        $target = Join-Path $HomeDir $relative

        if ($_.PSIsContainer) {
            New-Item -ItemType Directory -Force -Path $target | Out-Null
        } elseif (-not (Test-Path -LiteralPath $target)) {
            $parent = Split-Path -Parent $target
            if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
            Copy-Item -LiteralPath $_.FullName -Destination $target
        }
    }

    @(
        "source=$LegacyHome"
        "migrated_at=$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
    ) | Set-Content -Encoding UTF8 $MigrationMarker
    Write-Step 'Legacy data copied; original remains untouched'
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

Migrate-LegacyData
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
$env:CLUAIZ_HOME = $HomeDir # temporary internal compatibility during crate migration
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
    legacy_data_source = $LegacyHome
} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $HomeDir 'install.json')

$UserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($UserPath -notlike "*$BinDir*") {
    $prefix = if ([string]::IsNullOrWhiteSpace($UserPath)) { '' } else { $UserPath.TrimEnd(';') + ';' }
    [Environment]::SetEnvironmentVariable('Path', ($prefix + $BinDir), 'User')
}

Write-Step "Installed $Target"
& $Target --version
