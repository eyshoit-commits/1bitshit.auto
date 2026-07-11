param(
    [Parameter(Position = 0)]
    [string]$Backend = 'cpu'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Profile = 'release'
$TargetBin = 'bitshit.exe'

function Say([string]$Message) { Write-Host $Message }
function Fail([string]$Message) { throw "FEHLER: $Message" }
function Need([string]$Command) {
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        Fail "$Command wurde nicht gefunden."
    }
}

if ($Backend -notin @('auto','cpu','cuda')) {
    Fail "Ungueltiges Backend: $Backend."
}

Set-Location $RepoRoot
Say 'BitShit Test startet.'
Say "Verwende Backend: $Backend"

Need git
Need cargo
Need rustc
Need cmake

if ($Backend -eq 'cuda') {
    Need nvcc
    Need nvidia-smi
}

$env:BITSHIT_HOME = if ($env:BITSHIT_HOME) { $env:BITSHIT_HOME } else { Join-Path $HOME '.bitshit' }
$env:CLUAIZ_HOME = $env:BITSHIT_HOME
$env:GGML_CUDA = 'OFF'
$env:GGML_HIPBLAS = 'OFF'
$env:GGML_METAL = 'OFF'

if ($Backend -eq 'cuda') {
    $env:GGML_CUDA = 'ON'
}

Say 'Pruefe Cargo Workspace.'
cargo metadata --no-deps --format-version 1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'Cargo Workspace ist ungueltig.' }

if (-not (Test-Path 'Cargo.lock')) {
    Say 'Cargo.lock fehlt. Erzeuge Lockfile.'
    cargo generate-lockfile
    if ($LASTEXITCODE -ne 0) { Fail 'Cargo Lockfile konnte nicht erzeugt werden.' }
}

Say 'Baue BitShit.'
cargo build --locked --release -p cmd --bin bitshit
if ($LASTEXITCODE -ne 0) { Fail 'BitShit Build ist fehlgeschlagen.' }

$Binary = Join-Path $RepoRoot "target\$Profile\$TargetBin"
if (-not (Test-Path $Binary)) { Fail "Binary fehlt: $Binary" }

Say 'Pruefe Binary.'
& $Binary --version
if ($LASTEXITCODE -ne 0) { Fail 'Binary-Pruefung ist fehlgeschlagen.' }

Say 'BitShit Test abgeschlossen.'
