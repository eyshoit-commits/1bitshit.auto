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

function Resolve-CudaToolkit {
    $Candidates = New-Object System.Collections.Generic.List[string]

    foreach ($VariableName in @('CUDA_PATH', 'CUDA_HOME', 'CUDA_ROOT')) {
        $Value = [Environment]::GetEnvironmentVariable($VariableName)
        if ($Value) { $Candidates.Add($Value) }
    }

    Get-ChildItem Env: | Where-Object { $_.Name -match '^CUDA_PATH_V\d+_\d+$' } | ForEach-Object {
        if ($_.Value) { $Candidates.Add($_.Value) }
    }

    $DefaultRoot = Join-Path $env:ProgramFiles 'NVIDIA GPU Computing Toolkit\CUDA'
    if (Test-Path $DefaultRoot) {
        Get-ChildItem -Path $DefaultRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object {
                if ($_.Name -match '^v(\d+)\.(\d+)$') {
                    ([int]$Matches[1] * 1000) + [int]$Matches[2]
                } else { 0 }
            } -Descending |
            ForEach-Object { $Candidates.Add($_.FullName) }
    }

    foreach ($Candidate in $Candidates | Select-Object -Unique) {
        $Nvcc = Join-Path $Candidate 'bin\nvcc.exe'
        if (Test-Path $Nvcc) {
            return [PSCustomObject]@{
                Root = (Resolve-Path $Candidate).Path
                Nvcc = (Resolve-Path $Nvcc).Path
            }
        }
    }

    $Command = Get-Command nvcc.exe -ErrorAction SilentlyContinue
    if ($Command) {
        $NvccPath = $Command.Source
        return [PSCustomObject]@{
            Root = Split-Path -Parent (Split-Path -Parent $NvccPath)
            Nvcc = $NvccPath
        }
    }

    return $null
}

function Install-CudaToolkit {
    if (-not (Has 'winget.exe')) {
        Fail 'CUDA Toolkit fehlt und winget ist nicht verfügbar. Installiere App Installer aus dem Microsoft Store oder das NVIDIA CUDA Toolkit manuell.'
    }

    $Install = $Yes
    if (-not $Yes) {
        $Answer = Read-Host 'CUDA Toolkit fehlt. Jetzt automatisch mit winget installieren? [J/n]'
        $Install = [string]::IsNullOrWhiteSpace($Answer) -or $Answer -match '^(?i:j|ja|y|yes)$'
    }

    if (-not $Install) {
        Fail 'CUDA Toolkit wurde nicht installiert. Starte den Installer erneut oder verwende --backend cpu.'
    }

    Step 'Installiere NVIDIA CUDA Toolkit über winget. Das kann einige Minuten dauern.'
    & winget.exe install --id Nvidia.CUDA --exact --source winget --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) {
        Fail "winget konnte das NVIDIA CUDA Toolkit nicht installieren (Exitcode $LASTEXITCODE)."
    }

    $MachinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
    $UserPath = [Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = "$UcrtBin;$MsysRoot\usr\bin;$MachinePath;$UserPath"

    $Cuda = Resolve-CudaToolkit
    if (-not $Cuda) {
        Fail 'CUDA Toolkit wurde installiert, aber nvcc.exe ist noch nicht sichtbar. Öffne ein neues PowerShell-Fenster und starte denselben Installationsbefehl erneut.'
    }

    return $Cuda
}

Install-Msys2

Step 'Aktualisiere MSYS2 und installiere die vollständige UCRT64-Buildumgebung.'
Invoke-Msys 'pacman -Sy --noconfirm'
Invoke-Msys 'pacman -S --needed --noconfirm base-devel git make cmake ninja pkgconf mingw-w64-ucrt-x86_64-toolchain mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja mingw-w64-ucrt-x86_64-pkgconf mingw-w64-ucrt-x86_64-rust mingw-w64-ucrt-x86_64-python mingw-w64-ucrt-x86_64-openssl mingw-w64-ucrt-x86_64-zlib mingw-w64-ucrt-x86_64-curl'

$MachinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
$UserPath = [Environment]::GetEnvironmentVariable('Path','User')
$env:Path = "$UcrtBin;$MsysRoot\usr\bin;$MachinePath;$UserPath"

foreach ($ToolPath in @(
    (Join-Path $UcrtBin 'cargo.exe'),
    (Join-Path $UcrtBin 'rustc.exe'),
    (Join-Path $UcrtBin 'python.exe'),
    (Join-Path $UcrtBin 'gcc.exe'),
    (Join-Path $UcrtBin 'g++.exe'),
    (Join-Path $UcrtBin 'cmake.exe'),
    (Join-Path $UcrtBin 'ninja.exe'),
    (Join-Path $UcrtBin 'mingw32-make.exe'),
    (Join-Path $UcrtBin 'pkg-config.exe')
)) {
    if (-not (Test-Path $ToolPath)) { Fail "$ToolPath fehlt nach der MSYS2-Installation." }
}

if ($Backend -eq 'cuda') {
    if (-not (Has 'nvidia-smi.exe')) {
        Fail 'CUDA wurde gewählt, aber der NVIDIA-Treiber fehlt. Installiere zuerst den aktuellen NVIDIA-Treiber oder verwende --backend cpu.'
    }

    $Cuda = Resolve-CudaToolkit
    if (-not $Cuda) {
        $Cuda = Install-CudaToolkit
    }

    $env:CUDA_PATH = $Cuda.Root
    $env:CUDA_HOME = $Cuda.Root
    $env:CUDACXX = $Cuda.Nvcc
    $env:NVCC = $Cuda.Nvcc
    $env:Path = "$(Join-Path $Cuda.Root 'bin');$env:Path"
    Step "CUDA Toolkit erkannt: $($Cuda.Root)"
    Step "nvcc: $($Cuda.Nvcc)"
}

$env:BITSHIT_WINDOWS_TOOLCHAIN = 'msys2-ucrt64'
$env:CC = Join-Path $UcrtBin 'gcc.exe'
$env:CXX = Join-Path $UcrtBin 'g++.exe'
$env:AR = Join-Path $UcrtBin 'ar.exe'
$env:CMAKE_GENERATOR = 'Ninja'
$env:CMAKE_MAKE_PROGRAM = Join-Path $UcrtBin 'ninja.exe'
$env:PKG_CONFIG = Join-Path $UcrtBin 'pkg-config.exe'
$env:PKG_CONFIG_PATH = "$MsysRoot\ucrt64\lib\pkgconfig;$MsysRoot\ucrt64\share\pkgconfig"
$env:OPENSSL_DIR = "$MsysRoot\ucrt64"
$env:OPENSSL_LIB_DIR = "$MsysRoot\ucrt64\lib"
$env:OPENSSL_INCLUDE_DIR = "$MsysRoot\ucrt64\include"

$App = Join-Path $RepoRoot 'scripts\app-windows.ps1'
$AppArgs = @{ Backend = $Backend }
if ($Yes) { $AppArgs.Yes = $true }
if ($NoLegacyAlias) { $AppArgs.NoLegacyAlias = $true }
if ($NoMigrate) { $AppArgs.NoMigrate = $true }
& $App @AppArgs
if ($LASTEXITCODE -ne 0) { Fail "Windows-Installation ist mit Exitcode $LASTEXITCODE fehlgeschlagen." }
