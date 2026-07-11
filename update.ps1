param(
    [ValidateSet('cuda','cpu','auto')]
    [string]$Backend = 'cuda',
    [switch]$NoMigrate,
    [switch]$NoLegacyAlias
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step([string]$Message) {
    Write-Host "[bitshit-update] $Message" -ForegroundColor Cyan
}

function Fail([string]$Message) {
    throw "[bitshit-update] $Message"
}

if (-not (Test-Path (Join-Path $RepoRoot '.git'))) {
    Fail 'Dieses Skript muss direkt aus dem geklonten 1bitshit.auto-Repository gestartet werden.'
}

Write-Step 'BitShit Windows Update startet.'
Write-Step 'Hole den aktuellen Stand von GitHub.'

git -C $RepoRoot fetch origin --prune
if ($LASTEXITCODE -ne 0) { Fail 'Git fetch ist fehlgeschlagen.' }

git -C $RepoRoot checkout -q main
if ($LASTEXITCODE -ne 0) { Fail 'Wechsel auf main ist fehlgeschlagen.' }

git -C $RepoRoot reset --hard origin/main
if ($LASTEXITCODE -ne 0) { Fail 'Aktualisierung auf origin/main ist fehlgeschlagen.' }

Write-Step "Verwende Backend: $Backend"
$Installer = Join-Path $RepoRoot 'install.ps1'
if (-not (Test-Path $Installer)) { Fail 'install.ps1 wurde nicht gefunden.' }

$Arguments = @('-Backend', $Backend, '-Yes')
if ($NoMigrate) { $Arguments += '-NoMigrate' }
if ($NoLegacyAlias) { $Arguments += '-NoLegacyAlias' }

Write-Step 'Starte Aktualisierung und Neuinstallation.'
& $Installer @Arguments
if ($LASTEXITCODE -ne 0) { Fail "Installation ist mit Exitcode $LASTEXITCODE fehlgeschlagen." }

Write-Step 'Windows Update und Installation abgeschlossen.'
