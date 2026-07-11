param(
    [ValidateSet('text','json')]
    [string]$Format = 'text'
)

$ErrorActionPreference = 'Stop'

function Has([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

$Cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name)
$RamBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
$RamMb = [math]::Floor($RamBytes / 1MB)
$GpuControllers = @(Get-CimInstance Win32_VideoController)
$GpuVendor = 'none'
$GpuName = 'none'
$NvidiaDriver = $false
$CudaToolkit = Has 'nvcc'
$RocmRuntime = $false
$MetalAvailable = $false
$SelectedBackend = 'cpu'

$NvidiaGpu = $GpuControllers | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1
$AmdGpu = $GpuControllers | Where-Object { $_.Name -match 'AMD|Radeon' } | Select-Object -First 1
$IntelGpu = $GpuControllers | Where-Object { $_.Name -match 'Intel' } | Select-Object -First 1

if ($NvidiaGpu) {
    $GpuVendor = 'nvidia'
    $GpuName = $NvidiaGpu.Name
    if (Has 'nvidia-smi') {
        & nvidia-smi --query-gpu=name,driver_version --format=csv,noheader | Out-Null
        $NvidiaDriver = ($LASTEXITCODE -eq 0)
    }
} elseif ($AmdGpu) {
    $GpuVendor = 'amd'
    $GpuName = $AmdGpu.Name
} elseif ($IntelGpu) {
    $GpuVendor = 'intel'
    $GpuName = $IntelGpu.Name
}

if ($NvidiaDriver -and $CudaToolkit) {
    $SelectedBackend = 'cuda'
}

$Result = [ordered]@{
    os = 'Windows'
    arch = $env:PROCESSOR_ARCHITECTURE
    cpu = $Cpu
    ram_mb = [int64]$RamMb
    gpu_vendor = $GpuVendor
    gpu_name = $GpuName
    nvidia_driver = $NvidiaDriver
    cuda_toolkit = $CudaToolkit
    rocm_runtime = $RocmRuntime
    metal_available = $MetalAvailable
    selected_backend = $SelectedBackend
}

if ($Format -eq 'json') {
    $Result | ConvertTo-Json -Depth 3
} else {
    Write-Host "OS: $($Result.os)"
    Write-Host "Architektur: $($Result.arch)"
    Write-Host "CPU: $($Result.cpu)"
    Write-Host "RAM MB: $($Result.ram_mb)"
    Write-Host "GPU Anbieter: $($Result.gpu_vendor)"
    Write-Host "GPU: $($Result.gpu_name)"
    Write-Host "NVIDIA Treiber: $($Result.nvidia_driver)"
    Write-Host "CUDA Toolkit: $($Result.cuda_toolkit)"
    Write-Host "ROCm Runtime: $($Result.rocm_runtime)"
    Write-Host "Metal: $($Result.metal_available)"
    Write-Host "Empfohlenes Backend: $($Result.selected_backend)"
}
