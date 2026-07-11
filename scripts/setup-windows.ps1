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
function Has-WingetPackage([string]$Id) {
    $Output = & winget list --id $Id --exact --accept-source-agreements 2>&1
    return ($LASTEXITCODE -eq 0 -and ($Output -join "`n") -match [regex]::Escape($Id))
}
function Install-Winget([string]$Id, [string[]]$ExtraArgs = @()) {
    if (Has-WingetPackage $Id) {
        Write-Host "[bitshit] $Id ist bereits installiert."
        return
    }

    Write-Host "[bitshit] Installiere $Id"
    $InstallArgs = @('install','--id',$Id,'--exact','--accept-package-agreements','--accept-source-agreements','--silent') + $ExtraArgs
    & winget @InstallArgs
    if ($LASTEXITCODE -ne 0 -and -not (Has-WingetPackage $Id)) {
        throw "[bitshit] winget konnte $Id nicht installieren."
    }
}
function Import-VsDevEnvironment {
    if (Has 'cl.exe' -or Has 'clang-cl.exe') { return }

    $VsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $VsWhere)) {
        throw '[bitshit] vswhere.exe wurde nach der Build-Tools-Installation nicht gefunden.'
    }

    $InstallPath = (& $VsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        throw '[bitshit] Visual Studio C++ Build Tools wurden gefunden, aber der VC-Toolchain-Workload fehlt.'
    }

    $VsDevCmd = Join-Path $InstallPath 'Common7\Tools\VsDevCmd.bat'
    if (-not (Test-Path $VsDevCmd)) {
        throw "[bitshit] VsDevCmd.bat fehlt unter $VsDevCmd"
    }

    $EnvironmentLines = & cmd.exe /s /c "`"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && set" 2>$null
    foreach ($Line in $EnvironmentLines) {
        if ($Line -match '^([^=]+)=(.*)$') {
            Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2]
        }
    }

    if (-not (Has 'cl.exe') -and -not (Has 'clang-cl.exe')) {
        throw '[bitshit] Die Visual-Studio-Umgebung wurde geladen, aber cl.exe ist weiterhin nicht verfügbar.'
    }
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
Import-VsDevEnvironment

$App = Join-Path $RepoRoot 'scripts\app-windows.ps1'
$AppArgs = @('-Backend', $Backend)
if ($Yes) { $AppArgs += '-Yes' }
if ($NoLegacyAlias) { $AppArgs += '-NoLegacyAlias' }
if ($NoMigrate) { $AppArgs += '-NoMigrate' }
& $App @AppArgs
if ($LASTEXITCODE -ne 0) { throw "[bitshit] Windows-Installation ist mit Exitcode $LASTEXITCODE fehlgeschlagen." }
