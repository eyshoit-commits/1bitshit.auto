param(
    [Parameter(Position = 0)]
    [ValidateSet('auto','cpu','cuda')]
    [string]$Backend = ''
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say([string]$Message) { Write-Host $Message }
function Fail([string]$Message) { throw "FEHLER: $Message" }
function Has([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
function Install-Winget([string]$Id, [string[]]$ExtraArgs = @()) {
    Say "Installiere $Id."
    $Args = @('install','--id',$Id,'--exact','--accept-package-agreements','--accept-source-agreements','--silent') + $ExtraArgs
    & winget @Args
    if ($LASTEXITCODE -ne 0) { Fail "winget konnte $Id nicht installieren." }
}

Say 'BitShit Windows Umgebungs-Setup startet.'

if (-not (Has 'winget')) {
    Fail 'winget fehlt. Installiere App Installer aus dem Microsoft Store und starte das Skript erneut.'
}

if (-not (Has 'git')) {
    Install-Winget 'Git.Git'
}
if (-not (Has 'cmake')) {
    Install-Winget 'Kitware.CMake'
}
if (-not (Has 'cargo') -or -not (Has 'rustc')) {
    Install-Winget 'Rustlang.Rustup'
}

$HasMsvc = (Has 'cl.exe')
$HasClang = (Has 'clang-cl.exe')
if (-not $HasMsvc -and -not $HasClang) {
    $BuildToolsArgs = @(
        '--override',
        '--wait --quiet --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    )
    Install-Winget 'Microsoft.VisualStudio.2022.BuildTools' $BuildToolsArgs
}

$ResolvedBackend = $Backend
if ([string]::IsNullOrWhiteSpace($ResolvedBackend)) {
    $ResolvedBackend = 'auto'
}

if ($ResolvedBackend -eq 'cuda' -or $ResolvedBackend -eq 'auto') {
    $HasCuda = (Has 'nvcc') -and (Has 'nvidia-smi')
    if (-not $HasCuda -and $ResolvedBackend -eq 'cuda') {
        Install-Winget 'Nvidia.CUDA'
    }
}

$MachinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
$UserPath = [Environment]::GetEnvironmentVariable('Path','User')
$env:Path = "$MachinePath;$UserPath"

Say 'Umgebung installiert.'
Say 'Falls Visual Studio Build Tools oder CUDA gerade neu installiert wurden, schliesse dieses Fenster und oeffne PowerShell erneut.'

$Installer = Join-Path $RepoRoot 'install.ps1'
if (-not (Test-Path $Installer)) { Fail 'install.ps1 fehlt im Repository.' }

if ([string]::IsNullOrWhiteSpace($Backend)) {
    & $Installer
} else {
    & $Installer -Backend $Backend
}

if ($LASTEXITCODE -ne 0) {
    Fail "Installation ist mit Exitcode $LASTEXITCODE fehlgeschlagen."
}
