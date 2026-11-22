param(
    [ValidateSet("enlightened", "hidden")]
    [string]$HypervMode = "enlightened"
)

$ErrorActionPreference = "Stop"
$failed = 0
$warned = 0
$skipped = 0

function Write-Result {
    param(
        [ValidateSet("PASS", "FAIL", "WARN", "SKIP")]
        [string]$Status,
        [string]$Text
    )
    switch ($Status) {
        "PASS" { $color = "Green" }
        "FAIL" { $color = "Red"; $script:failed++ }
        "WARN" { $color = "Yellow"; $script:warned++ }
        "SKIP" { $color = "Yellow"; $script:skipped++ }
    }
    Write-Host "[$Status] $Text" -ForegroundColor $color
}

function Invoke-Check([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
    } catch {
        Write-Result FAIL "${Name}: the check itself failed: $($_.Exception.Message)"
    }
}

function Get-HypervisorVendor {
    $x86Base = "System.Runtime.Intrinsics.X86.X86Base" -as [type]
    if ($null -eq $x86Base -or -not $x86Base::IsSupported) {
        return $null
    }
    $leaf = $x86Base::CpuId(0x40000000, 0)
    $bytes = [byte[]]([BitConverter]::GetBytes($leaf.Item2) + [BitConverter]::GetBytes($leaf.Item3) + [BitConverter]::GetBytes($leaf.Item4))
    [System.Text.Encoding]::ASCII.GetString($bytes).TrimEnd([char]0)
}

function Get-AcpiTableSignatures {
    if (-not ("VfioStealth.Firmware" -as [type])) {
        Add-Type -Namespace VfioStealth -Name Firmware -MemberDefinition '[DllImport("kernel32.dll", SetLastError = true)] public static extern uint EnumSystemFirmwareTables(uint provider, byte[] buffer, uint size);'
    }
    $acpiProvider = [uint32]0x41435049
    $size = [VfioStealth.Firmware]::EnumSystemFirmwareTables($acpiProvider, $null, 0)
    if ($size -eq 0) {
        throw "EnumSystemFirmwareTables failed with Win32 error $([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())"
    }
    $buffer = New-Object byte[] $size
    $read = [VfioStealth.Firmware]::EnumSystemFirmwareTables($acpiProvider, $buffer, $size)
    if ($read -ne $size) {
        throw "EnumSystemFirmwareTables returned $read bytes, expected $size"
    }
    $text = [System.Text.Encoding]::ASCII.GetString($buffer)
    for ($i = 0; $i -lt $text.Length; $i += 4) {
        $text.Substring($i, 4)
    }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host "=== vfio-stealth detection check ===" -ForegroundColor Cyan
Write-Host "Usage: verify-stealth.ps1 [-HypervMode enlightened|hidden]"
Write-Host "Judging the hypervisor bit against hypervMode '$HypervMode'. This script cannot read the NixOS config:"
Write-Host "pass the hypervMode the VM was built with (the module default is enlightened)."
Write-Host ""

Invoke-Check "Manufacturer" {
    $cs = Get-CimInstance Win32_ComputerSystem
    if ($cs.Manufacturer -match "QEMU|Bochs|Virtual|VMware|Xen|KVM|innotek") {
        Write-Result FAIL "Win32_ComputerSystem.Manufacturer: $($cs.Manufacturer)"
    } else {
        Write-Result PASS "Manufacturer: $($cs.Manufacturer)"
    }
}

Invoke-Check "BIOS Vendor" {
    $bios = Get-CimInstance Win32_BIOS
    if ($bios.Manufacturer -match "SeaBIOS|QEMU|Bochs|innotek|Phoenix Technologies.*Virtual") {
        Write-Result FAIL "BIOS Vendor: $($bios.Manufacturer)"
    } else {
        Write-Result PASS "BIOS: $($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)"
    }
}

Invoke-Check "BaseBoard" {
    $bb = Get-CimInstance Win32_BaseBoard
    if ($bb.Manufacturer -match "QEMU|Oracle|VMware|innotek") {
        Write-Result FAIL "BaseBoard: $($bb.Manufacturer)"
    } else {
        Write-Result PASS "BaseBoard: $($bb.Manufacturer) $($bb.Product)"
    }
}

Invoke-Check "VM services" {
    $vmServices = @("VBoxService", "VMTools", "QEMU*")
    $found = @(foreach ($service in Get-CimInstance Win32_Service) {
            $matched = $service.DisplayName -eq "QEMU Guest Agent"
            foreach ($pattern in $vmServices) {
                if ($service.Name -like $pattern) { $matched = $true }
            }
            if ($matched) { $service.Name }
        })
    if ($found.Count -gt 0) {
        Write-Result FAIL "VM service found: $($found -join ', ')"
    } else {
        Write-Result PASS "No VM-specific services detected"
    }
}

Invoke-Check "Hyper-V integration services" {
    $integrationServices = @("vmicheartbeat", "vmicshutdown", "vmickvpexchange", "vmicvss", "vmictimesync", "vmicguestinterface", "vmicrdv", "vmicvmsession")
    $running = @(Get-CimInstance Win32_Service | Where-Object { $integrationServices -contains $_.Name -and $_.State -eq "Running" } | ForEach-Object { $_.Name })
    if ($running.Count -gt 0) {
        Write-Result FAIL "Hyper-V integration services running, so the guest found a Hyper-V host: $($running -join ', ')"
    } else {
        Write-Result PASS "No Hyper-V integration service running (they exist on every Windows install)"
    }
}

Invoke-Check "VM PCI devices" {
    $pci = @(Get-PnpDevice | Where-Object { $_.DeviceId -match "VEN_1AF4|VEN_1B36|VEN_1234" })
    if ($pci.Count -gt 0) {
        Write-Result FAIL "VM PCI devices: $($pci.Count) found"
        $pci | ForEach-Object { Write-Host "       $($_.DeviceId)" -ForegroundColor Red }
    } else {
        Write-Result PASS "No VirtIO/QEMU PCI devices"
    }
}

Invoke-Check "Win32_Fan" {
    $fans = @(Get-CimInstance Win32_Fan)
    if ($fans.Count -gt 0) {
        Write-Result PASS "Win32_Fan present ($($fans.Count) fans)"
    } else {
        Write-Result WARN "Win32_Fan empty (ACPI SSDT may not be loaded)"
    }
}

Invoke-Check "Battery" {
    $battery = @(Get-CimInstance Win32_Battery)
    if ($battery.Count -gt 0) {
        Write-Result PASS "Battery present"
    } else {
        Write-Result WARN "No battery (fake-battery.aml may not be loaded)"
    }
}

Invoke-Check "Physical memory" {
    $mem = @(Get-CimInstance Win32_PhysicalMemory)
    if ($mem.Count -ge 1 -and -not [string]::IsNullOrWhiteSpace($mem[0].Manufacturer)) {
        Write-Result PASS "Physical memory: $($mem.Count) DIMMs, $($mem[0].Manufacturer)"
    } else {
        Write-Result WARN "No physical memory info (SMBIOS type 17 may be missing)"
    }
}

Invoke-Check "HypervisorPresent" {
    $present = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
    if ($null -eq $present) {
        Write-Result SKIP "HypervisorPresent: this Windows does not report it in Win32_ComputerSystem"
        return
    }
    $vendor = Get-HypervisorVendor
    $vendorText = if ($null -eq $vendor) { "vendor not readable in this PowerShell; run it in PowerShell 7 to see it" } else { "vendor '$vendor'" }
    $vbs = (Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard).VirtualizationBasedSecurityStatus
    if ($HypervMode -eq "hidden") {
        if ($present -and $vbs -eq 2) {
            Write-Result PASS "HypervisorPresent = True ($vendorText): Windows' own hypervisor runs for VBS, as on a PC with VBS on"
        } elseif ($present) {
            Write-Result FAIL "HypervisorPresent = True ($vendorText); hypervMode hidden turns the CPUID hypervisor bit off"
        } else {
            Write-Result PASS "HypervisorPresent = False, as hypervMode hidden expects"
        }
    } elseif (-not $present) {
        Write-Result WARN "HypervisorPresent = False, but hypervMode enlightened shows the hypervisor bit; if the VM was built with hypervMode hidden, run with -HypervMode hidden"
    } elseif ($vendor -eq "KVMKVMKVM") {
        Write-Result FAIL "HypervisorPresent = True with vendor 'KVMKVMKVM'; the module sets kvm hidden, which conceals the KVM signature"
    } else {
        Write-Result PASS "HypervisorPresent = True ($vendorText), as hypervMode enlightened expects"
    }
}

Invoke-Check "Disk model" {
    $disks = @(Get-CimInstance Win32_DiskDrive)
    $vmDisk = @($disks | Where-Object { $_.Model -match "QEMU HARDDISK|VBOX HARDDISK|VirtIO|QEMU DVD-ROM|VBOX CD-ROM" })
    if ($vmDisk.Count -gt 0) {
        Write-Result FAIL "VM disk model: $($vmDisk.Model -join ', ')"
    } else {
        $diskInfo = if ($disks.Count -gt 0) { $disks[0].Model } else { "none" }
        Write-Result PASS "Disk model: $diskInfo"
    }
}

Invoke-Check "Disk firmware" {
    $disks = @(Get-CimInstance Win32_DiskDrive)
    $vmFirmware = @($disks | Where-Object { $_.FirmwareRevision -match "^2\.5\+" })
    if ($vmFirmware.Count -gt 0) {
        Write-Result FAIL "QEMU disk firmware revision: $($vmFirmware.FirmwareRevision -join ', ')"
    } else {
        $firmwareInfo = if ($disks.Count -gt 0) { $disks[0].FirmwareRevision } else { "none" }
        Write-Result PASS "Disk firmware: $firmwareInfo"
    }
}

Invoke-Check "Optical drive" {
    $cdrom = @(Get-CimInstance Win32_CDROMDrive)
    $vmCd = @($cdrom | Where-Object { $_.Name -match "QEMU HARDDISK|VBOX HARDDISK|VirtIO|QEMU DVD-ROM|QEMU CD-ROM|VBOX CD-ROM" })
    if ($vmCd.Count -gt 0) {
        Write-Result FAIL "VM optical drive: $($vmCd.Name -join ', ')"
    } else {
        $cdInfo = if ($cdrom.Count -gt 0) { $cdrom[0].Name } else { "none" }
        Write-Result PASS "Optical drive: $cdInfo"
    }
}

Invoke-Check "Chassis" {
    $chassis = Get-CimInstance Win32_SystemEnclosure
    if ($chassis.Manufacturer -match "QEMU|Bochs|Virtual|VMware|innotek") {
        Write-Result FAIL "Chassis manufacturer: $($chassis.Manufacturer)"
    } else {
        Write-Result PASS "Chassis: $($chassis.Manufacturer)"
    }
}

Invoke-Check "CacheMemory" {
    $caches = @(Get-CimInstance Win32_CacheMemory)
    if ($caches.Count -ge 2) {
        $sizes = ($caches | ForEach-Object { "$($_.Purpose) $($_.InstalledSize)KB" }) -join ", "
        Write-Result PASS "CacheMemory: $($caches.Count) levels ($sizes)"
    } else {
        Write-Result WARN "CacheMemory: $($caches.Count) entries (VMs have none by default)"
    }
}

Invoke-Check "SystemSlot" {
    $slots = @(Get-CimInstance Win32_SystemSlot)
    if ($slots.Count -gt 0) {
        Write-Result PASS "SystemSlot: $($slots.Count) slots"
    } else {
        Write-Result WARN "No system slots (VMs lack SMBIOS type 9)"
    }
}

Invoke-Check "TemperatureProbe" {
    $tempProbe = @(Get-CimInstance Win32_TemperatureProbe)
    if ($tempProbe.Count -gt 0) {
        Write-Result PASS "TemperatureProbe present"
    } else {
        Write-Result WARN "No TemperatureProbe (SMBIOS type 28 may be missing)"
    }
}

Invoke-Check "VoltageProbe" {
    $voltProbe = @(Get-CimInstance Win32_VoltageProbe)
    if ($voltProbe.Count -gt 0) {
        Write-Result PASS "VoltageProbe present"
    } else {
        Write-Result WARN "No VoltageProbe (SMBIOS type 26 may be missing)"
    }
}

Invoke-Check "CurrentProbe" {
    $curProbe = @(Get-CimInstance Win32_CurrentProbe)
    if ($curProbe.Count -gt 0) {
        Write-Result PASS "CurrentProbe present"
    } else {
        Write-Result WARN "No CurrentProbe (SMBIOS type 29 may be missing)"
    }
}

Invoke-Check "ACPI ThermalZone" {
    if (-not $isAdmin) {
        Write-Result SKIP "MSAcpi_ThermalZoneTemperature (requires Administrator)"
        return
    }
    try {
        $tz = @(Get-CimInstance -Namespace root\wmi -ClassName MSAcpi_ThermalZoneTemperature)
    } catch [Microsoft.Management.Infrastructure.CimException] {
        if ($_.Exception.NativeErrorCode -ne [Microsoft.Management.Infrastructure.NativeErrorCode]::NotSupported) {
            throw
        }
        $tz = @()
    }
    if ($tz.Count -gt 0) {
        Write-Result PASS "ACPI ThermalZone present ($($tz.Count) zone(s))"
    } else {
        Write-Result WARN "No ACPI ThermalZone (sensor-probes.aml may not be loaded)"
    }
}

Invoke-Check "NIC" {
    $nics = @(Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter -eq $true })
    $vmNic = @($nics | Where-Object { $_.Description -match "VirtIO|Virtio|Red Hat|QEMU|VMware|VirtualBox|Hyper-V" })
    if ($vmNic.Count -gt 0) {
        Write-Result FAIL "VM NIC detected: $($vmNic[0].Description)"
    } else {
        $nicInfo = if ($nics.Count -gt 0) { $nics[0].Description } else { "none" }
        Write-Result PASS "NIC: $nicInfo"
    }
}

Invoke-Check "EDID" {
    $displayKey = "HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY"
    if (-not (Test-Path -LiteralPath $displayKey)) {
        Write-Result WARN "EDID: no monitor entries found"
        return
    }
    $monitors = @((Get-Item -LiteralPath $displayKey).GetSubKeyNames())
    $vmMonitor = @($monitors | Where-Object { $_ -match "^(RHT|QEMU|VBOX|Default_Monitor)" })
    if ($vmMonitor.Count -gt 0) {
        Write-Result FAIL "EDID registry: VM monitor ID '$($vmMonitor -join "', '")'"
    } elseif ($monitors.Count -gt 0) {
        Write-Result PASS "EDID: no VM monitor IDs in registry ($($monitors -join ', '))"
    } else {
        Write-Result WARN "EDID: no monitor entries found"
    }
}

Invoke-Check "ACPI OEM" {
    $tables = @(foreach ($table in "DSDT", "FADT", "RSDT") {
            $key = "HKLM:\HARDWARE\ACPI\$table"
            if (Test-Path -LiteralPath $key) {
                foreach ($oemId in (Get-Item -LiteralPath $key).GetSubKeyNames()) {
                    foreach ($oemTableId in (Get-Item -LiteralPath "$key\$oemId").GetSubKeyNames()) {
                        "$table $oemId/$oemTableId"
                    }
                }
            }
        })
    $vmTables = @($tables | Where-Object { $_ -match "BOCHS|BXPC|QEMU" })
    if ($tables.Count -eq 0) {
        Write-Result WARN "ACPI OEM: no DSDT, FADT or RSDT key under HKLM:\HARDWARE\ACPI"
    } elseif ($vmTables.Count -gt 0) {
        Write-Result FAIL "ACPI OEM: VM IDs in ACPI table headers ($($vmTables -join ', '))"
    } else {
        Write-Result PASS "ACPI OEM: $($tables -join ', ')"
    }
}

Invoke-Check "BIOS date" {
    $bios = Get-CimInstance Win32_BIOS
    if ($bios.ReleaseDate) {
        $biosDate = $bios.ReleaseDate
        $suspectDates = @("20140401", "20201111", "20060101", "20220202")
        $dateStr = $biosDate.ToString("yyyyMMdd")
        if ($suspectDates -contains $dateStr) {
            Write-Result FAIL "BIOS date suspicious: $($biosDate.ToString('yyyy-MM-dd')) (known VM default)"
        } else {
            Write-Result PASS "BIOS date: $($biosDate.ToString('yyyy-MM-dd'))"
        }
    } else {
        Write-Result WARN "BIOS date unavailable"
    }
}

Invoke-Check "BaseBoard serial" {
    $bb = Get-CimInstance Win32_BaseBoard
    if ([string]::IsNullOrWhiteSpace($bb.SerialNumber) -or $bb.SerialNumber -eq "None" -or $bb.SerialNumber -eq "Default string") {
        Write-Result WARN "BaseBoard serial empty or default: '$($bb.SerialNumber)'"
    } else {
        Write-Result PASS "BaseBoard serial: $($bb.SerialNumber)"
    }
}

Invoke-Check "CPU name" {
    $cpu = @(Get-CimInstance Win32_Processor)
    if ($cpu.Count -eq 0) {
        Write-Result FAIL "Win32_Processor returned no processor"
    } elseif ($cpu.Name -match "QEMU|KVM|Virtual") {
        Write-Result FAIL "CPU name: $($cpu[0].Name)"
    } else {
        Write-Result PASS "CPU: $($cpu[0].Name)"
    }
}

Invoke-Check "ivshmem" {
    $ivshmem = @(Get-PnpDevice | Where-Object { $_.DeviceId -match "VEN_(1AF4|1022)&DEV_1110" })
    if ($ivshmem.Count -gt 0) {
        Write-Result FAIL "ivshmem device found: $($ivshmem[0].DeviceId)"
    } else {
        Write-Result PASS "No ivshmem device"
    }
}

Invoke-Check "QEMU Guest Agent" {
    $qga = @(Get-Process | Where-Object { $_.ProcessName -eq "qemu-ga" })
    if ($qga.Count -gt 0) {
        Write-Result FAIL "QEMU Guest Agent process running (qemu-ga.exe)"
    } else {
        Write-Result PASS "No QEMU Guest Agent process"
    }
}

Invoke-Check "VirtIO drivers" {
    $vioDrivers = @(Get-ChildItem -Path "$env:SystemRoot\System32\drivers\vio*.sys")
    if ($vioDrivers.Count -gt 0) {
        Write-Result FAIL "VirtIO drivers found: $($vioDrivers.Name -join ', ')"
    } else {
        Write-Result PASS "No VirtIO driver files"
    }
}

Invoke-Check "Hyper-V guest parameters" {
    $hvKey = "HKLM:\SOFTWARE\Microsoft\Virtual Machine\Guest\Parameters"
    if (-not (Test-Path -LiteralPath $hvKey)) {
        Write-Result PASS "No Hyper-V guest parameters key"
        return
    }
    $vmName = (Get-ItemProperty -LiteralPath $hvKey).PSObject.Properties["VirtualMachineName"]
    if ($vmName) {
        Write-Result WARN "Hyper-V guest params key exists (VirtualMachineName=$($vmName.Value))"
    } else {
        Write-Result WARN "Hyper-V guest params key exists"
    }
}

Invoke-Check "Model" {
    $cs = Get-CimInstance Win32_ComputerSystem
    if ($cs.Model -match "QEMU|Bochs|Virtual|Standard PC|KVM|VirtualBox") {
        Write-Result FAIL "ComputerSystem.Model: $($cs.Model)"
    } else {
        Write-Result PASS "Model: $($cs.Model)"
    }
}

Invoke-Check "SMBIOS OEM strings" {
    $cs = Get-CimInstance Win32_ComputerSystem
    $oemStrings = @($cs.OEMStringArray | Where-Object { $_ })
    $vmValues = @(@($oemStrings) + @($cs.SystemFamily) | Where-Object { $_ -match "QEMU|Virtual|Bochs" })
    if ($vmValues.Count -gt 0) {
        Write-Result FAIL "SMBIOS OEM strings/SystemFamily: $($vmValues -join ', ')"
    } elseif ($oemStrings.Count -eq 0) {
        Write-Result WARN "SMBIOS OEM strings empty (type 11 missing), SystemFamily '$($cs.SystemFamily)'"
    } else {
        Write-Result PASS "SMBIOS OEM strings clean ($($oemStrings.Count) entries), SystemFamily '$($cs.SystemFamily)'"
    }
}

Invoke-Check "PortConnector" {
    $ports = @(Get-CimInstance Win32_PortConnector)
    if ($ports.Count -ge 1) {
        Write-Result PASS "PortConnector: $($ports.Count) entries"
    } else {
        Write-Result WARN "No PortConnector entries (SMBIOS type 8 missing)"
    }
}

Invoke-Check "CoolingDevice" {
    $cooling = @(Get-CimInstance CIM_CoolingDevice)
    if ($cooling.Count -gt 0) {
        Write-Result PASS "CoolingDevice: $($cooling.Count) device(s)"
    } else {
        Write-Result WARN "No CIM_CoolingDevice (SMBIOS type 27 missing)"
    }
}

Invoke-Check "OnBoardDevice" {
    $onboard = @(Get-CimInstance Win32_OnBoardDevice)
    if ($onboard.Count -gt 0) {
        Write-Result PASS "OnBoardDevice: $($onboard.Count) device(s)"
    } else {
        Write-Result WARN "No OnBoardDevice entries (SMBIOS type 41 missing)"
    }
}

Invoke-Check "Disk serial" {
    $diskSerial = @(Get-CimInstance Win32_DiskDrive | ForEach-Object { $_.SerialNumber } | Where-Object { $_ })
    $vmSerial = @($diskSerial | Where-Object { $_ -match "^QM\d|^VBOX|^drive-|^QEMU" })
    if ($vmSerial.Count -gt 0) {
        Write-Result FAIL "VM disk serial: $($vmSerial -join ', ')"
    } elseif ($diskSerial.Count -gt 0) {
        $shortSerial = @($diskSerial | Where-Object { $_.Length -lt 8 })
        if ($shortSerial.Count -gt 0) {
            Write-Result WARN "Disk serial suspiciously short: $($shortSerial -join ', ')"
        } else {
            Write-Result PASS "Disk serial: $($diskSerial[0])"
        }
    } else {
        Write-Result WARN "No disk serial returned"
    }
}

Invoke-Check "MAC OUI" {
    $vmOuis = @("52:54:00", "08:00:27", "00:0C:29", "00:50:56", "00:15:5D", "00:16:3E")
    $physNics = @(Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter -eq $true -and $_.MACAddress })
    $vmNics = @(foreach ($nic in $physNics) {
            $oui = ($nic.MACAddress -split ":")[0..2] -join ":"
            if ($vmOuis -contains $oui) { "$oui on $($nic.Description)" }
        })
    if ($vmNics.Count -gt 0) {
        Write-Result FAIL "VM MAC OUI $($vmNics -join ', ')"
    } elseif ($physNics.Count -gt 0) {
        $firstOui = ($physNics[0].MACAddress -split ":")[0..2] -join ":"
        Write-Result PASS "MAC OUI: $firstOui ($($physNics[0].Description))"
    } else {
        Write-Result WARN "No physical adapters with MAC address"
    }
}

Invoke-Check "ACPI BGRT" {
    $signatures = @(Get-AcpiTableSignatures)
    if ($signatures -contains "BGRT") {
        Write-Result FAIL "ACPI BGRT table present: the firmware boot logo table leaks; the stealth OVMF is built without it"
    } else {
        Write-Result PASS "No ACPI BGRT table, as the stealth OVMF builds"
    }
}

Invoke-Check "VMPort" {
    if (Test-Path -LiteralPath "HKLM:\SOFTWARE\VMware, Inc.\VMware Tools") {
        Write-Result FAIL "VMware Tools registry key present"
    } elseif (@(Get-Process | Where-Object { $_.ProcessName -eq "vmtoolsd" }).Count -gt 0) {
        Write-Result FAIL "vmtoolsd process running"
    } else {
        Write-Result PASS "No VMPort indicators"
    }
}

Invoke-Check "SCSI DEVICEMAP" {
    $scsiMap = "HKLM:\HARDWARE\DEVICEMAP\Scsi"
    $hits = @()
    if (Test-Path -LiteralPath $scsiMap) {
        $hits = @(foreach ($key in Get-ChildItem -LiteralPath $scsiMap -Recurse) {
                $props = Get-ItemProperty -LiteralPath $key.PSPath
                foreach ($name in @("Identifier", "DeviceIdentifier", "InquiryData")) {
                    $val = $props.$name
                    if ($val -is [string] -and $val -match "QEMU|qemu|Bochs|VBOX") { "'$name': $val" }
                }
            })
    }
    if ($hits.Count -gt 0) {
        Write-Result FAIL "SCSI DEVICEMAP $($hits -join ', ')"
    } else {
        Write-Result PASS "No QEMU identifiers in SCSI DEVICEMAP"
    }
}

Invoke-Check "Raw SMBIOS" {
    if (-not $isAdmin) {
        Write-Result SKIP "Raw SMBIOS read (requires Administrator for root\wmi)"
        return
    }
    $smbiosData = (Get-CimInstance -Namespace root\wmi -ClassName MSSMBios_RawSMBiosTables).SMBiosData
    if ($smbiosData) {
        $smbiosStr = [System.Text.Encoding]::ASCII.GetString($smbiosData)
        if ($smbiosStr -match "QEMU|qemu|Bochs|bochs") {
            Write-Result FAIL "Raw SMBIOS blob contains VM string"
        } else {
            Write-Result PASS "Raw SMBIOS blob clean"
        }
    } else {
        Write-Result SKIP "MSSMBios_RawSMBiosTables returned no SMBIOS data"
    }
}

Invoke-Check "SPICE" {
    $spiceProcs = @("vdagent", "vdservice")
    $spiceFound = @(Get-Process | Where-Object { $spiceProcs -contains $_.ProcessName } | ForEach-Object { $_.ProcessName })
    if ($spiceFound.Count -gt 0) {
        Write-Result FAIL "SPICE process running: $($spiceFound -join ', ')"
    } else {
        Write-Result PASS "No SPICE Guest Tools processes"
    }
}

Write-Host ""
Write-Host "=== $failed failures, $warned warnings, $skipped skipped ===" -ForegroundColor $(if ($failed -gt 0) { "Red" } elseif ($warned -gt 0 -or $skipped -gt 0) { "Yellow" } else { "Green" })
if ($failed -eq 0 -and $warned -eq 0 -and $skipped -eq 0) {
    Write-Host "All checks passed." -ForegroundColor Green
} elseif ($failed -eq 0 -and $skipped -gt 0) {
    Write-Host "0 failures, $warned warnings, $skipped skipped" -ForegroundColor Yellow
} elseif ($failed -eq 0) {
    Write-Host "No failures, but warnings should be reviewed." -ForegroundColor Yellow
} else {
    Write-Host "Fix failures before running game security software." -ForegroundColor Red
}
if ($failed -gt 0) {
    exit 1
}
exit 0
