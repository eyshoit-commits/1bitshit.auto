param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Pass([string]$Message) { Write-Host "[PASS] $Message" -ForegroundColor Green }
function Info([string]$Message) { Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Fail([string]$Message) { throw "[FAIL] $Message" }

function Require-Command([string]$Name) {
    $Command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $Command) { Fail "Befehl fehlt: $Name" }
    Pass "$Name gefunden: $($Command.Source)"
}

Info 'Pruefe Windows CUDA Umgebung fuer 1BitShit.'

if ($env:OS -ne 'Windows_NT') { Fail 'Dieses Skript muss unter Windows laufen.' }
Pass 'Windows erkannt.'

Require-Command git
Require-Command cargo
Require-Command rustc
Require-Command cmake
Require-Command nvidia-smi
Require-Command nvcc

$HasMsvc = [bool](Get-Command cl.exe -ErrorAction SilentlyContinue)
$HasClang = [bool](Get-Command clang-cl.exe -ErrorAction SilentlyContinue)
if (-not $HasMsvc -and -not $HasClang) {
    Fail 'Kein Windows C++ Compiler gefunden. Starte eine Visual Studio Developer PowerShell oder installiere Desktop development with C++.'
}
Pass 'Windows C++ Compiler gefunden.'

Info 'NVIDIA Treiberstatus:'
nvidia-smi
if ($LASTEXITCODE -ne 0) { Fail 'nvidia-smi ist fehlgeschlagen.' }

Info 'CUDA Compilerstatus:'
nvcc --version
if ($LASTEXITCODE -ne 0) { Fail 'nvcc ist fehlgeschlagen.' }

Push-Location $RepoRoot
try {
    Info 'Pruefe Cargo Workspace Metadaten.'
    cargo metadata --no-deps --format-version 1 | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail 'Cargo Workspace Metadaten sind ungueltig.' }
    Pass 'Cargo Workspace Metadaten sind gueltig.'

    if (-not $SkipBuild) {
        $env:BITSHIT_HOME = if ($env:BITSHIT_HOME) { $env:BITSHIT_HOME } else { Join-Path $HOME '.bitshit' }
        $env:CLUAIZ_HOME = $env:BITSHIT_HOME
        $env:GGML_CUDA = 'ON'
        $env:GGML_HIPBLAS = 'OFF'
        $env:GGML_METAL = 'OFF'

        if (-not (Test-Path 'Cargo.lock')) {
            Info 'Cargo.lock fehlt. Erzeuge Lockfile.'
            cargo generate-lockfile
            if ($LASTEXITCODE -ne 0) { Fail 'Cargo Lockfile konnte nicht erzeugt werden.' }
        }

        Info 'Baue BitShit mit CUDA im Release-Profil.'
        cargo build --locked --release -p cmd --bin bitshit
        if ($LASTEXITCODE -ne 0) { Fail 'CUDA Build ist fehlgeschlagen.' }

        $Binary = Join-Path $RepoRoot 'target\release\bitshit.exe'
        if (-not (Test-Path $Binary)) { Fail "Build meldete Erfolg, aber $Binary fehlt." }
        Pass "CUDA Binary gebaut: $Binary"

        & $Binary --version
        if ($LASTEXITCODE -ne 0) { Fail 'Die gebaute Binary besteht den Versionstest nicht.' }
        Pass 'Versionstest bestanden.'
    }
} finally {
    Pop-Location
}

Pass 'Windows CUDA Test abgeschlossen.'
