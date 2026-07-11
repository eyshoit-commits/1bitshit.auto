param(
    [ValidateSet('auto','cpu','cuda')]
    [string]$Backend = 'auto',
    [switch]$Yes,
    [switch]$NoLegacyAlias,
    [switch]$NoMigrate
)

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
if ($env:OS -ne 'Windows_NT') { throw '[bitshit] setup-windows.ps1 ist nur fuer Windows.' }

$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$MsysRoot = if ($env:BITSHIT_MSYS2_ROOT) { $env:BITSHIT_MSYS2_ROOT } else { 'C:\msys64' }
$MsysInstallerUrl = 'https://github.com/msys2/msys2-installer/releases/download/2026-06-11/msys2-x86_64-20260611.exe'
$MsysInstaller = Join-Path $env:TEMP 'msys2-x86_64-20260611.exe'
$MsysBash = Join-Path $MsysRoot 'usr\bin\bash.exe'
$UcrtBin = Join-Path $MsysRoot 'ucrt64\bin'

function Has([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
function Step([string]$Message) { Write-Host "[bitshit] $Message" }
function Fail([string]$Message) { throw "[bitshit] $Message" }

function Install-Msys2 {
    if (Test-Path $MsysBash) {
        Step "MSYS2 ist bereits unter $MsysRoot installiert."
        return
    }

    Step 'Lade MSYS2 2026-06-11 herunter.'
    Invoke-WebRequest -Uri $MsysInstallerUrl -OutFile $MsysInstaller -UseBasicParsing
    if (-not (Test-Path $MsysInstaller)) { Fail 'MSYS2-Installer wurde nicht heruntergeladen.' }

    Step "Installiere MSYS2 nach $MsysRoot."
    $Process = Start-Process -FilePath $MsysInstaller -ArgumentList @(
        'install',
        '--confirm-command',
        '--accept-messages',
        '--root', $MsysRoot
    ) -Wait -PassThru
    if ($Process.ExitCode -ne 0 -or -not (Test-Path $MsysBash)) {
        Fail "MSYS2-Installation ist mit Exitcode $($Process.ExitCode) fehlgeschlagen."
    }
}

function Invoke-Msys([string]$Command) {
    & $MsysBash -lc $Command
    if ($LASTEXITCODE -ne 0) { Fail "MSYS2-Befehl fehlgeschlagen: $Command" }
}

Install-Msys2

Step 'Aktualisiere MSYS2 und installiere die vollständige UCRT64-Buildumgebung.'
Invoke-Msys 'pacman -Sy --noconfirm'
Invoke-Msys 'pacman -S --needed --noconfirm base-devel git make cmake ninja pkgconf mingw-w64-ucrt-x86_64-toolchain mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja mingw-w64-ucrt-x86_64-pkgconf mingw-w64-ucrt-x86_64-rust'

$MachinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
$UserPath = [Environment]::GetEnvironmentVariable('Path','User')
$env:Path = "$UcrtBin;$MsysRoot\usr\bin;$MachinePath;$UserPath"

foreach ($Tool in @('cargo.exe','rustc.exe','gcc.exe','g++.exe','cmake.exe','ninja.exe','make.exe')) {
    if (-not (Has $Tool)) { Fail "$Tool fehlt nach der MSYS2-Installation." }
}

if ($Backend -eq 'cuda') {
    if (-not (Has 'nvidia-smi.exe')) { Fail 'CUDA wurde gewählt, aber der NVIDIA-Treiber fehlt.' }
    if (-not (Has 'nvcc.exe')) {
        Fail 'CUDA wurde gewählt, aber nvcc.exe fehlt. Installiere das NVIDIA CUDA Toolkit und starte das Terminal neu.'
    }
}

$env:BITSHIT_WINDOWS_TOOLCHAIN = 'msys2-ucrt64'
$env:CC = Join-Path $UcrtBin 'gcc.exe'
$env:CXX = Join-Path $UcrtBin 'g++.exe'
$env:AR = Join-Path $UcrtBin 'ar.exe'
$env:CMAKE_GENERATOR = 'Ninja'

$App = Join-Path $RepoRoot 'scripts\app-windows.ps1'
$AppArgs = @('-Backend', $Backend)
if ($Yes) { $AppArgs += '-Yes' }
if ($NoLegacyAlias) { $AppArgs += '-NoLegacyAlias' }
if ($NoMigrate) { $AppArgs += '-NoMigrate' }
& $App @AppArgs
if ($LASTEXITCODE -ne 0) { Fail "Windows-Installation ist mit Exitcode $LASTEXITCODE fehlgeschlagen." }
