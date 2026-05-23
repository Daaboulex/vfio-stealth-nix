# vfio-stealth guest cleanup — run ONCE as Administrator in PowerShell
# Removes QEMU/KVM/VirtIO registry artifacts that anti-cheat systems scan
#
# Usage: Right-click PowerShell -> Run as Administrator
#   .\cleanup-registry.ps1
#   .\cleanup-registry.ps1 -Manufacturer "Gigabyte Technology Co., Ltd." -Product "B650 AORUS ELITE AX"
# Reboot after running.
#
# WARNING: This modifies HKLM registry keys. Only run inside a VFIO guest VM
# that already has vfio-stealth-nix host-side configuration applied.

#Requires -RunAsAdministrator

param(
    [string]$Manufacturer = "ASUSTeK COMPUTER INC.",
    [string]$Product = "ROG CROSSHAIR X870E HERO",
    [string]$BIOSVendor = "American Megatrends Inc.",
    [string]$BIOSVersion = "2101",
    [string]$ChassisManufacturer = $Manufacturer,
    [string]$SystemFamily = "To be filled by O.E.M."
)

$cleaned = 0

Write-Host "=== vfio-stealth registry cleanup ===" -ForegroundColor Cyan
Write-Host "Manufacturer: $Manufacturer"
Write-Host "Product:      $Product"
Write-Host "BIOS Vendor:  $BIOSVendor"
Write-Host ""

# ============================================================================
# Section 1: SMBIOS registry overrides
# ============================================================================
$biosPath = "HKLM:\HARDWARE\DESCRIPTION\System\BIOS"
if (Test-Path $biosPath) {
    Set-ItemProperty -Path $biosPath -Name SystemManufacturer -Value $Manufacturer -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $biosPath -Name SystemProductName -Value $Product -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $biosPath -Name BIOSVendor -Value $BIOSVendor -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $biosPath -Name BIOSVersion -Value $BIOSVersion -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $biosPath -Name BaseBoardManufacturer -Value $Manufacturer -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $biosPath -Name BaseBoardProduct -Value $Product -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $biosPath -Name SystemFamily -Value $SystemFamily -ErrorAction SilentlyContinue
    Write-Host "[OK] SMBIOS registry entries updated" -ForegroundColor Green
    $cleaned++
} else {
    Write-Host "[SKIP] BIOS registry path not found" -ForegroundColor Yellow
}

# ============================================================================
# Section 2: VirtIO driver service remnants
# ============================================================================
$servicePaths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services\VirtIO*",
    "HKLM:\SYSTEM\CurrentControlSet\Services\viostor",
    "HKLM:\SYSTEM\CurrentControlSet\Services\vioscsi",
    "HKLM:\SYSTEM\CurrentControlSet\Services\vioser",
    "HKLM:\SYSTEM\CurrentControlSet\Services\viorng",
    "HKLM:\SYSTEM\CurrentControlSet\Services\vioinput",
    "HKLM:\SYSTEM\CurrentControlSet\Services\viofs",
    "HKLM:\SYSTEM\CurrentControlSet\Services\viogpudo",
    "HKLM:\SYSTEM\CurrentControlSet\Services\netkvm",
    "HKLM:\SYSTEM\CurrentControlSet\Services\Balloon"
)
$removedServices = 0
foreach ($path in $servicePaths) {
    $items = Get-Item $path -ErrorAction SilentlyContinue
    if ($items) {
        $items | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $removedServices++
    }
}
Write-Host "[OK] Removed $removedServices VirtIO service entries" -ForegroundColor Green
$cleaned++

# ============================================================================
# Section 3: QEMU/VirtIO PCI device enumeration entries
# AutoVirt rewrites VEN_1AF4/1B36→1022 (AMD) and VEN_1234→1002 (ATI).
# Clean both original and rewritten IDs to cover patched and un-patched QEMU.
# ============================================================================
$devPaths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_1AF4*",  # Red Hat VirtIO (original)
    "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_1B36*",  # Red Hat QEMU PCIe (original)
    "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_1234*",  # QEMU standard VGA (original)
    "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_1022&DEV_1110*"  # ivshmem after AutoVirt rewrite
)
$removedDevices = 0
foreach ($path in $devPaths) {
    $items = Get-Item $path -ErrorAction SilentlyContinue
    if ($items) {
        $items | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $removedDevices++
    }
}
Write-Host "[OK] Removed $removedDevices QEMU/VirtIO PCI device entries" -ForegroundColor Green
$cleaned++

# ============================================================================
# Section 4: QEMU Guest Agent service and files
# ============================================================================
$qemuGA = "HKLM:\SYSTEM\CurrentControlSet\Services\QEMU Guest Agent"
if (Test-Path $qemuGA) {
    # Stop service first if running
    Stop-Service "QEMU Guest Agent" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $qemuGA -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Removed QEMU Guest Agent service key" -ForegroundColor Green
    $cleaned++
}
# Remove qemu-ga binary and config
$qgaPaths = @(
    "$env:ProgramFiles\QEMU Guest Agent",
    "$env:ProgramFiles\Qemu-ga",
    "${env:ProgramFiles(x86)}\QEMU Guest Agent"
)
foreach ($p in $qgaPaths) {
    if (Test-Path $p) {
        Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Removed QEMU GA directory: $p" -ForegroundColor Green
        $cleaned++
    }
}

# ============================================================================
# Section 5: QEMU display adapter registry keys
# ============================================================================
$displayPaths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_1234*",     # QEMU stdvga
    "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY\QEMU*",     # QEMU monitor
    "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY\Default_Monitor*"
)
$removedDisplay = 0
foreach ($path in $displayPaths) {
    $items = Get-Item $path -ErrorAction SilentlyContinue
    if ($items) {
        $items | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $removedDisplay++
    }
}
Write-Host "[OK] Removed $removedDisplay QEMU display adapter entries" -ForegroundColor Green
$cleaned++

# ============================================================================
# Section 6: VirtIO driver files in System32\drivers
# ============================================================================
$vioDrivers = Get-ChildItem "$env:SystemRoot\System32\drivers\vio*.sys" -ErrorAction SilentlyContinue
$removedDrivers = 0
foreach ($drv in $vioDrivers) {
    Remove-Item $drv.FullName -Force -ErrorAction SilentlyContinue
    $removedDrivers++
}
if ($removedDrivers -gt 0) {
    Write-Host "[OK] Removed $removedDrivers VirtIO driver files from System32\drivers" -ForegroundColor Green
    $cleaned++
}

# ============================================================================
# Section 7: Event log entries mentioning QEMU/VirtIO/KVM
# ============================================================================
$logNames = @("System", "Application", "Setup")
$clearedLogs = 0
foreach ($log in $logNames) {
    try {
        $vmEvents = Get-WinEvent -LogName $log -ErrorAction SilentlyContinue | Where-Object {
            $_.Message -match "QEMU|VirtIO|KVM|Red Hat|Hyper-V|Virtual|hypervisor|viostor|vioscsi|netkvm"
        }
        if ($vmEvents -and $vmEvents.Count -gt 0) {
            # Cannot selectively delete events; clear entire log if contaminated
            wevtutil cl $log 2>$null
            $clearedLogs++
        }
    } catch {
        # Log may not exist or access denied
    }
}
if ($clearedLogs -gt 0) {
    Write-Host "[OK] Cleared $clearedLogs event logs containing VM references" -ForegroundColor Green
    Write-Host "     (System/Application/Setup logs were cleared entirely)" -ForegroundColor Yellow
    $cleaned++
} else {
    Write-Host "[OK] No VM references in event logs" -ForegroundColor Green
}

# ============================================================================
# Section 8: Device Manager cached device descriptions
# ============================================================================
$setupClasses = @(
    "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e96c-e325-11ce-bfc1-08002be10318}",  # Display
    "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}",  # Network
    "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e97b-e325-11ce-bfc1-08002be10318}"   # SCSI
)
$cleanedDevMgr = 0
foreach ($classPath in $setupClasses) {
    if (Test-Path $classPath) {
        $subkeys = Get-ChildItem $classPath -ErrorAction SilentlyContinue
        foreach ($sub in $subkeys) {
            $desc = Get-ItemProperty $sub.PSPath -Name "DriverDesc" -ErrorAction SilentlyContinue
            if ($desc -and $desc.DriverDesc -match "QEMU|VirtIO|Red Hat|Bochs|Virtual") {
                Remove-Item $sub.PSPath -Recurse -Force -ErrorAction SilentlyContinue
                $cleanedDevMgr++
            }
        }
    }
}
if ($cleanedDevMgr -gt 0) {
    Write-Host "[OK] Removed $cleanedDevMgr cached device descriptions" -ForegroundColor Green
    $cleaned++
}

# ============================================================================
# Done
# ============================================================================
Write-Host ""
Write-Host "Registry cleanup complete ($cleaned sections processed). Reboot required." -ForegroundColor Cyan
