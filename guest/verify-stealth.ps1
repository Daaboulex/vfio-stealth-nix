# vfio-stealth verification — checks detection vectors from inside the Windows guest
#
# Usage: .\verify-stealth.ps1
# Run inside the VM after applying host-side vfio-stealth-nix config + guest cleanup.
# Does NOT require Administrator (read-only checks).

$failed = 0
$warned = 0

Write-Host "=== vfio-stealth detection check ===" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------
# 1. SMBIOS: Win32_ComputerSystem manufacturer
# Anti-cheat checks this for QEMU, Bochs, Virtual, VMware, Xen, KVM
# -----------------------------------------------------------------------
$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.Manufacturer -match "QEMU|Bochs|Virtual|VMware|Xen|KVM|innotek") {
    Write-Host "[FAIL] Win32_ComputerSystem.Manufacturer: $($cs.Manufacturer)" -ForegroundColor Red
    $failed++
} else {
    Write-Host "[PASS] Manufacturer: $($cs.Manufacturer)" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 2. SMBIOS: BIOS vendor
# SeaBIOS and Bochs BIOS are instant VM detection
# -----------------------------------------------------------------------
$bios = Get-CimInstance Win32_BIOS
if ($bios.Manufacturer -match "SeaBIOS|QEMU|Bochs|innotek|Phoenix Technologies.*Virtual") {
    Write-Host "[FAIL] BIOS Vendor: $($bios.Manufacturer)" -ForegroundColor Red
    $failed++
} else {
    Write-Host "[PASS] BIOS: $($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 3. SMBIOS: Baseboard (motherboard)
# QEMU reports "QEMU" as board manufacturer by default
# -----------------------------------------------------------------------
$bb = Get-CimInstance Win32_BaseBoard
if ($bb.Manufacturer -match "QEMU|Oracle|Microsoft|VMware|innotek") {
    Write-Host "[FAIL] BaseBoard: $($bb.Manufacturer)" -ForegroundColor Red
    $failed++
} else {
    Write-Host "[PASS] BaseBoard: $($bb.Manufacturer) $($bb.Product)" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 4. VM-specific Windows services
# VBox, VMware tools, Hyper-V integration services, QEMU guest agent
# -----------------------------------------------------------------------
$vmServices = @("VBoxService", "VMTools", "vmicheartbeat", "vmicshutdown", "vmickvpexchange", "QEMU*")
foreach ($svc in $vmServices) {
    $found = Get-Service $svc -ErrorAction SilentlyContinue
    if ($found) {
        Write-Host "[FAIL] VM service found: $($found.Name)" -ForegroundColor Red
        $failed++
    }
}
Write-Host "[PASS] No VM-specific services detected" -ForegroundColor Green

# -----------------------------------------------------------------------
# 5. PCI device vendor IDs
# VEN_1AF4 = Red Hat (VirtIO), VEN_1B36 = Red Hat (QEMU PCIe),
# VEN_1234 = QEMU VGA — all dead giveaways
# -----------------------------------------------------------------------
$pci = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.DeviceId -match "VEN_1AF4|VEN_1B36|VEN_1234" }
if ($pci) {
    Write-Host "[FAIL] VM PCI devices: $($pci.Count) found" -ForegroundColor Red
    $pci | ForEach-Object { Write-Host "       $($_.DeviceId)" -ForegroundColor Red }
    $failed++
} else {
    Write-Host "[PASS] No VirtIO/QEMU PCI devices" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 6. ACPI: Win32_Fan (should exist if SSDT fan table is loaded)
# Real hardware always has fan objects; VMs typically have none
# -----------------------------------------------------------------------
$fans = Get-CimInstance Win32_Fan -ErrorAction SilentlyContinue
if ($fans) {
    Write-Host "[PASS] Win32_Fan present ($($fans.Count) fans)" -ForegroundColor Green
} else {
    Write-Host "[WARN] Win32_Fan empty (ACPI SSDT may not be loaded)" -ForegroundColor Yellow
    $warned++
}

# -----------------------------------------------------------------------
# 7. ACPI: Battery (should exist if fake-battery.aml is loaded)
# Laptops always have one; desktops don't — but VMs never do
# -----------------------------------------------------------------------
$battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
if ($battery) {
    Write-Host "[PASS] Battery present" -ForegroundColor Green
} else {
    Write-Host "[WARN] No battery (fake-battery.aml may not be loaded)" -ForegroundColor Yellow
    $warned++
}

# -----------------------------------------------------------------------
# 8. SMBIOS Type 17: Physical memory DIMMs
# Real machines report DIMM manufacturer/part number; VMs often leave
# these empty or missing entirely
# -----------------------------------------------------------------------
$mem = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
if ($mem.Count -ge 1 -and $mem[0].Manufacturer -ne "") {
    Write-Host "[PASS] Physical memory: $($mem.Count) DIMMs, $($mem[0].Manufacturer)" -ForegroundColor Green
} else {
    Write-Host "[WARN] No physical memory info (SMBIOS type 17 may be missing)" -ForegroundColor Yellow
    $warned++
}

# -----------------------------------------------------------------------
# 9. CPUID hypervisor bit (leaf 0x1, bit 31 of ECX)
# If KVM hv-passthrough is not hiding the hypervisor, this will be set
# -----------------------------------------------------------------------
try {
    $hypervisor = Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty HypervisorPresent -ErrorAction SilentlyContinue
    if ($hypervisor -eq $true) {
        Write-Host "[FAIL] HypervisorPresent = True (CPUID hypervisor bit is set)" -ForegroundColor Red
        $failed++
    } else {
        Write-Host "[PASS] HypervisorPresent = False" -ForegroundColor Green
    }
} catch {
    Write-Host "[SKIP] Could not check HypervisorPresent" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "=== $failed failures, $warned warnings ===" -ForegroundColor $(if ($failed -gt 0) { "Red" } elseif ($warned -gt 0) { "Yellow" } else { "Green" })
if ($failed -eq 0 -and $warned -eq 0) {
    Write-Host "All checks passed!" -ForegroundColor Green
} elseif ($failed -eq 0) {
    Write-Host "No failures, but warnings should be reviewed." -ForegroundColor Yellow
} else {
    Write-Host "Fix failures before running anti-cheat software." -ForegroundColor Red
}
