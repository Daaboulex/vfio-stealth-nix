# vfio-stealth guest cleanup — run ONCE as Administrator in PowerShell
# Removes QEMU/KVM/VirtIO registry artifacts that anti-cheat systems scan
#
# Usage: Right-click PowerShell → Run as Administrator → .\cleanup-registry.ps1
# Reboot after running.
#
# WARNING: This modifies HKLM registry keys. Only run inside a VFIO guest VM
# that already has vfio-stealth-nix host-side configuration applied.

#Requires -RunAsAdministrator

# ============================================================================
# Section 1: SMBIOS overrides
# If QEMU defaults leaked into the registry before stealth was configured,
# these entries may still contain "QEMU", "Bochs", or "Standard PC".
# Overwrite with realistic values matching the SMBIOS spoofs in module.nix.
# ============================================================================
$biosPath = "HKLM:\HARDWARE\DESCRIPTION\System\BIOS"
if (Test-Path $biosPath) {
    Set-ItemProperty -Path $biosPath -Name SystemManufacturer -Value "ASUSTeK COMPUTER INC." -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $biosPath -Name SystemProductName -Value "ROG CROSSHAIR X870E HERO" -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $biosPath -Name BIOSVendor -Value "American Megatrends Inc." -ErrorAction SilentlyContinue
    Write-Host "[OK] SMBIOS registry entries updated" -ForegroundColor Green
} else {
    Write-Host "[SKIP] BIOS registry path not found" -ForegroundColor Yellow
}

# ============================================================================
# Section 2: VirtIO driver service remnants
# Even after uninstalling VirtIO guest tools, service registry keys may
# persist. Anti-cheat scans CurrentControlSet\Services for known VM drivers.
# ============================================================================
$servicePaths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services\VirtIO*",
    "HKLM:\SYSTEM\CurrentControlSet\Services\viostor",
    "HKLM:\SYSTEM\CurrentControlSet\Services\vioscsi",
    "HKLM:\SYSTEM\CurrentControlSet\Services\vioser",
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

# ============================================================================
# Section 3: QEMU/VirtIO PCI device enumeration entries
# Windows caches PCI device info in the Enum\PCI registry hive.
# These vendor IDs are dead giveaways:
#   VEN_1AF4 = Red Hat (VirtIO)
#   VEN_1B36 = Red Hat (QEMU PCIe)
#   VEN_1234 = QEMU (standard VGA)
# ============================================================================
$devPaths = @(
    "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_1AF4*",  # Red Hat VirtIO
    "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_1B36*",  # Red Hat QEMU PCIe
    "HKLM:\SYSTEM\CurrentControlSet\Enum\PCI\VEN_1234*"   # QEMU standard VGA
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

# ============================================================================
# Section 4: QEMU Guest Agent service
# If qemu-ga was ever installed, its service key lingers.
# ============================================================================
$qemuGA = "HKLM:\SYSTEM\CurrentControlSet\Services\QEMU Guest Agent"
if (Test-Path $qemuGA) {
    Remove-Item -Path $qemuGA -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Removed QEMU Guest Agent service" -ForegroundColor Green
}

# ============================================================================
# Done — reboot required for changes to take full effect
# ============================================================================
Write-Host ""
Write-Host "Registry cleanup complete. Reboot required." -ForegroundColor Cyan
