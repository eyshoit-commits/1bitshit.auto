param(
    [Parameter(Position = 0)]
    [string]$Backend = ''
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

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

$Installer = Join-Path $RepoRoot 'install.ps1'
if (-not (Test-Path $Installer)) {
    Fail 'install.ps1 fehlt im Repository.'
}

Say 'Starte Aktualisierung und Neuinstallation.'
if ([string]::IsNullOrWhiteSpace($Backend)) {
    & $Installer
} else {
    if ($Backend -notin @('auto','cpu','cuda')) {
        Fail "Ungueltiges Backend: $Backend. Erlaubt sind auto, cpu oder cuda."
    }
    Say "Verwende Backend: $Backend"
    & $Installer -Backend $Backend -Yes
}

if ($LASTEXITCODE -ne 0) {
    Fail "Installation ist mit Exitcode $LASTEXITCODE fehlgeschlagen."
}

Say 'BitShit Update abgeschlossen.'
