param(
    [Parameter(Position = 0)]
    [ValidateSet('auto','cpu','cuda')]
    [string]$Backend = ''
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Bootstrap = Join-Path $RepoRoot 'bootstrap-windows.ps1'

if ($env:OS -ne 'Windows_NT') {
    throw 'FEHLER: env-setup.ps1 ist nur fuer Windows. Verwende env-setup.sh unter Linux.'
}

if (-not (Test-Path $Bootstrap)) {
    throw 'FEHLER: bootstrap-windows.ps1 fehlt im Repository.'
}

if ([string]::IsNullOrWhiteSpace($Backend)) {
    & $Bootstrap
} else {
    & $Bootstrap $Backend
}

if ($LASTEXITCODE -ne 0) {
    throw "FEHLER: Windows Bootstrap ist mit Exitcode $LASTEXITCODE fehlgeschlagen."
}
