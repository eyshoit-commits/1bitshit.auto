# BitShit Windows updater entry point.
# Accepts PowerShell-style, GNU-style, and positional backend syntax.

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

$Backend = 'auto'
$NoLegacyAlias = $false
$NoMigrate = $false
$NoLaunch = $false

for ($i = 0; $i -lt $args.Count; $i++) {
    $arg = [string]$args[$i]
    switch -Regex ($arg) {
        '^(?i)--?backend$' {
            if ($i + 1 -ge $args.Count) {
                throw 'FEHLER: Nach --backend fehlt der Wert auto, cpu oder cuda.'
            }
            $i++
            $Backend = ([string]$args[$i]).ToLowerInvariant()
            continue
        }
        '^(?i)--?backend=(auto|cpu|cuda)$' {
            $Backend = $Matches[1].ToLowerInvariant()
            continue
        }
        '^(?i)--?no-legacy-alias$' {
            $NoLegacyAlias = $true
            continue
        }
        '^(?i)--?no-migrate$' {
            $NoMigrate = $true
            continue
        }
        '^(?i)--?no-launch$' {
            $NoLaunch = $true
            continue
        }
        '^(?i)(auto|cpu|cuda)$' {
            $Backend = $Matches[1].ToLowerInvariant()
            continue
        }
        '^(?i)--?yes$' {
            # Updates are always non-interactive; retain this flag for CLI symmetry.
            continue
        }
        default {
            throw "FEHLER: Unbekanntes Update-Argument: $arg"
        }
    }
}

if ($Backend -notin @('auto', 'cpu', 'cuda')) {
    throw "FEHLER: Ungültiges Backend '$Backend'. Erlaubt sind auto, cpu oder cuda."
}

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
function Say([string]$Message) { Write-Host $Message }
function Fail([string]$Message) { throw "FEHLER: $Message" }

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
    git switch main
    if ($LASTEXITCODE -ne 0) { Fail 'Wechsel auf main ist fehlgeschlagen.' }
} elseif ($CurrentBranch -ne 'main') {
    Say "Wechsle von Branch $CurrentBranch auf main."
    git switch main
    if ($LASTEXITCODE -ne 0) { Fail 'Wechsel auf main ist fehlgeschlagen.' }
}

git reset --hard origin/main
if ($LASTEXITCODE -ne 0) { Fail 'Aktualisierung auf origin/main ist fehlgeschlagen.' }

$Installer = Join-Path $RepoRoot 'scripts\setup-windows.ps1'
if (-not (Test-Path $Installer)) {
    Fail 'scripts\setup-windows.ps1 fehlt im Repository.'
}

$Forward = @{
    Backend = $Backend
    Yes = $true
}
if ($NoLegacyAlias) { $Forward.NoLegacyAlias = $true }
if ($NoMigrate) { $Forward.NoMigrate = $true }
if ($NoLaunch) { $Forward.NoLaunch = $true }

Say "Starte Aktualisierung und Neuinstallation über MSYS2 UCRT64 mit Backend $Backend."
& $Installer @Forward
if ($LASTEXITCODE -ne 0) {
    Fail "Installation ist mit Exitcode $LASTEXITCODE fehlgeschlagen."
}

Say 'BitShit Update abgeschlossen.'
