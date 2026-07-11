param(
    [Parameter(Position = 0)]
    [string]$Backend = ''
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BitShitHome = if ($env:BITSHIT_HOME) { $env:BITSHIT_HOME } else { Join-Path $HOME '.bitshit' }
$InstallState = Join-Path $BitShitHome 'install.json'

function Say([string]$Message) {
    Write-Host $Message
}

function Fail([string]$Message) {
    throw "FEHLER: $Message"
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Fail 'git wurde nicht gefunden.'
}

Set-Location $RepoRoot

Say 'BitShit Update startet.'
Say 'Hole den aktuellen Stand von GitHub.'

git fetch origin --prune
if ($LASTEXITCODE -ne 0) { Fail 'Git fetch ist fehlgeschlagen.' }

$CurrentBranch = (git branch --show-current).Trim()
if ([string]::IsNullOrWhiteSpace($CurrentBranch)) {
    $CurrentBranch = 'main'
    git switch main
    if ($LASTEXITCODE -ne 0) { Fail 'Wechsel auf main ist fehlgeschlagen.' }
}

if ($CurrentBranch -ne 'main') {
    Say "Wechsle von Branch $CurrentBranch auf main."
    git switch main
    if ($LASTEXITCODE -ne 0) { Fail 'Wechsel auf main ist fehlgeschlagen.' }
}

git reset --hard origin/main
if ($LASTEXITCODE -ne 0) { Fail 'Aktualisierung auf origin/main ist fehlgeschlagen.' }

if ([string]::IsNullOrWhiteSpace($Backend) -and (Test-Path $InstallState)) {
    try {
        $SavedBackend = (Get-Content -Raw $InstallState | ConvertFrom-Json).backend
        if ($SavedBackend -in @('auto','cpu','cuda')) {
            $Backend = $SavedBackend
        }
    } catch {
        $Backend = ''
    }
}

if ([string]::IsNullOrWhiteSpace($Backend)) {
    $Backend = 'cpu'
    Say 'Kein frueheres Backend gefunden. Verwende CPU.'
} else {
    Say "Verwende Backend: $Backend"
}

if ($Backend -notin @('auto','cpu','cuda')) {
    Fail "Ungueltiges Backend: $Backend. Erlaubt sind auto, cpu oder cuda."
}

$Installer = Join-Path $RepoRoot 'install.ps1'
if (-not (Test-Path $Installer)) {
    Fail 'install.ps1 fehlt im Repository.'
}

Say 'Starte Aktualisierung und Neuinstallation.'
& $Installer -Backend $Backend -Yes
if ($LASTEXITCODE -ne 0) {
    Fail "Installation ist mit Exitcode $LASTEXITCODE fehlgeschlagen."
}

Say 'BitShit Update abgeschlossen.'
