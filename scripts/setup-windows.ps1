param(
    [ValidateSet('auto','cpu','cuda')]
    [string]$Backend = 'auto',
    [switch]$Yes,
    [switch]$NoLegacyAlias,
    [switch]$NoMigrate
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw '[bitshit] setup-windows.ps1 ist nur fuer Windows.' }

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
function Has([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
function Install-Winget([string]$Id, [string[]]$ExtraArgs = @()) {
    Write-Host "[bitshit] Installiere $Id"
    $Args = @('install','--id',$Id,'--exact','--accept-package-agreements','--accept-source-agreements','--silent') + $ExtraArgs
    & winget @Args
    if ($LASTEXITCODE -ne 0) { throw "[bitshit] winget konnte $Id nicht installieren." }
}

if (-not (Has 'winget')) { throw '[bitshit] winget fehlt. Installiere App Installer aus dem Microsoft Store.' }
if (-not (Has 'git')) { Install-Winget 'Git.Git' }
if (-not (Has 'cmake')) { Install-Winget 'Kitware.CMake' }
if (-not (Has 'cargo') -or -not (Has 'rustc')) { Install-Winget 'Rustlang.Rustup' }

if (-not (Has 'cl.exe') -and -not (Has 'clang-cl.exe')) {
    Install-Winget 'Microsoft.VisualStudio.2022.BuildTools' @(
        '--override',
        '--wait --quiet --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
    )
}

if ($Backend -eq 'cuda' -and (-not (Has 'nvcc') -or -not (Has 'nvidia-smi'))) {
    Install-Winget 'Nvidia.CUDA'
}

$MachinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
$UserPath = [Environment]::GetEnvironmentVariable('Path','User')
$env:Path = "$MachinePath;$UserPath"

$App = Join-Path $RepoRoot 'scripts\app-windows.ps1'
$Args = @('-Backend', $Backend)
if ($Yes) { $Args += '-Yes' }
if ($NoLegacyAlias) { $Args += '-NoLegacyAlias' }
if ($NoMigrate) { $Args += '-NoMigrate' }
& $App @Args
if ($LASTEXITCODE -ne 0) { throw "[bitshit] Windows-Installation ist mit Exitcode $LASTEXITCODE fehlgeschlagen." }
