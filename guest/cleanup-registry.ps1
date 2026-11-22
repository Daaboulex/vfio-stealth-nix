#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$cleaned = 0
$failures = 0
$skipped = 0

function Write-Failure([string]$Text) {
    Write-Host "[FAIL] $Text" -ForegroundColor Red
    $script:failures++
}

function Invoke-Step([string]$Name, [scriptblock]$Body) {
    try {
        & $Body
    } catch {
        Write-Failure "${Name}: $($_.Exception.Message)"
    }
}

function Remove-Found([string]$Path) {
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force
        $true
    } catch {
        Write-Failure "Could not remove ${Path}: $($_.Exception.Message)"
        $false
    }
}

function Write-Skip([string]$Text) {
    Write-Host "[SKIP] $Text" -ForegroundColor Yellow
    $script:skipped++
}

function Get-DriverInUse([string]$ServiceName) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
    if (Test-Path -LiteralPath $key) {
        $start = (Get-ItemProperty -LiteralPath $key).PSObject.Properties["Start"]
        if ($start -and $start.Value -eq 0) { return "its Start value is 0 (boot)" }
        if ($start -and $start.Value -eq 1) { return "its Start value is 1 (system)" }
    }
    if (@(Get-CimInstance Win32_BaseService -Filter "Name='$ServiceName' AND State='Running'").Count -gt 0) {
        return "it is running"
    }
    $null
}

function Remove-DriverServices([string[]]$Patterns) {
    $removed = 0
    foreach ($pattern in $Patterns) {
        if (Test-Path -Path $pattern) {
            foreach ($item in Get-Item -Path $pattern) {
                $reason = Get-DriverInUse $item.PSChildName
                if ($reason) {
                    Write-Skip "Kept driver service $($item.PSChildName): $reason"
                } elseif (Remove-Found $item.PSPath) {
                    $removed++
                }
            }
        }
    }
    $removed
}

function Remove-Devices([string[]]$Patterns) {
    $removed = 0
    $matched = @(Get-PnpDevice | Where-Object {
            $id = $_.InstanceId
            @($Patterns | Where-Object { $id -like $_ }).Count -gt 0
        })
    foreach ($device in $matched) {
        if ($device.Present) {
            Write-Skip "Kept device $($device.InstanceId): the device is present"
            continue
        }
        # why: pnputil /remove-device is the supported removal of a device with its Enum key; deleting the key by hand is not
        $output = & pnputil.exe /remove-device $device.InstanceId 2>&1
        if ($LASTEXITCODE -eq 0) {
            $removed++
        } else {
            Write-Failure "Could not remove $($device.InstanceId): $($output -join ' ')"
        }
    }
    $removed
}

Write-Host "=== vfio-stealth registry cleanup ===" -ForegroundColor Cyan
Write-Host ""

Invoke-Step "VirtIO services" {
    $removedServices = Remove-DriverServices @(
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
    Write-Host "[OK] Removed $removedServices VirtIO service entries" -ForegroundColor Green
    $script:cleaned++
}

Invoke-Step "QEMU/VirtIO PCI devices" {
    # why: AutoVirt rewrites these vendor IDs, so both the original and the rewritten ones are cleaned; on Intel QEMU's VGA keeps its device id 1111 under Intel's vendor
    $removedDevices = Remove-Devices @(
        "PCI\VEN_1AF4*",
        "PCI\VEN_1B36*",
        "PCI\VEN_1234*",
        "PCI\VEN_1022&DEV_1110*",
        "PCI\VEN_8086&DEV_1111*"
    )
    Write-Host "[OK] Removed $removedDevices QEMU/VirtIO PCI device entries" -ForegroundColor Green
    $script:cleaned++
}

Invoke-Step "QEMU Guest Agent" {
    $agents = @(Get-CimInstance Win32_Service | Where-Object {
            $_.Name -eq "QEMU-GA" -or $_.Name -eq "QEMU Guest Agent" -or $_.DisplayName -eq "QEMU Guest Agent"
        })
    foreach ($agent in $agents) {
        try {
            Stop-Service -Name $agent.Name -Force
        } catch {
            Write-Failure "Could not stop the guest agent service $($agent.Name): $($_.Exception.Message)"
            continue
        }
        $agentKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$($agent.Name)"
        if ((Test-Path -LiteralPath $agentKey) -and (Remove-Found $agentKey)) {
            Write-Host "[OK] Removed QEMU Guest Agent service key $($agent.Name)" -ForegroundColor Green
            $script:cleaned++
        }
    }
    $qgaPaths = @(
        "$env:ProgramFiles\QEMU Guest Agent",
        "$env:ProgramFiles\Qemu-ga",
        "${env:ProgramFiles(x86)}\QEMU Guest Agent"
    )
    foreach ($p in $qgaPaths) {
        if ((Test-Path -LiteralPath $p) -and (Remove-Found $p)) {
            Write-Host "[OK] Removed QEMU GA directory: $p" -ForegroundColor Green
            $script:cleaned++
        }
    }
}

Invoke-Step "QEMU display adapters" {
    $removedDisplay = Remove-Devices @(
        "DISPLAY\QEMU*",
        "DISPLAY\RHT*",
        "DISPLAY\Default_Monitor*"
    )
    Write-Host "[OK] Removed $removedDisplay QEMU display adapter entries" -ForegroundColor Green
    $script:cleaned++
}

Invoke-Step "VirtIO driver files" {
    $removedDrivers = 0
    $systemDrivers = @(Get-CimInstance Win32_SystemDriver | Where-Object { $_.PathName })
    foreach ($drv in Get-ChildItem -Path "$env:SystemRoot\System32\drivers\vio*.sys") {
        $owners = @($systemDrivers | Where-Object { (Split-Path -Path $_.PathName -Leaf) -eq $drv.Name })
        $reasons = @(foreach ($owner in $owners) {
                $reason = Get-DriverInUse $owner.Name
                if ($reason) { "service $($owner.Name): $reason" }
            })
        if ($reasons.Count -gt 0) {
            Write-Skip "Kept driver file $($drv.Name): $($reasons -join '; ')"
        } elseif (Remove-Found $drv.FullName) {
            $removedDrivers++
        }
    }
    if ($removedDrivers -gt 0) {
        Write-Host "[OK] Removed $removedDrivers VirtIO driver files from System32\drivers" -ForegroundColor Green
        $script:cleaned++
    }
}

Invoke-Step "Event logs" {
    $failuresBefore = $script:failures
    $clearedLogs = 0
    foreach ($log in @("System", "Application", "Setup")) {
        try {
            if ((Get-WinEvent -ListLog $log).RecordCount -eq 0) {
                continue
            }
            $vmEvents = @(Get-WinEvent -LogName $log | Where-Object {
                    $_.Message -match "QEMU|VirtIO|KVM|Red Hat|Hyper-V|Virtual|hypervisor|viostor|vioscsi|netkvm"
                })
            if ($vmEvents.Count -gt 0) {
                # why: events cannot be deleted one by one, so a contaminated log is cleared whole
                wevtutil cl $log
                if ($LASTEXITCODE -ne 0) {
                    Write-Failure "wevtutil could not clear the $log log (exit code $LASTEXITCODE)"
                } else {
                    $clearedLogs++
                }
            }
        } catch {
            Write-Failure "Could not read the $log log: $($_.Exception.Message)"
        }
    }
    if ($clearedLogs -gt 0) {
        Write-Host "[OK] Cleared $clearedLogs event logs containing VM references" -ForegroundColor Green
        Write-Host "     (System/Application/Setup logs were cleared entirely)" -ForegroundColor Yellow
        $script:cleaned++
    } elseif ($script:failures -eq $failuresBefore) {
        Write-Host "[OK] No VM references in event logs" -ForegroundColor Green
    }
}

Invoke-Step "SPICE Guest Tools" {
    $removedSpice = 0
    $spicePaths = @(
        "HKLM:\SYSTEM\CurrentControlSet\Services\vdagent",
        "HKLM:\SYSTEM\CurrentControlSet\Services\vdservice",
        "$env:ProgramFiles\SPICE Guest Tools",
        "${env:ProgramFiles(x86)}\SPICE Guest Tools"
    )
    foreach ($path in $spicePaths) {
        if ((Test-Path -LiteralPath $path) -and (Remove-Found $path)) { $removedSpice++ }
    }
    if ($removedSpice -gt 0) {
        Write-Host "[OK] Removed $removedSpice SPICE Guest Tools entries" -ForegroundColor Green
        $script:cleaned++
    }
}

Invoke-Step "Cached device descriptions" {
    $setupClasses = @(
        "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e96c-e325-11ce-bfc1-08002be10318}",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e97b-e325-11ce-bfc1-08002be10318}"
    )
    $driversInUse = @(Get-PnpDevice -PresentOnly | Get-PnpDeviceProperty -KeyName DEVPKEY_Device_Driver | ForEach-Object { $_.Data } | Where-Object { $_ })
    $cleanedDevMgr = 0
    foreach ($classPath in $setupClasses) {
        if (-not (Test-Path -LiteralPath $classPath)) {
            continue
        }
        $classGuid = Split-Path -Path $classPath -Leaf
        $instances = @((Get-Item -LiteralPath $classPath).GetSubKeyNames() | Where-Object { $_ -match "^\d{4}$" })
        foreach ($instance in $instances) {
            $instancePath = "$classPath\$instance"
            $desc = (Get-ItemProperty -LiteralPath $instancePath).PSObject.Properties["DriverDesc"]
            if (-not ($desc -and $desc.Value -match "QEMU|VirtIO|Red Hat|Bochs|Virtual")) {
                continue
            }
            if ($driversInUse -contains "$classGuid\$instance") {
                Write-Skip "Kept driver key $classGuid\$instance ($($desc.Value)): a present device uses it"
            } elseif (Remove-Found $instancePath) {
                $cleanedDevMgr++
            }
        }
    }
    if ($cleanedDevMgr -gt 0) {
        Write-Host "[OK] Removed $cleanedDevMgr cached device descriptions" -ForegroundColor Green
        $script:cleaned++
    }
}

Write-Host ""
if ($failures -gt 0) {
    Write-Host "Registry cleanup finished with $failures failures ($cleaned sections processed, $skipped skipped). Fix them, then reboot." -ForegroundColor Red
    exit 1
}
Write-Host "Registry cleanup complete ($cleaned sections processed, $skipped skipped). Reboot required." -ForegroundColor Cyan
exit 0
