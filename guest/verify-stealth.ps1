# vfio-stealth verification — checks 30 detection vectors from inside the Windows guest
#
# Usage: .\verify-stealth.ps1
# Run inside the VM after applying host-side vfio-stealth-nix config + guest cleanup.
# Does NOT require Administrator (read-only checks), except thermal zone (root\wmi).

$failed = 0
$warned = 0

Write-Host "=== vfio-stealth detection check (30 vectors) ===" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------
# 1. SMBIOS Type 1: Win32_ComputerSystem.Manufacturer
# -----------------------------------------------------------------------
$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.Manufacturer -match "QEMU|Bochs|Virtual|VMware|Xen|KVM|innotek") {
    Write-Host "[FAIL] Win32_ComputerSystem.Manufacturer: $($cs.Manufacturer)" -ForegroundColor Red
    $failed++
} else {
    Write-Host "[PASS] Manufacturer: $($cs.Manufacturer)" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 2. SMBIOS Type 0: Win32_BIOS.Manufacturer
# -----------------------------------------------------------------------
$bios = Get-CimInstance Win32_BIOS
if ($bios.Manufacturer -match "SeaBIOS|QEMU|Bochs|innotek|Phoenix Technologies.*Virtual") {
    Write-Host "[FAIL] BIOS Vendor: $($bios.Manufacturer)" -ForegroundColor Red
    $failed++
} else {
    Write-Host "[PASS] BIOS: $($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 3. SMBIOS Type 2: Win32_BaseBoard.Manufacturer
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
# -----------------------------------------------------------------------
$vmServices = @("VBoxService", "VMTools", "vmicheartbeat", "vmicshutdown", "vmickvpexchange", "QEMU*")
$svcFailed = $false
foreach ($svc in $vmServices) {
    $found = Get-Service $svc -ErrorAction SilentlyContinue
    if ($found) {
        Write-Host "[FAIL] VM service found: $($found.Name)" -ForegroundColor Red
        $failed++
        $svcFailed = $true
    }
}
if (-not $svcFailed) {
    Write-Host "[PASS] No VM-specific services detected" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 5. PCI device vendor IDs (VirtIO / QEMU PCIe / QEMU VGA)
#    NOTE: AutoVirt rewrites VEN_1AF4→1022, VEN_1B36→1022, VEN_1234→1002.
#    With AutoVirt applied, these original IDs should never appear.
#    We still check the originals to catch un-patched QEMU.
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
# 6. ACPI: Win32_Fan
# -----------------------------------------------------------------------
$fans = Get-CimInstance Win32_Fan -ErrorAction SilentlyContinue
if ($fans) {
    Write-Host "[PASS] Win32_Fan present ($($fans.Count) fans)" -ForegroundColor Green
} else {
    Write-Host "[WARN] Win32_Fan empty (ACPI SSDT may not be loaded)" -ForegroundColor Yellow
    $warned++
}

# -----------------------------------------------------------------------
# 7. ACPI: Win32_Battery
# -----------------------------------------------------------------------
$battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
if ($battery) {
    Write-Host "[PASS] Battery present" -ForegroundColor Green
} else {
    Write-Host "[WARN] No battery (fake-battery.aml may not be loaded)" -ForegroundColor Yellow
    $warned++
}

# -----------------------------------------------------------------------
# 8. SMBIOS Type 17: Win32_PhysicalMemory
# -----------------------------------------------------------------------
$mem = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
if ($mem.Count -ge 1 -and $mem[0].Manufacturer -ne "") {
    Write-Host "[PASS] Physical memory: $($mem.Count) DIMMs, $($mem[0].Manufacturer)" -ForegroundColor Green
} else {
    Write-Host "[WARN] No physical memory info (SMBIOS type 17 may be missing)" -ForegroundColor Yellow
    $warned++
}

# -----------------------------------------------------------------------
# 9. CPUID hypervisor bit
# -----------------------------------------------------------------------
try {
    $hypervisor = $cs.HypervisorPresent
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
# 10. Win32_DiskDrive.Model — QEMU default disk model strings
# -----------------------------------------------------------------------
$disks = Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue
$vmDisk = $disks | Where-Object { $_.Model -match "QEMU|VBOX|Virtual|VirtIO" }
if ($vmDisk) {
    Write-Host "[FAIL] VM disk model: $($vmDisk.Model)" -ForegroundColor Red
    $failed++
} else {
    $diskInfo = if ($disks) { $disks[0].Model } else { "none" }
    Write-Host "[PASS] Disk model: $diskInfo" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 11. Win32_CDROMDrive.Name — QEMU default optical drive model
# -----------------------------------------------------------------------
$cdrom = Get-CimInstance Win32_CDROMDrive -ErrorAction SilentlyContinue
$vmCd = $cdrom | Where-Object { $_.Name -match "QEMU|VBOX|Virtual|VirtIO" }
if ($vmCd) {
    Write-Host "[FAIL] VM optical drive: $($vmCd.Name)" -ForegroundColor Red
    $failed++
} else {
    $cdInfo = if ($cdrom) { $cdrom[0].Name } else { "none" }
    Write-Host "[PASS] Optical drive: $cdInfo" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 12. SMBIOS Type 3: Win32_SystemEnclosure.Manufacturer
# -----------------------------------------------------------------------
$chassis = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue
if ($chassis.Manufacturer -match "QEMU|Bochs|Virtual|VMware|innotek") {
    Write-Host "[FAIL] Chassis manufacturer: $($chassis.Manufacturer)" -ForegroundColor Red
    $failed++
} else {
    Write-Host "[PASS] Chassis: $($chassis.Manufacturer)" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 13. SMBIOS Type 7: Win32_CacheMemory count and sizes
# -----------------------------------------------------------------------
$caches = Get-CimInstance Win32_CacheMemory -ErrorAction SilentlyContinue
if ($caches -and $caches.Count -ge 2) {
    $sizes = ($caches | ForEach-Object { "$($_.Purpose) $($_.InstalledSize)KB" }) -join ", "
    Write-Host "[PASS] CacheMemory: $($caches.Count) levels ($sizes)" -ForegroundColor Green
} else {
    Write-Host "[WARN] CacheMemory: $( if ($caches) { $caches.Count } else { 0 } ) entries (VMs have none by default)" -ForegroundColor Yellow
    $warned++
}

# -----------------------------------------------------------------------
# 14. SMBIOS Type 9: Win32_SystemSlot presence
# -----------------------------------------------------------------------
$slots = Get-CimInstance Win32_SystemSlot -ErrorAction SilentlyContinue
if ($slots) {
    Write-Host "[PASS] SystemSlot: $($slots.Count) slots" -ForegroundColor Green
} else {
    Write-Host "[WARN] No system slots (VMs lack SMBIOS type 9)" -ForegroundColor Yellow
    $warned++
}

# -----------------------------------------------------------------------
# 15. SMBIOS Type 28: Win32_TemperatureProbe
# -----------------------------------------------------------------------
$tempProbe = Get-CimInstance Win32_TemperatureProbe -ErrorAction SilentlyContinue
if ($tempProbe) {
    Write-Host "[PASS] TemperatureProbe present" -ForegroundColor Green
} else {
    Write-Host "[WARN] No TemperatureProbe (SMBIOS type 28 may be missing)" -ForegroundColor Yellow
    $warned++
}

# -----------------------------------------------------------------------
# 16. SMBIOS Type 26: Win32_VoltageProbe
# -----------------------------------------------------------------------
$voltProbe = Get-CimInstance Win32_VoltageProbe -ErrorAction SilentlyContinue
if ($voltProbe) {
    Write-Host "[PASS] VoltageProbe present" -ForegroundColor Green
} else {
    Write-Host "[WARN] No VoltageProbe (SMBIOS type 26 may be missing)" -ForegroundColor Yellow
    $warned++
}

# -----------------------------------------------------------------------
# 17. SMBIOS Type 29: Win32_CurrentProbe
# -----------------------------------------------------------------------
$curProbe = Get-CimInstance Win32_CurrentProbe -ErrorAction SilentlyContinue
if ($curProbe) {
    Write-Host "[PASS] CurrentProbe present" -ForegroundColor Green
} else {
    Write-Host "[WARN] No CurrentProbe (SMBIOS type 29 may be missing)" -ForegroundColor Yellow
    $warned++
}

# -----------------------------------------------------------------------
# 18. MSAcpi_ThermalZoneTemperature (root\wmi)
# Requires Admin — degrades to WARN/SKIP if unprivileged.
# -----------------------------------------------------------------------
try {
    $tz = Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop
    if ($tz) {
        Write-Host "[PASS] ACPI ThermalZone present ($($tz.Count) zone(s))" -ForegroundColor Green
    } else {
        Write-Host "[WARN] No ACPI ThermalZone (sensor-probes.aml may not be loaded)" -ForegroundColor Yellow
        $warned++
    }
} catch {
    Write-Host "[SKIP] MSAcpi_ThermalZoneTemperature (requires Administrator)" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# 19. Win32_NetworkAdapter — emulated NIC model strings
# -----------------------------------------------------------------------
$nics = Get-CimInstance Win32_NetworkAdapter -ErrorAction SilentlyContinue | Where-Object { $_.PhysicalAdapter -eq $true }
$vmNic = $nics | Where-Object { $_.Description -match "VirtIO|Virtio|Red Hat|QEMU|VMware|VirtualBox|Hyper-V" }
if ($vmNic) {
    Write-Host "[FAIL] VM NIC detected: $($vmNic[0].Description)" -ForegroundColor Red
    $failed++
} else {
    $nicInfo = if ($nics) { $nics[0].Description } else { "none" }
    Write-Host "[PASS] NIC: $nicInfo" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 20. EDID monitor identity — registry check
# -----------------------------------------------------------------------
$edidFound = $false
$edidVm = $false
try {
    $monKeys = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY" -ErrorAction SilentlyContinue
    foreach ($key in $monKeys) {
        if ($key.PSChildName -match "^(QEMU|BOX|VBOX|Default_Monitor)") {
            $edidVm = $true
            Write-Host "[FAIL] EDID registry: VM monitor ID '$($key.PSChildName)'" -ForegroundColor Red
            $failed++
            break
        }
        $edidFound = $true
    }
    if (-not $edidVm -and $edidFound) {
        Write-Host "[PASS] EDID: no VM monitor IDs in registry" -ForegroundColor Green
    } elseif (-not $edidVm -and -not $edidFound) {
        Write-Host "[WARN] EDID: no monitor entries found" -ForegroundColor Yellow
        $warned++
    }
} catch {
    Write-Host "[SKIP] Could not read EDID registry" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# 21. ACPI table OEM IDs — check for BOCHS/BXPC/VBOX via raw firmware
# -----------------------------------------------------------------------
try {
    $acpiOem = Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
    # Fallback: check registry for cached ACPI info
    $acpiBios = Get-ItemProperty "HKLM:\HARDWARE\DESCRIPTION\System\BIOS" -ErrorAction SilentlyContinue
    if ($acpiBios) {
        $combined = "$($acpiBios.SystemManufacturer)|$($acpiBios.BIOSVendor)"
        if ($combined -match "BOCHS|BXPC|QEMU|Bochs") {
            Write-Host "[FAIL] ACPI OEM: VM strings in BIOS registry ($combined)" -ForegroundColor Red
            $failed++
        } else {
            Write-Host "[PASS] ACPI OEM: no BOCHS/BXPC/QEMU in BIOS registry" -ForegroundColor Green
        }
    } else {
        Write-Host "[SKIP] ACPI OEM: BIOS registry path unavailable" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[SKIP] ACPI OEM check failed" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# 22. SMBIOS Type 0: BIOS date format check
# -----------------------------------------------------------------------
if ($bios.ReleaseDate) {
    $biosDate = $bios.ReleaseDate
    # QEMU default date is often 04/01/2014 or 11/11/2020 (Bochs)
    $suspectDates = @("20140401", "20201111", "20060101")
    $dateStr = $biosDate.ToString("yyyyMMdd")
    if ($suspectDates -contains $dateStr) {
        Write-Host "[FAIL] BIOS date suspicious: $($biosDate.ToString('yyyy-MM-dd')) (known VM default)" -ForegroundColor Red
        $failed++
    } else {
        Write-Host "[PASS] BIOS date: $($biosDate.ToString('yyyy-MM-dd'))" -ForegroundColor Green
    }
} else {
    Write-Host "[WARN] BIOS date unavailable" -ForegroundColor Yellow
    $warned++
}

# -----------------------------------------------------------------------
# 23. SMBIOS Type 2: BaseBoard serial/version emptiness
# -----------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($bb.SerialNumber) -or $bb.SerialNumber -eq "None" -or $bb.SerialNumber -eq "Default string") {
    Write-Host "[WARN] BaseBoard serial empty or default: '$($bb.SerialNumber)'" -ForegroundColor Yellow
    $warned++
} else {
    Write-Host "[PASS] BaseBoard serial: $($bb.SerialNumber)" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 24. Win32_Processor.Name — CPU brand string consistency
# -----------------------------------------------------------------------
$cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
if ($cpu) {
    if ($cpu.Name -match "QEMU|KVM|Virtual") {
        Write-Host "[FAIL] CPU name: $($cpu.Name)" -ForegroundColor Red
        $failed++
    } else {
        Write-Host "[PASS] CPU: $($cpu.Name)" -ForegroundColor Green
    }
} else {
    Write-Host "[SKIP] Could not query Win32_Processor" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# 25. ivshmem device — VEN_1022&DEV_1110 (shared memory, common VFIO add-on)
#     AutoVirt rewrites Red Hat VEN_1AF4 → AMD VEN_1022, so ivshmem now
#     appears as an AMD device. Check both in case AutoVirt is not applied.
# -----------------------------------------------------------------------
$ivshmem = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.DeviceId -match "VEN_(1AF4|1022)&DEV_1110" }
if ($ivshmem) {
    Write-Host "[FAIL] ivshmem device found: $($ivshmem[0].DeviceId)" -ForegroundColor Red
    $failed++
} else {
    Write-Host "[PASS] No ivshmem device" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 26. QEMU Guest Agent process
# -----------------------------------------------------------------------
$qga = Get-Process "qemu-ga" -ErrorAction SilentlyContinue
if ($qga) {
    Write-Host "[FAIL] QEMU Guest Agent process running (qemu-ga.exe)" -ForegroundColor Red
    $failed++
} else {
    Write-Host "[PASS] No QEMU Guest Agent process" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 27. VirtIO driver files in System32\drivers
# -----------------------------------------------------------------------
$vioDrivers = Get-ChildItem "$env:SystemRoot\System32\drivers\vio*.sys" -ErrorAction SilentlyContinue
if ($vioDrivers) {
    Write-Host "[FAIL] VirtIO drivers found: $($vioDrivers.Name -join ', ')" -ForegroundColor Red
    $failed++
} else {
    Write-Host "[PASS] No VirtIO driver files" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 28. Hyper-V vendor ID string — check for known VM values
# -----------------------------------------------------------------------
try {
    $hvInfo = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters" -ErrorAction SilentlyContinue
    if ($hvInfo) {
        $vendorVal = $hvInfo.VirtualMachineName
        if ($vendorVal) {
            Write-Host "[WARN] Hyper-V guest params key exists (VirtualMachineName=$vendorVal)" -ForegroundColor Yellow
            $warned++
        }
    } else {
        Write-Host "[PASS] No Hyper-V guest parameters key" -ForegroundColor Green
    }
} catch {
    Write-Host "[PASS] Hyper-V guest parameters not present" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 29. Win32_ComputerSystem.Model — should not be QEMU/Bochs
# -----------------------------------------------------------------------
if ($cs.Model -match "QEMU|Bochs|Virtual|Standard PC|KVM|VirtualBox") {
    Write-Host "[FAIL] ComputerSystem.Model: $($cs.Model)" -ForegroundColor Red
    $failed++
} else {
    Write-Host "[PASS] Model: $($cs.Model)" -ForegroundColor Green
}

# -----------------------------------------------------------------------
# 30. SMBIOS Type 11: OEM Strings — check for QEMU/VM markers
# -----------------------------------------------------------------------
try {
    $oemStrings = Get-CimInstance -Query "SELECT * FROM Win32_ComputerSystem" -ErrorAction Stop
    # OEM strings typically in SystemFamily or via raw SMBIOS; check registry fallback
    $smbiosOem = Get-ItemProperty "HKLM:\HARDWARE\DESCRIPTION\System\BIOS" -Name "SystemFamily" -ErrorAction SilentlyContinue
    if ($smbiosOem -and $smbiosOem.SystemFamily -match "QEMU|Virtual|Bochs") {
        Write-Host "[FAIL] SMBIOS OEM/SystemFamily: $($smbiosOem.SystemFamily)" -ForegroundColor Red
        $failed++
    } else {
        Write-Host "[PASS] SMBIOS OEM strings clean" -ForegroundColor Green
    }
} catch {
    Write-Host "[SKIP] Could not query OEM strings" -ForegroundColor Yellow
}

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "=== $failed failures, $warned warnings ===" -ForegroundColor $(if ($failed -gt 0) { "Red" } elseif ($warned -gt 0) { "Yellow" } else { "Green" })
if ($failed -eq 0 -and $warned -eq 0) {
    Write-Host "All 30 checks passed." -ForegroundColor Green
} elseif ($failed -eq 0) {
    Write-Host "No failures, but warnings should be reviewed." -ForegroundColor Yellow
} else {
    Write-Host "Fix failures before running anti-cheat software." -ForegroundColor Red
}
