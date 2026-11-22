param(
    [switch]$Register
)

$ErrorActionPreference = "Continue"
$media = $PSScriptRoot
$config = Get-Content -LiteralPath (Join-Path $media "vfio-probe.json") -Raw | ConvertFrom-Json
$port = New-Object System.IO.Ports.SerialPort "COM1", 115200, "None", 8, "One"
$port.Encoding = [System.Text.Encoding]::UTF8
$port.NewLine = "`n"
$port.Open()

function Send-Line([string]$Text) {
    $port.WriteLine($Text)
}

function Invoke-Section([string]$Name, [scriptblock]$Body) {
    Send-Line "VFIO-PROBE-BEGIN $Name"
    $global:LASTEXITCODE = 0
    try {
        $records = @(& $Body 2>&1)
        $code = $global:LASTEXITCODE
        if ($code -eq 0 -and @($records | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count -gt 0) {
            $code = 1
        }
        $output = $records | Out-String -Width 4096
    } catch {
        $output = $_ | Out-String -Width 4096
        $code = 1
    }
    foreach ($line in $output -split "`r?`n") {
        Send-Line $line
    }
    Send-Line "VFIO-PROBE-END $Name $code"
}

Send-Line "VFIO-PROBE-START"

if ($config.vbs -and -not (Test-Path -LiteralPath "C:\vbs-requested")) {
    Invoke-Section "vbs-enable" {
        $guard = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
        New-Item -Path "$guard\Scenarios\HypervisorEnforcedCodeIntegrity" -Force | Out-Null
        New-ItemProperty -Path $guard -Name EnableVirtualizationBasedSecurity -PropertyType DWord -Value 1 -Force | Out-Null
        New-ItemProperty -Path $guard -Name RequirePlatformSecurityFeatures -PropertyType DWord -Value 1 -Force | Out-Null
        New-ItemProperty -Path "$guard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name Enabled -PropertyType DWord -Value 1 -Force | Out-Null
        bcdedit /set hypervisorlaunchtype auto
        New-Item -ItemType File -Path "C:\vbs-requested" -Force | Out-Null
    }
    $port.Close()
    Restart-Computer -Force
    exit
}

if ($Register) {
    Invoke-Section "register" {
        $argument = '/c for %d in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do @if exist %d:\vfio-probe.json powershell.exe -NoProfile -ExecutionPolicy Bypass -File %d:\run.ps1'
        $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument $argument
        $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
        Register-ScheduledTask -TaskName "vfio-probe" -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        "registered vfio-probe for $env:USERNAME"
    }
}

Invoke-Section "windows" {
    Get-CimInstance Win32_OperatingSystem | Format-List Caption, Version, BuildNumber, OSArchitecture, OSLanguage, MUILanguages
}

Invoke-Section "elevation" {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.SecurityIdentifier]"S-1-5-32-544")
}

Invoke-Section "cleanup-registry" {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $media "cleanup-registry.ps1")
}

Invoke-Section "verify-stealth" {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $media "verify-stealth.ps1") -HypervMode $config.hypervMode
}

Invoke-Section "defender-exclusion" {
    Add-MpPreference -ExclusionPath (Join-Path $media "vmaware")
    (Get-MpPreference).ExclusionPath
}

$vmawareJson = Join-Path $env:TEMP "vmaware.json"
Invoke-Section "vmaware-run" {
    & (Join-Path $media "vmaware\vmaware.exe") --no-ansi --json --output $vmawareJson
}

Invoke-Section "vmaware" {
    Get-Content -LiteralPath $vmawareJson -Raw
}

Invoke-Section "pci-devices" {
    Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like "PCI\VEN_*" } | Select-Object -Property FriendlyName, InstanceId, Status, Class | ConvertTo-Json -Depth 3
}

Invoke-Section "device-guard" {
    Get-CimInstance -ClassName Win32_DeviceGuard -Namespace root\Microsoft\Windows\DeviceGuard | Select-Object -Property * -ExcludeProperty Cim* | ConvertTo-Json -Depth 4
}

Send-Line "VFIO-PROBE-DONE"
$port.Close()
Stop-Computer -Force
