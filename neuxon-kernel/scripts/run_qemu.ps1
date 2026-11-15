<#
.SYNOPSIS
    Neuxon OS 2.0: Windows PowerShell QEMU Bare-Metal Boot & VirtIO-GPU Runner
#>
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir
$BuildTarget = Join-Path $RootDir "target\x86_64-neuxon_os\release\bootimage-neuxon-kernel.bin"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host " Neuxon OS 2.0: Launching Bare-Metal x86_64 Kernel under QEMU (Windows)" -ForegroundColor Green
Write-Host " Configuration: SMP=4 cores, RAM=2048MB, VirtIO-GPU, macOS Dock & Top Bar" -ForegroundColor DarkGray
Write-Host "======================================================================" -ForegroundColor Cyan

if (-not (Test-Path $BuildTarget)) {
    Write-Host "[*] Compiling Neuxon OS and building bootable disk image..." -ForegroundColor Yellow
    cargo bootimage --release --target x86_64-neuxon_os.json --manifest-path kernel/Cargo.toml
}

$qemu = Get-Command "qemu-system-x86_64.exe" -ErrorAction SilentlyContinue
if (-not $qemu) {
    Write-Host "[!] qemu-system-x86_64.exe not found on PATH. Please ensure QEMU is installed." -ForegroundColor Red
    exit 1
}

& qemu-system-x86_64.exe `
    -drive format=raw,file="$BuildTarget" `
    -machine q35 `
    -cpu max `
    -smp 4 `
    -m 2048M `
    -vga none `
    -device virtio-gpu-pci `
    -device virtio-net-pci,netdev=net0 `
    -netdev user,id=net0 `
    -serial stdio `
    -no-reboot
