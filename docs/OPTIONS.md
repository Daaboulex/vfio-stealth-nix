# Options

Every option the modules of this flake declare. This file is generated from the module sources: change a description there, then run `nix run .#std-write-option-reference`.

## NixOS module

### `virtualisation.vfio-stealth.enable`

Whether to enable VFIO hardware emulation stack.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.acpi.c2Latency`

Worst-case C2 latency in microseconds the FADT reports (P_LVL2_LAT); above 100 means the CPU has no C2. The default 101 is what a desktop board with AMI firmware reports. VMAware's FIRMWARE check flags QEMU's own 0x0FFF. Goes into packages.qemu.

Type: `16 bit unsigned integer; between 0 and 65535 (both inclusive)`. Default: `101`.

### `virtualisation.vfio-stealth.acpi.c3Latency`

Worst-case C3 latency in microseconds the FADT reports (P_LVL3_LAT); above 1000 means the CPU has no C3. The default 1001 is what a desktop board with AMI firmware reports. VMAware's FIRMWARE check flags QEMU's own 0x0FFF. Goes into packages.qemu.

Type: `16 bit unsigned integer; between 0 and 65535 (both inclusive)`. Default: `1001`.

### `virtualisation.vfio-stealth.acpi.waet`

Give the guest the WAET ACPI table, which the AutoVirt patch removes. With it, Windows knows its RTC and ACPI PM timer are emulated and skips the workarounds it otherwise runs for them, which slow timer reads and can stall HAL init. Without it, the table that only virtual machines carry is gone, and VMAware's FIRMWARE check no longer finds it; that check also reads acpi.c2Latency and acpi.c3Latency. Goes into packages.qemu.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.acpiOem.id`

6-char ACPI OEM ID (padded with spaces). Populates ACPI table header OEM ID field. Goes into packages.qemu and packages.acpiTables.

Type: `string matching the pattern ^[A-Za-z0-9 _.-]{6}$`. Default: `"ALASKA"`.

### `virtualisation.vfio-stealth.acpiOem.tableId`

8-char ACPI OEM Table ID (padded with spaces). Populates ACPI table header OEM Table ID field. Goes into packages.qemu and packages.acpiTables.

Type: `string matching the pattern ^[A-Za-z0-9 _.-]{8}$`. Default: `"A M I   "`.

### `virtualisation.vfio-stealth.acpiProcessors`

Builds the SSDT that gives a VM one ACPI processor device per vCPU, under a processor container, as real firmware does; QEMU's own processor objects are removed by the vendor patch. Each VM in domains gets it with its vCPU count; a VM defined by hand passes `-acpitable file=` with it.

Type: `function that evaluates to a(n) package`. Default: a function from a vCPU count to an SSDT. Read only.

### `virtualisation.vfio-stealth.acpiSsdt.batterySerial`

The serial number the emulated battery's _BIF reports. Populates WMI BatteryStaticData.SerialNumber. Goes into packages.acpiTables.

Type: `string matching the pattern [A-Za-z0-9]{1,16}`. Default: five digits derived from identity.seed, or `"41167"` without one.

### `virtualisation.vfio-stealth.acpiSsdt.fakeBattery`

Include an emulated ACPI battery device in the SSDT table. Covers the 'no battery = server/VM' heuristic.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.acpiSsdt.sensorProbes`

Include CPU and VRM thermal zone probes (covers MSAcpi_ThermalZoneTemperature WMI checks).

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.acpiSsdt.spoofedDevices`

Include emulated ACPI device entries in the SSDT table. Covers ACPI namespace enumeration checks.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.aperfMperf`

Pass through IA32_APERF/MPERF MSRs to guest (addresses IET-based VM indicators), in a VM with cpuPm on, the only one QEMU offers them to. Requires kernel 6.18+.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.bootCheck`

A build that starts this host's packages.qemu with packages.ovmf and domain.qemuArgs under KVM, as libvirt starts them, and boots a probe kernel from a SATA disk, a virtio disk and a SATA CD with SMBIOS emulated and from domain.sysinfo. It also checks that the Secure Boot firmware boots with no keys, refuses an unsigned loader with the Microsoft keys, and with an enrolled test key boots only the signed copy. Build it with `nix build /etc/nixos#nixosConfigurations.<host>.config.virtualisation.vfio-stealth.bootCheck -L`; it needs /dev/kvm, and its output holds every serial log and an evidence.json of what each guest reported. A boot that stalls is retried, up to three boots per case.

Type: `package`. Default: a build that boots this host's packages and domain.qemuArgs. Read only.

### `virtualisation.vfio-stealth.cet`

Show the guest the host CPU's control-flow enforcement, shadow stacks and indirect branch tracking, as hardware does. Off by default with Intel: under KVM on an Intel host, Windows' own Hyper-V, which VBS and HVCI run on, does not start while the guest sees CET.

Type: `boolean`. Default: `cpuVendor == "amd"`.

### `virtualisation.vfio-stealth.cpuIdentity.characteristics`

SMBIOS type 4 Characteristics bit field per DSP0134 7.5.9; 252 is the 64-bit capable, Multi-Core, Hardware Thread, Execute Protection, Enhanced Virtualization and Power/Performance Control both boards report, in place of QEMU's Unknown. Populates WMI Win32_Processor.Characteristics. null takes the value smbios/processor-defaults.nix gives cpuVendor: 252 on amd, 252 on intel, read from real AM5 and LGA1700 boards.

Type: `null or 16 bit unsigned integer; between 0 and 65535 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.cpuIdentity.currentSpeed`

CPU current speed in MHz for SMBIOS type 4, as the Current Speed line of `dmidecode -t 4` shows it. null leaves QEMU's 2000.

Type: `null or integer between 1 and 65535 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.cpuIdentity.externalClock`

SMBIOS type 4 External Clock in MHz, in place of QEMU's Unknown. Populates WMI Win32_Processor.ExtClock. null takes the value smbios/processor-defaults.nix gives cpuVendor: 100 on amd, 100 on intel, read from real AM5 and LGA1700 boards.

Type: `null or integer between 1 and 65535 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.cpuIdentity.family`

SMBIOS type 4 Family number per DSP0134 7.5.2, such as 107 for Zen, 198 for Core i7, 205 for Core i5 and 207 for Core i9, in place of QEMU's 1, Other. Populates WMI Win32_Processor.Family. null takes the value smbios/processor-defaults.nix gives cpuVendor: 107 on amd, 198 on intel, read from real AM5 and LGA1700 boards.

Type: `null or integer between 1 and 65533 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.cpuIdentity.manufacturer`

CPU manufacturer for SMBIOS type 4, as the Manufacturer line of `dmidecode -t 4` shows it. null takes the name smbios/processor-defaults.nix gives cpuVendor: Advanced Micro Devices, Inc. on amd, Intel(R) Corporation on intel.

Type: `null or string`. Default: `null`.

### `virtualisation.vfio-stealth.cpuIdentity.maxSpeed`

CPU max speed in MHz for SMBIOS type 4, as the Max Speed line of `dmidecode -t 4` shows it. null leaves QEMU's 2000.

Type: `null or integer between 1 and 65535 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.cpuIdentity.modelId`

CPU model string reported to guest (e.g. 'AMD Ryzen 7 7800X3D 8-Core Processor'), in CPUID and as the SMBIOS type 4 Version. null keeps the host CPU's, which type 4 then names too.

Type: `null or string`. Default: `null`.

### `virtualisation.vfio-stealth.cpuIdentity.socket`

SMBIOS type 4 Socket Designation, as `dmidecode -t 4` shows it, in place of QEMU's CPU and an instance number. Populates WMI Win32_Processor.SocketDesignation. null takes the value smbios/processor-defaults.nix gives cpuVendor: "AM5" on amd, "LGA1700" on intel, read from real AM5 and LGA1700 boards.

Type: `null or string matching the pattern [ -~]{1,64}`. Default: `null`.

### `virtualisation.vfio-stealth.cpuIdentity.upgrade`

SMBIOS type 4 Upgrade byte per DSP0134 7.5.5, the socket: 73 = Socket AM5, 49 = Socket AM4, 64 = Socket LGA1700, 85 = Socket LGA1851, in place of QEMU's 1, Other. Populates WMI Win32_Processor.UpgradeMethod. null takes the value smbios/processor-defaults.nix gives cpuVendor: 73 on amd, 64 on intel, read from real AM5 and LGA1700 boards.

Type: `null or integer between 1 and 255 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.cpuIdentity.voltageDecivolts`

SMBIOS type 4 Voltage in tenths of a volt, 13 for the 1.3 V `dmidecode -t 4` shows, in place of QEMU's Unknown. Populates WMI Win32_Processor.CurrentVoltage. null takes the value smbios/processor-defaults.nix gives cpuVendor: 13 on amd, 14 on intel, read from real AM5 and LGA1700 boards.

Type: `null or integer between 1 and 127 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.cpuVendor`

Host CPU vendor. There is no default, and an enabled module refuses null. It picks the QEMU and OVMF pair in packages, the AMD-only kernel options and patches, and the CPU flags in domain. "intel" refuses the kernel options that patch KVM's SVM code: timing.enable, cpuidSpoof.enable, cpuidPassthrough.enable and cpuidPassthrough.pinned.

Type: `null or one of "amd", "intel"`. Default: `null`. Example: `"amd"`.

### `virtualisation.vfio-stealth.cpuidPassthrough.enable`

Disable CPUID interception entirely. Guest executes CPUID at native hardware speed (zero VM exit). Addresses software-counter timing checks such as VMAware's TIMER and SINGLE_STEP. Requires AMD host with host-passthrough CPU mode. When enabled, cpuidSpoof is skipped (passthrough takes precedence). Side effect: Hyper-V enlightenments are invisible to guest (Windows uses TSC directly). LIMITATION: the guest sees the host's raw topology (core count, thread count, NUMA nodes) via CPUID; if the VM has fewer vCPUs than the host has threads, Windows deadlocks at boot waiting for processors that do not exist.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.cpuidPassthrough.pinned`

Add vfio-native's experimental runtime CPUID passthrough to kernelPostPatch. Writing 1 to /sys/module/kvm_amd/parameters/cpuid_passthrough after the guest has booted stops CPUID exits on vCPUs pinned 1:1 to a host core, and kvm_amd.brand_string sets the processor name the guest then reads; Windows hangs when it is switched on during boot. AMD hosts only, and not with cpuidPassthrough.enable.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.cpuidSpoof.enable`

Add the CPUID leaf 0 fast path (from AutoVirt, formerly Hypervisor-Phantom) to kernelPostPatch. A guest CPUID with EAX = 0 is answered right after the VM exit with the VM's own CPUID leaf 0, the values KVM would give, and the guest is re-entered without the rest of the exit handling. The patch also clears the RDTSC and RDTSCP intercepts, which the timing.enable patch sets again. No other leaf is changed: the hypervisor-present bit (leaf 1, bit 31) and the hypervisor vendor leaf (0x40000000) are not touched. Skipped when cpuidPassthrough.enable is true.

Type: `boolean`. Default: `cpuVendor == "amd"`.

### `virtualisation.vfio-stealth.devices.acpiCreator.id`

The acpiCreator.id an emulated QEMU device reports in place of QEMU's own: the 4-character creator id of a headerless -acpitable, such as "AMI ". The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Z0-9 ]{4}`. Default: `"AMI "`.

### `virtualisation.vfio-stealth.devices.acpiCreator.revision`

The acpiCreator.revision an emulated QEMU device reports in place of QEMU's own: the 32-bit creator revision. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `integer between 0 and 4294967295 (both inclusive)`. Default: `65555`.

### `virtualisation.vfio-stealth.devices.megasas.package`

The megasas.package an emulated QEMU device reports in place of QEMU's own: an LSI package version such as 12.15.0-0239. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [0-9][0-9.-]{0,31}`. Default: `"12.15.0-0239"`.

### `virtualisation.vfio-stealth.devices.megasas.serialDigits`

The megasas.serialDigits an emulated QEMU device reports in place of QEMU's own: the count of digits derived from the VM uuid and the card's PCI path, 1 to 16. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `integer between 1 and 16 (both inclusive)`. Default: `8`.

### `virtualisation.vfio-stealth.devices.megasas.serialPrefix`

The megasas.serialPrefix an emulated QEMU device reports in place of QEMU's own: 0 to 4 upper-case letters put before the serial's digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Z]{0,4}`. Default: `"SV"`.

### `virtualisation.vfio-stealth.devices.usbAudio.manufacturer`

The usbAudio.manufacturer an emulated QEMU device reports in place of QEMU's own: 1 to 64 letters, digits, spaces or any of .,()/+_-. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Za-z0-9 .,()/+_-]{1,64}`. Default: `"C-Media Electronics Inc."`.

### `virtualisation.vfio-stealth.devices.usbAudio.name`

The usbAudio.name an emulated QEMU device reports in place of QEMU's own: 1 to 64 letters, digits, spaces or any of .,()/+_-. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Za-z0-9 .,()/+_-]{1,64}`. Default: `"USB PnP Sound Device"`.

### `virtualisation.vfio-stealth.devices.usbAudio.product`

The usbAudio.product an emulated QEMU device reports in place of QEMU's own: 0x and four lower-case hex digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern 0x[0-9a-f]{4}`. Default: `"0x013c"`.

### `virtualisation.vfio-stealth.devices.usbAudio.release`

The usbAudio.release an emulated QEMU device reports in place of QEMU's own: 0x and four lower-case hex digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern 0x[0-9a-f]{4}`. Default: `"0x0100"`.

### `virtualisation.vfio-stealth.devices.usbAudio.vendor`

The usbAudio.vendor an emulated QEMU device reports in place of QEMU's own: 0x and four lower-case hex digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern 0x[0-9a-f]{4}`. Default: `"0x0d8c"`.

### `virtualisation.vfio-stealth.devices.usbBraille.manufacturer`

The usbBraille.manufacturer an emulated QEMU device reports in place of QEMU's own: 1 to 64 letters, digits, spaces or any of .,()/+_-. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Za-z0-9 .,()/+_-]{1,64}`. Default: `"HumanWare"`.

### `virtualisation.vfio-stealth.devices.usbBraille.name`

The usbBraille.name an emulated QEMU device reports in place of QEMU's own: 1 to 64 letters, digits, spaces or any of .,()/+_-. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Za-z0-9 .,()/+_-]{1,64}`. Default: `"Brailliant 40"`.

### `virtualisation.vfio-stealth.devices.usbFidoKey.manufacturer`

The usbFidoKey.manufacturer an emulated QEMU device reports in place of QEMU's own: 1 to 64 letters, digits, spaces or any of .,()/+_-. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Za-z0-9 .,()/+_-]{1,64}`. Default: `"Yubico"`.

### `virtualisation.vfio-stealth.devices.usbFidoKey.name`

The usbFidoKey.name an emulated QEMU device reports in place of QEMU's own: 1 to 64 letters, digits, spaces or any of .,()/+_-. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Za-z0-9 .,()/+_-]{1,64}`. Default: `"Security Key by Yubico"`.

### `virtualisation.vfio-stealth.devices.usbFidoKey.product`

The usbFidoKey.product an emulated QEMU device reports in place of QEMU's own: 0x and four lower-case hex digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern 0x[0-9a-f]{4}`. Default: `"0x0120"`.

### `virtualisation.vfio-stealth.devices.usbFidoKey.vendor`

The usbFidoKey.vendor an emulated QEMU device reports in place of QEMU's own: 0x and four lower-case hex digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern 0x[0-9a-f]{4}`. Default: `"0x1050"`.

### `virtualisation.vfio-stealth.devices.usbHub.product`

The usbHub.product an emulated QEMU device reports in place of QEMU's own: 0x and four lower-case hex digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern 0x[0-9a-f]{4}`. Default: `"0x2046"`.

### `virtualisation.vfio-stealth.devices.usbHub.vendor`

The usbHub.vendor an emulated QEMU device reports in place of QEMU's own: 0x and four lower-case hex digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern 0x[0-9a-f]{4}`. Default: `"0x0451"`.

### `virtualisation.vfio-stealth.devices.usbPhone.androidRelease`

The usbPhone.androidRelease an emulated QEMU device reports in place of QEMU's own: an Android release such as 12 or 13.0.1. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [0-9]{1,2}(\.[0-9]{1,2}){0,2}`. Default: `"12"`.

### `virtualisation.vfio-stealth.devices.usbPhone.manufacturer`

The usbPhone.manufacturer an emulated QEMU device reports in place of QEMU's own: 1 to 64 letters, digits, spaces or any of .,()/+_-. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Za-z0-9 .,()/+_-]{1,64}`. Default: `"Google"`.

### `virtualisation.vfio-stealth.devices.usbPhone.mtpProduct`

The usbPhone.mtpProduct an emulated QEMU device reports in place of QEMU's own: 0x and four lower-case hex digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern 0x[0-9a-f]{4}`. Default: `"0x4ee1"`.

### `virtualisation.vfio-stealth.devices.usbPhone.name`

The usbPhone.name an emulated QEMU device reports in place of QEMU's own: 1 to 64 letters, digits, spaces or any of .,()/+_-. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Za-z0-9 .,()/+_-]{1,64}`. Default: `"Pixel 3"`.

### `virtualisation.vfio-stealth.devices.usbPhone.serialLength`

The usbPhone.serialLength an emulated QEMU device reports in place of QEMU's own: the length of the serial derived from the VM uuid, 1 to 64. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `integer between 1 and 64 (both inclusive)`. Default: `12`.

### `virtualisation.vfio-stealth.devices.usbPhone.tetherProduct`

The usbPhone.tetherProduct an emulated QEMU device reports in place of QEMU's own: 0x and four lower-case hex digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern 0x[0-9a-f]{4}`. Default: `"0x4ee3"`.

### `virtualisation.vfio-stealth.devices.usbPhone.vendor`

The usbPhone.vendor an emulated QEMU device reports in place of QEMU's own: 0x and four lower-case hex digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern 0x[0-9a-f]{4}`. Default: `"0x18d1"`.

### `virtualisation.vfio-stealth.devices.usbSerial.manufacturer`

The usbSerial.manufacturer an emulated QEMU device reports in place of QEMU's own: 1 to 64 letters, digits, spaces or any of .,()/+_-. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Za-z0-9 .,()/+_-]{1,64}`. Default: `"FTDI"`.

### `virtualisation.vfio-stealth.devices.usbSerial.name`

The usbSerial.name an emulated QEMU device reports in place of QEMU's own: 1 to 64 letters, digits, spaces or any of .,()/+_-. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Za-z0-9 .,()/+_-]{1,64}`. Default: `"FT232R USB UART"`.

### `virtualisation.vfio-stealth.devices.usbSerial.product`

The usbSerial.product an emulated QEMU device reports in place of QEMU's own: 0x and four lower-case hex digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern 0x[0-9a-f]{4}`. Default: `"0x6001"`.

### `virtualisation.vfio-stealth.devices.usbSerial.release`

The usbSerial.release an emulated QEMU device reports in place of QEMU's own: 0x and four lower-case hex digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern 0x[0-9a-f]{4}`. Default: `"0x0600"`.

### `virtualisation.vfio-stealth.devices.usbSerial.serialLength`

The usbSerial.serialLength an emulated QEMU device reports in place of QEMU's own: the length of the serial derived from the VM uuid, 1 to 64. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `integer between 1 and 64 (both inclusive)`. Default: `8`.

### `virtualisation.vfio-stealth.devices.usbSerial.vendor`

The usbSerial.vendor an emulated QEMU device reports in place of QEMU's own: 0x and four lower-case hex digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern 0x[0-9a-f]{4}`. Default: `"0x0403"`.

### `virtualisation.vfio-stealth.devices.usbSmartcard.manufacturer`

The usbSmartcard.manufacturer an emulated QEMU device reports in place of QEMU's own: 1 to 64 letters, digits, spaces or any of .,()/+_-. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Za-z0-9 .,()/+_-]{1,64}`. Default: `"GEMPLUS"`.

### `virtualisation.vfio-stealth.devices.usbSmartcard.name`

The usbSmartcard.name an emulated QEMU device reports in place of QEMU's own: 1 to 64 letters, digits, spaces or any of .,()/+_-. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Za-z0-9 .,()/+_-]{1,64}`. Default: `"Gemplus USB SmartCard Reader 433-Swap"`.

### `virtualisation.vfio-stealth.devices.usbSmartcard.release`

The usbSmartcard.release an emulated QEMU device reports in place of QEMU's own: 0x and four lower-case hex digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern 0x[0-9a-f]{4}`. Default: `"0x0001"`.

### `virtualisation.vfio-stealth.devices.usbSmartcard.serialLength`

The usbSmartcard.serialLength an emulated QEMU device reports in place of QEMU's own: the length of the serial derived from the VM uuid, 1 to 64. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `integer between 1 and 64 (both inclusive)`. Default: `8`.

### `virtualisation.vfio-stealth.devices.usbStorageBridge.manufacturer`

The usbStorageBridge.manufacturer an emulated QEMU device reports in place of QEMU's own: 1 to 64 letters, digits, spaces or any of .,()/+_-. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Za-z0-9 .,()/+_-]{1,64}`. Default: `"JMicron"`.

### `virtualisation.vfio-stealth.devices.usbStorageBridge.name`

The usbStorageBridge.name an emulated QEMU device reports in place of QEMU's own: 1 to 64 letters, digits, spaces or any of .,()/+_-. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Za-z0-9 .,()/+_-]{1,64}`. Default: `"USB to ATA/ATAPI Bridge"`.

### `virtualisation.vfio-stealth.devices.usbStorageBridge.product`

The usbStorageBridge.product an emulated QEMU device reports in place of QEMU's own: 0x and four lower-case hex digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern 0x[0-9a-f]{4}`. Default: `"0x0567"`.

### `virtualisation.vfio-stealth.devices.usbStorageBridge.serialLength`

The usbStorageBridge.serialLength an emulated QEMU device reports in place of QEMU's own: the length of the serial derived from the VM uuid, 1 to 64. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `integer between 1 and 64 (both inclusive)`. Default: `12`.

### `virtualisation.vfio-stealth.devices.usbStorageBridge.vendor`

The usbStorageBridge.vendor an emulated QEMU device reports in place of QEMU's own: 0x and four lower-case hex digits. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern 0x[0-9a-f]{4}`. Default: `"0x152d"`.

### `virtualisation.vfio-stealth.devices.usbTablet.manufacturer`

The usbTablet.manufacturer an emulated QEMU device reports in place of QEMU's own: 1 to 64 letters, digits, spaces or any of .,()/+_-. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Za-z0-9 .,()/+_-]{1,64}`. Default: `"Wacom Co.,Ltd."`.

### `virtualisation.vfio-stealth.devices.vmgenidHardwareId`

The vmgenidHardwareId an emulated QEMU device reports in place of QEMU's own: an ACPI hardware id of 1 to 32 letters, digits or underscores. The default comes from qemu/device-identities.nix, which every install shares; set your own to keep installs apart. Goes into packages.qemu.

Type: `string matching the pattern [A-Za-z0-9_]{1,32}`. Default: `"Hyper_V_Gen_Counter_V1"`.

### `virtualisation.vfio-stealth.disk.firmware`

Disk firmware revision, as `hdparm -I` or `smartctl -i` shows it for your real disk. Replaces QEMU's 2.5+ on SATA and SCSI disks. Goes into packages.qemu.

Type: `string matching the pattern ^[A-Za-z0-9._-]{1,8}$`. Default: `"01.01A01"`.

### `virtualisation.vfio-stealth.disk.model`

Disk model string, at most 40 characters. Populates Win32_DiskDrive.Model. Set to your real disk model. Goes into packages.qemu.

Type: `string matching the pattern ^.{1,40}$`. Default: `"WDC WD10EZEX-00WN4A0     "`.

### `virtualisation.vfio-stealth.disk.opticalFirmware`

Optical drive firmware revision, as your real drive reports it. Replaces QEMU's 2.5+ on SATA and SCSI CD drives. Goes into packages.qemu.

Type: `string matching the pattern ^[A-Za-z0-9._-]{1,8}$`. Default: `"LY00"`.

### `virtualisation.vfio-stealth.disk.opticalModel`

Emulated optical drive model: a vendor of at most 8 characters, a space, then a product of at most 16. The drive reports the whole string to ATA IDENTIFY and the two parts to SCSI INQUIRY, as a real drive does. Populates Win32_CDROMDrive.Name. Goes into packages.qemu.

Type: `string`. Default: `"HL-DT-ST DVDRAM GH24NSC0 "`.

### `virtualisation.vfio-stealth.disk.serial`

IDE/SCSI disk serial string, as `smartctl -i` shows it. Populates Win32_DiskDrive.SerialNumber; with another disk.model, set one in the form that model's maker uses. Goes into packages.qemu.

Type: `string`. Default: derived from identity.seed: for a disk.model beginning WDC WD, WD-WCC and nine characters, the form Western Digital drives report; for another, twelve hex digits. `"Default string"` without a seed.

### `virtualisation.vfio-stealth.domain`

What a VM's libvirt domain takes from these options: features, cpuFeatures, clock and sysinfo for the domain, qemuArgs for its QEMU command line, processor for the SMBIOS type 4 identity cpuIdentity resolves to, the devices devicesToRemove names, and warnings. qemuArgs leave out what domains.<name>.cpuPm adds, -overcommit cpu-pm=on and with aperfMperf -global x86_64-cpu.aperfmperf=on, which a VM pinned one to one adds itself.

Type: `lazy attribute set of anything`. Default: lib.mkStealthFeatures applied to these options. Read only.

### `virtualisation.vfio-stealth.domains`

VMs this module defines in libvirt through NixVirt, each with the stealth QEMU arguments, SMBIOS sysinfo, Hyper-V and CPU settings, the stealth firmware and Secure Boot keys. NixVirt redefines them at each activation, so a change made in virt-manager does not survive a rebuild. Once any VM is declared here, NixVirt removes every other VM defined on qemu:///system, though not its disks or NVRAM, so declare every VM of the host here or none.

Type: `attribute set of (submodule)`. Default: `{ }`.

### `virtualisation.vfio-stealth.domains.<name>.active`

Whether NixVirt starts (true) or stops (false) the VM at activation; null leaves it as it is.

Type: `null or boolean`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cache.assocL1`

This domain's smbios.cache.assocL1, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or integer between 1 and 14 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cache.assocL2`

This domain's smbios.cache.assocL2, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or integer between 1 and 14 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cache.assocL3`

This domain's smbios.cache.assocL3, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or integer between 1 and 14 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cache.ecc`

This domain's smbios.cache.ecc, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or integer between 1 and 6 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cache.l1`

This domain's smbios.cache.l1, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or (positive integer, meaning >0)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cache.l2`

This domain's smbios.cache.l2, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or (positive integer, meaning >0)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cache.l3`

This domain's smbios.cache.l3, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or (positive integer, meaning >0)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cdroms`

ISO images, attached as SATA CD drives in this order. The VM boots from the first one before the disks.

Type: `list of string`. Default: `[ ]`.

### `virtualisation.vfio-stealth.domains.<name>.cores`

CPU cores the guest sees, on one socket.

Type: `positive integer, meaning >0`.

### `virtualisation.vfio-stealth.domains.<name>.cpuIdentity.characteristics`

This domain's cpuIdentity.characteristics, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or 16 bit unsigned integer; between 0 and 65535 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cpuIdentity.currentSpeed`

This domain's cpuIdentity.currentSpeed, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or integer between 1 and 65535 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cpuIdentity.externalClock`

This domain's cpuIdentity.externalClock, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or integer between 1 and 65535 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cpuIdentity.family`

This domain's cpuIdentity.family, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or integer between 1 and 65533 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cpuIdentity.manufacturer`

This domain's cpuIdentity.manufacturer, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or string`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cpuIdentity.maxSpeed`

This domain's cpuIdentity.maxSpeed, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or integer between 1 and 65535 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cpuIdentity.modelId`

This domain's cpuIdentity.modelId, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or string`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cpuIdentity.socket`

This domain's cpuIdentity.socket, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or string matching the pattern [ -~]{1,64}`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cpuIdentity.upgrade`

This domain's cpuIdentity.upgrade, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or integer between 1 and 255 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cpuIdentity.voltageDecivolts`

This domain's cpuIdentity.voltageDecivolts, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or integer between 1 and 127 (both inclusive)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.cpuPm`

Pass -overcommit cpu-pm=on, so HLT, MWAIT and PAUSE no longer exit: an idle vCPU wakes without an exit's delay and the guest gets MWAIT and, with aperfMperf, APERF and MPERF, as on hardware. The vCPU then never hands its host CPU back when idle, so it suits vCPUs pinned one to one to host CPUs nothing else needs, and takes time from host work on CPUs the host shares with it.

Type: `boolean`. Default: `pinning != null`.

### `virtualisation.vfio-stealth.domains.<name>.disks`

Disks, in boot order.

Type: `list of (submodule)`. Default: `[ ]`.

### `virtualisation.vfio-stealth.domains.<name>.disks.*.bus`

sata installs without extra drivers; virtio needs the virtio-win storage driver.

Type: `one of "sata", "virtio"`. Default: `"sata"`.

### `virtualisation.vfio-stealth.domains.<name>.disks.*.cache`

libvirt's cache mode for the disk. none bypasses the host page cache with O_DIRECT, the fastest for a block device or an image on ext4 or XFS. Use writeback for an image on btrfs: there a guest that changes a buffer while its direct write is in flight leaves a block whose checksum fails, and the guest later reads it as an I/O error.

Type: `one of "none", "writeback", "writethrough", "directsync", "unsafe"`. Default: `"none"`.

### `virtualisation.vfio-stealth.domains.<name>.disks.*.format`

The image format; a block device is raw.

Type: `one of "raw", "qcow2"`. Default: `"raw"`.

### `virtualisation.vfio-stealth.domains.<name>.disks.*.source`

An image file, or a block device under /dev such as an LVM volume.

Type: `string`.

### `virtualisation.vfio-stealth.domains.<name>.display`

The remote display. With gpu set the VM has no emulated video card, and a spice display carries only input and the clipboard, as Looking Glass uses it; none leaves even that out.

Type: `one of "spice", "vnc", "none"`. Default: `"spice"`.

### `virtualisation.vfio-stealth.domains.<name>.extra`

NixVirt domain attributes merged over the generated ones, for anything these options do not cover.

Type: `attribute set of anything`. Default: `{ }`.

### `virtualisation.vfio-stealth.domains.<name>.extraQemuArgs`

QEMU arguments added after the generated ones. Never -cpu, which replaces libvirt's CPU line.

Type: `list of string`. Default: `[ ]`.

### `virtualisation.vfio-stealth.domains.<name>.gpu`

A GPU passed through with VFIO. The VM then has no emulated video card. Its address, audio and extraFunctions are guarded like hostDevices.

Type: `null or (submodule)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.gpu.address`

The GPU's PCI address, as lspci -D prints it.

Type: `string matching the pattern ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$`. Example: `"0000:01:00.0"`.

### `virtualisation.vfio-stealth.domains.<name>.gpu.audio`

The GPU's HDMI audio function, which sits in its IOMMU group.

Type: `null or string matching the pattern ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$`. Default: `null`. Example: `"0000:01:00.1"`.

### `virtualisation.vfio-stealth.domains.<name>.gpu.binding`

How the GPU reaches vfio-pci. "libvirt" passes it managed: libvirt unbinds the host driver at start and binds it again at stop. "hook" binds vfio-pci in the QEMU hook through driver_override after the host driver has initialised the card, for cards that need a host POST, and gives it back only with rebindOnStop. "boot" claims it at boot through vfio-pci.ids from ids, so the host never drives it.

Type: `one of "libvirt", "hook", "boot"`. Default: `"libvirt"`.

### `virtualisation.vfio-stealth.domains.<name>.gpu.extraFunctions`

Further functions in the GPU's IOMMU group, such as the USB-C controller of some cards. They are bound with the GPU.

Type: `list of string matching the pattern ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$`. Default: `[ ]`.

Example:

```nix
[
  "0000:01:00.2"
]
```

### `virtualisation.vfio-stealth.domains.<name>.gpu.ids`

The vendor:device ids binding "boot" puts in vfio-pci.ids, as lspci -nn shows them. Every device with one of these ids goes to vfio-pci, so never list an id the host's own devices share.

Type: `list of string matching the pattern ^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$`. Default: `[ ]`.

Example:

```nix
[
  "10de:2484"
  "10de:228b"
]
```

### `virtualisation.vfio-stealth.domains.<name>.gpu.rebindOnStop`

With binding "hook", give the GPU back to its host driver when the VM stops. Off, the card stays on vfio-pci until the next boot; some kernels crash when the host driver takes back a card a guest has used.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.domains.<name>.gpu.resizeBar2Mb`

With binding "hook", resize BAR 2 to this many MiB while no driver holds the card, before vfio-pci binds it. The size must be one the card lists in resource2_resize. A small BAR keeps some guest drivers from failing; the largest makes some cards re-enumerate and clears a reset state a stop leaves. null leaves BAR 2 as it is.

Type: `null or (power of two)`. Default: `null`. Example: `256`.

### `virtualisation.vfio-stealth.domains.<name>.gpu.rom`

The GPU's option ROM; null leaves it as QEMU shows it.

Type: `null or (submodule)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.gpu.rom.bar`

Show the guest the card's ROM BAR. Some cards' guest drivers misread it, which shows as a corrupted picture; turn it off for those.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.domains.<name>.gpu.rom.file`

A VBIOS image the guest sees in place of the card's own ROM, for a card whose ROM the host firmware has altered. A path in the flake is copied to the store, where QEMU can read it.

Type: `null or absolute path`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.hostDevices`

PCI devices passed through with VFIO, as `lspci -D` prints them, such as 0000:02:00.0 for an NVMe controller, passed managed: libvirt binds them to vfio-pci at start and back at stop. With host.enable the hook refuses to pass one that a protectedDisks path sits on, and unmounts what is mounted from it. A GPU goes under gpu.

Type: `list of string matching the pattern ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$`. Default: `[ ]`.

### `virtualisation.vfio-stealth.domains.<name>.hugepages`

Back the guest's memory with locked huge pages of hugepages.size from a shared memfd. memory must be a whole number of pages. Needs host.enable; without hugepages.atBoot the hook allocates the pages at start.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.domains.<name>.hypervMode`

This domain's hypervMode, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or one of "enlightened", "hidden"`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.iommu`

Give the VM an IOMMU of the host's vendor, AMD-Vi on AMD and VT-d on Intel, with interrupt remapping, as a real board has. Windows' own hypervisor then finds I/O remapping hardware, which VBS uses for DMA protection; without it a guest with VBS and a passed-through GPU can show no picture. Each passed-through device then needs an IOMMU group of its own on the host: a group of several devices, such as a GPU whose audio and USB functions share its group, is refused.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.domains.<name>.kvmPvEnforceCpuid`

This domain's kvmPvEnforceCpuid, for a VM that shows other hardware than the host's other VMs; null takes the host's.

Type: `null or boolean`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.lookingGlass`

Give the VM the ivshmem device Looking Glass writes frames to: backed by /dev/kvmfr0 with kvmfr.enable, else by /dev/shm/looking-glass of lookingGlass.shmemSizeMb.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.domains.<name>.machine`

The QEMU machine type, always a q35, which the stealth patches edit. q35 follows the QEMU version; pin a versioned type such as pc-q35-10.0 to keep the hardware Windows was activated on across QEMU updates.

Type: `string matching the pattern ^(q35|pc-q35-[0-9]+\.[0-9]+)$`. Default: `"q35"`. Example: `"pc-q35-10.0"`.

### `virtualisation.vfio-stealth.domains.<name>.memory`

Memory in MiB.

Type: `positive integer, meaning >0`.

### `virtualisation.vfio-stealth.domains.<name>.network`

The VM's network card, or null for none.

Type: `null or (submodule)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.network.mac`

The card's MAC address, such as one a Windows install was activated with. null derives it from macPrefix and the uuid when spoofMac is on, and leaves it to libvirt otherwise.

Type: `null or string matching the pattern ^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$`. Default: `null`. Example: `"D8:BB:C1:12:34:56"`.

### `virtualisation.vfio-stealth.domains.<name>.network.model`

The emulated network card.

Type: `string`. Default: `"e1000e"`.

### `virtualisation.vfio-stealth.domains.<name>.network.source`

The libvirt network or bridge name.

Type: `string`. Default: `"default"`.

### `virtualisation.vfio-stealth.domains.<name>.network.type`

A libvirt network or a host bridge.

Type: `one of "network", "bridge"`. Default: `"network"`.

### `virtualisation.vfio-stealth.domains.<name>.pinning`

Pin each vCPU to its own host CPU, and QEMU's threads to others. null leaves placement to the host scheduler.

Type: `null or (submodule)`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.pinning.emulator`

Host CPUs for QEMU's emulator threads, as a libvirt cpuset, outside the vCPUs' CPUs.

Type: `string matching the pattern ^(0|[1-9][0-9]*)(-(0|[1-9][0-9]*))?(,(0|[1-9][0-9]*)(-(0|[1-9][0-9]*))?)*$`. Example: `"0-1"`.

### `virtualisation.vfio-stealth.domains.<name>.pinning.iothread`

Host CPUs for one I/O thread, which serves the domain's virtio disks. null gives the domain no I/O thread, and QEMU's main loop serves them.

Type: `null or string matching the pattern ^(0|[1-9][0-9]*)(-(0|[1-9][0-9]*))?(,(0|[1-9][0-9]*)(-(0|[1-9][0-9]*))?)*$`. Default: `null`. Example: `"1"`.

### `virtualisation.vfio-stealth.domains.<name>.pinning.vcpus`

The host CPU each vCPU runs on, in vCPU order, one per vCPU. With threads = 2, list the two hardware threads of one host core next to each other, as lscpu -e pairs them, so the guest's sibling threads share a core.

Type: `list of (unsigned integer, meaning >=0)`. Default: `[ ]`.

Example:

```nix
[
  2
  18
  3
  19
]
```

### `virtualisation.vfio-stealth.domains.<name>.secureBoot`

Start from the Microsoft Secure Boot keys. With it off the firmware has no keys and boots unsigned loaders.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.domains.<name>.sound`

An emulated Intel HD Audio controller with one codec reporting hdaCodec, played and recorded through the PipeWire session in pipewireRuntimeDir. micro gives a speaker output and a microphone input, duplex a line out and a line in, output a line out alone. QEMU opens the PipeWire socket of another user, so it needs virtualisation.libvirtd.qemu.runAsRoot. null gives the VM no emulated sound; a GPU's HDMI audio or a passed USB audio device needs none.

Type: `null or one of "micro", "duplex", "output"`. Default: `null`.

### `virtualisation.vfio-stealth.domains.<name>.stopServices`

systemd units the QEMU hook stops before the VM takes its devices and starts again when it stops, such as fan or GPU control daemons that keep a GPU open. Before taking a device the hook refuses to start while any process still has it open, and names those processes, where taking it from its driver would otherwise wait for them. Needs host.enable.

Type: `list of string matching the pattern ^[A-Za-z0-9@._:-]+$`. Default: `[ ]`.

Example:

```nix
[
  "coolercontrold.service"
  "lactd.service"
]
```

### `virtualisation.vfio-stealth.domains.<name>.threads`

Threads per core.

Type: `integer between 1 and 2 (both inclusive)`. Default: `2`.

### `virtualisation.vfio-stealth.domains.<name>.tpm`

An emulated TPM 2.0, which Windows 11 needs.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.domains.<name>.unmount`

Mount points the hook unmounts before the VM starts, such as a filesystem on a disk the VM takes, and mounts again from fstab after it stops. A path that is not mounted is skipped; one that will not unmount refuses the start. Filesystems left mounted on a passed-through disk are unmounted too, but not mounted again. Needs host.enable.

Type: `list of absolute path not in the Nix store`. Default: `[ ]`.

Example:

```nix
[
  "/mnt/games"
]
```

### `virtualisation.vfio-stealth.domains.<name>.usb`

USB devices passed through by vendor and product id. A udev rule attaches a device again when it is plugged in while the VM runs.

Type: `list of (submodule)`. Default: `[ ]`.

### `virtualisation.vfio-stealth.domains.<name>.usb.*.product`

The USB product id, as a number.

Type: `16 bit unsigned integer; between 0 and 65535 (both inclusive)`. Example: `22136`.

### `virtualisation.vfio-stealth.domains.<name>.usb.*.vendor`

The USB vendor id, as lsusb shows it in hex; write it as a number, such as 4660 for 1234.

Type: `16 bit unsigned integer; between 0 and 65535 (both inclusive)`. Example: `4660`.

### `virtualisation.vfio-stealth.domains.<name>.uuid`

The VM's UUID, in lower case, which also becomes its SMBIOS system UUID. Keep it fixed: Windows activation, the TPM state, the MAC address and the USB serials follow it. With identity.seed it defaults to a version 4 UUID derived from the seed and the VM's name; without one it must be set.

Type: `string matching the pattern ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`.

### `virtualisation.vfio-stealth.domains.<name>.xml`

The rendered domain XML. NixVirt defines it in libvirt; `virsh define` takes it too.

Type: `absolute path`. Read only.

### `virtualisation.vfio-stealth.edid.dpi`

Monitor DPI. Goes into packages.qemu.

Type: `integer between 1 and 1000 (both inclusive)`. Default: `91`.

### `virtualisation.vfio-stealth.edid.manufacturer`

3-char EDID manufacturer code. Goes into packages.qemu.

Type: `string`. Default: `"ACI"`.

### `virtualisation.vfio-stealth.edid.productCode`

EDID product code (hex). Goes into packages.qemu.

Type: `string`. Default: `"0x2480"`.

### `virtualisation.vfio-stealth.edid.resolution.height`

Vertical pixels of the EDID preferred mode, in place of QEMU's 800, for a display device that sets no yres. Goes into packages.qemu.

Type: `integer between 1 and 4095 (both inclusive)`. Default: `1080`.

### `virtualisation.vfio-stealth.edid.resolution.width`

Horizontal pixels of the EDID preferred mode, in place of QEMU's 1280, for a display device that sets no xres. Goes into packages.qemu.

Type: `integer between 1 and 4095 (both inclusive)`. Default: `1920`.

### `virtualisation.vfio-stealth.edid.serial`

The monitor name in the EDID, the descriptor QEMU fills with "QEMU Monitor". The numeric serial is edid.serialNumber. Goes into packages.qemu.

Type: `string`. Default: `"VG248QE"`.

### `virtualisation.vfio-stealth.edid.serialNumber`

The EDID ID Serial Number, bytes 12 to 15, as `edid-decode` shows it under Serial Number; QEMU writes 0. Windows reads it into WmiMonitorID.SerialNumberID. Goes into packages.qemu.

Type: `32 bit unsigned integer; between 0 and 4294967295 (both inclusive)`. Default: a number derived from identity.seed, or 0 without one.

### `virtualisation.vfio-stealth.edid.week`

EDID manufacture week. Goes into packages.qemu.

Type: `integer between 1 and 54 (both inclusive)`. Default: `22`.

### `virtualisation.vfio-stealth.edid.year`

EDID manufacture year. Goes into packages.qemu.

Type: `integer between 1990 and 2245 (both inclusive)`. Default: `2020`.

### `virtualisation.vfio-stealth.evdev.extraKeyboards`

More keyboard event devices passed the same way, such as the other interfaces of a keyboard that shows several.

Type: `list of absolute path not in the Nix store`. Default: `[ ]`.

### `virtualisation.vfio-stealth.evdev.keyboard`

The keyboard every VM in domains takes over through QEMU's input-linux, switched between host and guest with both Ctrl keys. Use its /dev/input/by-id path, which survives a replug.

Type: `null or absolute path not in the Nix store`. Default: `null`. Example: `"/dev/input/by-id/usb-Example_Keyboard-event-kbd"`.

### `virtualisation.vfio-stealth.evdev.mouse`

The mouse every VM in domains takes over through input-linux, following the keyboard.

Type: `null or absolute path not in the Nix store`. Default: `null`. Example: `"/dev/input/by-id/usb-Example_Mouse-event-mouse"`.

### `virtualisation.vfio-stealth.hdaCodec`

Vendor:device id the emulated HD Audio codec reports in place of QEMU's, with pciSubsystem as its subsystem id. Copy the Vendor Id that `cat /proc/asound/card*/codec#*` shows for your board's codec; the default is a Realtek ALC897. Goes into packages.qemu.

Type: `string matching the pattern ^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$`. Default: `"10ec:0897"`.

### `virtualisation.vfio-stealth.host.enable`

Prepare this host to pass PCI devices to the VMs in domains: load vfio, vfio_iommu_type1 and vfio_pci, keep vfio-pci devices out of idle D3, load vfio-pci before snd_hda_intel so a GPU's audio function is free to bind, let libvirt-guests start no guest at boot, disable the sleep targets, which a passed-through device does not survive, and install the libvirt QEMU hook that does what the domains' gpu, hugepages, unmount and pinning ask at start and stop. hugepages, kvmfr, lookingGlass.client, evdev, pinning.isolate, acsOverride, disableAspm, a changed protectedDisks and a domain's hook or boot GPU binding, hugepages and unmount need it.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.host.acsOverride`

Value of the pcie_acs_override= kernel parameter, which splits IOMMU groups the chipset bundles. Only kernels carrying the ACS override patch read it; mainline ignores it. It fakes isolation: a passed-through device can still reach the other devices of its real group by DMA, past the IOMMU. null leaves the parameter out.

Type: `null or string`. Default: `null`. Example: `"downstream,multifunction"`.

### `virtualisation.vfio-stealth.host.disableAspm`

Pass pcie_aspm=off, which keeps every PCIe link out of its power-saving states. Some GPUs and boards lose a passed-through device's link, or fail to reset it, when ASPM moves it between states; the cost is host power draw.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.host.protectedDisks`

Paths whose disks a VM must never take. Before a VM starts, the hook resolves each path to the block devices beneath the filesystem that holds it, through device mapper and LVM, adds every active swap device, and refuses to start a VM that passes through a PCI device any of them sits on. A path whose device it cannot resolve, such as one on ZFS, refuses every VM that passes a PCI device; an empty list turns the check off for everything but swap.

Type: `list of absolute path not in the Nix store`.

Default:

```nix
[
  "/"
  "/boot"
  "/nix/store"
  "/home"
]
```

### `virtualisation.vfio-stealth.hugepages.atBoot`

Reserve the pages on the kernel command line, before memory fragments. Without it the hook adds a domain's pages to the pool before the domain starts and takes them back after it stops, and refuses the start when the kernel cannot find them.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hugepages.count`

Pages reserved at boot with atBoot. null reserves the sum of the memory of every domain with hugepages, enough for all of them at once. Unused without atBoot, where each domain allocates its own.

Type: `null or (positive integer, meaning >0)`. Default: `null`.

### `virtualisation.vfio-stealth.hugepages.size`

The huge page size of a domain with hugepages. 1G pages cost fewer TLB misses, but after the host has run a while it seldom finds whole free gigabytes, so 1G usually needs atBoot.

Type: `one of "2M", "1G"`. Default: `"2M"`.

### `virtualisation.vfio-stealth.hypervFeatures.frequencies`

TSC frequency reporting (HvTscPage). Requires CONFIG_KVM_HYPERV=y (KVM_CAP_HYPERV_TIME); libvirt errors with 'host doesn't support hyperv frequencies' otherwise.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.ipi`

Hyper-V IPI hypercall. Requires CONFIG_KVM_HYPERV=y.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.reenlightenment`

TSC re-enlightenment notification (HvReenlightenment). Requires CONFIG_KVM_HYPERV=y.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.relaxed`

Relaxed timing (HvRelax). QEMU/libvirt-level setting with no KVM cap; always supported.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.hypervFeatures.reset`

Hyper-V reset hypercall. Requires CONFIG_KVM_HYPERV=y.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.runtime`

Hyper-V runtime (HvRuntime). Requires CONFIG_KVM_HYPERV=y.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.spinlocks`

Spinlock retry reporting (HvSpin). Requires CONFIG_KVM_HYPERV=y (KVM_CAP_HYPERV_SPIN); libvirt errors with 'host doesn't support hyperv spinlocks' otherwise.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.stimer`

Synthetic timers (HvSyntheticTimers) with direct mode. Requires CONFIG_KVM_HYPERV=y.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.synic`

Synthetic interrupt controller (HvSynIC). Requires CONFIG_KVM_HYPERV=y.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.tlbflush`

Hyper-V TLB flush hypercall. Requires CONFIG_KVM_HYPERV=y.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.vapic`

SynIC APIC virtualization (HvApic). Requires CONFIG_KVM_HYPERV=y in the host kernel (KVM_CAP_HYPERV_VAPIC); libvirt errors with 'host doesn't support hyperv vapic' otherwise.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervFeatures.vendor_id`

Hyper-V vendor_id exposure. Libvirt-level setting with no KVM cap; always supported.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.hypervFeatures.vpindex`

Virtual processor index (HvVpIndex). Requires CONFIG_KVM_HYPERV=y in the host kernel. Enables libvirtError: 'host doesn't support hyperv vpindex' if requested on a kernel that does not advertise it.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.hypervMode`

Hyper-V enlightenment strategy. "enlightened" sets the hypervisor CPUID bit and exposes the Hyper-V enlightenments, which speed up Windows, and VMAware reads HYPERVISOR_BIT and HYPERVISOR_STR from them. "hidden" clears the bit and emits no enlightenments, which is the stealth setting. Windows' own Hyper-V, which VBS and HVCI need, starts in either mode, on an Intel host with cet off; enlightened adds VMAware's SINGLE_STEP and VMID, and INTERRUPT_SHADOW on AMD. Per-VM overridable via domains.<name>.hypervMode

Type: `one of "enlightened", "hidden"`. Default: `"enlightened"`.

### `virtualisation.vfio-stealth.hypervVendorId`

Hyper-V vendor_id reported to guest (1 to 12 chars, libvirt hard limit). Avoid well-known VM values like 'AMDisbetter!' or 'Microsoft Hv'.

Type: `string matching the pattern ^.{1,12}$`. Default: twelve hex digits derived from identity.seed, or `"AuthAMDRyzen"` without one.

### `virtualisation.vfio-stealth.identity.seed`

A private string of 8 or more characters, unique to this host, from which every unique identity value left unset is derived: smbios.baseBoardSerial, the serial of each populated slot in smbios.memory.slots, disk.serial, edid.serialNumber, acpiSsdt.batterySerial and hypervVendorId, and with smbios.perDomainSerials each VM's serials. Each derived value has the form its kind of part reports, and the same seed gives the same values on every rebuild. null leaves them at values every host without a seed shares, which tie a guest to this module, and warns for each one still set to it. Anyone who knows the seed can compute the values, so keep it out of a public repository, for example in a private flake input.

Type: `null or string matching the pattern .{8,}`. Default: `null`. Example: `"a private phrase only this host uses"`.

### `virtualisation.vfio-stealth.instructionFixes.enable`

Add KVM patches to kernelPostPatch so the guest sees bare-metal behaviour where KVM differs. On both vendors: VMCALL and VMMCALL at CPL > 0 raise #UD (vfio-native). On amd also: an SVM instruction while the guest's EFER.SVME is clear raises #UD, and ICEBP's #DB reports the address after the instruction. VMAware's KVM_INTERCEPTION, SVM_EXCEPTIONS and SINGLE_STEP checks read these.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.kernelCapabilities`

Per-feature capability set of the host kernel, passed by the caller to lib.mkStealthFeatures, which drops every requested Hyper-V feature the set does not allow. null = assume all features supported. Set the attrset by hand after running zcat /proc/config.gz | grep KVM_HYPERV on the host, and name every hypervFeatures key: a key left out counts as unsupported. The parser in lib/kernel-capabilities.nix is not a flake output.

Type: `null or (attribute set of boolean)`. Default: `null`.

### `virtualisation.vfio-stealth.kernelParams.maxCState`

processor.max_cstate value passed on the kernel command line. Lower values reduce timing jitter that can reveal virtualization.

Type: `integer between 0 and 9 (both inclusive)`. Default: `1`.

### `virtualisation.vfio-stealth.kernelParams.tscReliable`

Pass tsc=reliable on the kernel command line. Prevents kernel from falling back to HPET/ACPI PM timer, which detection software can flag.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.kernelPostPatch`

Combined kernel postPatch script. packages.kernelFor appends it to a kernel package.

Type: `string`. Default: `""`. Read only.

### `virtualisation.vfio-stealth.kvmPvEnforceCpuid`

Set kvm-pv-enforce-cpuid=on on the guest CPU. QEMU's default is off. With it on, a guest that touches the KVM paravirt MSRs without the matching CPUID bit gets #GP, which stops Windows in early boot.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.kvmfr.enable`

Load the kvmfr module, which gives Looking Glass its shared memory as /dev/kvmfr0, owned by user. A domain with lookingGlass then gets an ivshmem device backed by it.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.kvmfr.sizeMb`

Size of /dev/kvmfr0 in MiB: 32 holds a 1440p SDR frame, 64 a 4K SDR frame, 128 a 4K HDR frame.

Type: `null or (power of two)`. Default: `null`. Example: `64`.

### `virtualisation.vfio-stealth.libtpmsIdentityPatch`

libtpms postPatch script that gives the emulated TPM the identity of tpm.manufacturer, tpm.model and tpm.firmwareVersion: what a guest reads as TPM2_PT_MANUFACTURER, the vendor strings and the firmware version, and what swtpm_setup writes into the EK certificate. With tpm.harden the module builds libvirt's swtpm with it.

Type: `string`. Default: `""`. Read only.

### `virtualisation.vfio-stealth.lookingGlass.client`

Install looking-glass-client, which shows a guest's screen from the shared memory a domain with lookingGlass writes.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.lookingGlass.shmemSizeMb`

Size in MiB of the shared memory file /dev/shm/looking-glass that a domain with lookingGlass gets when kvmfr.enable is off; sized as kvmfr.sizeMb.

Type: `null or (power of two)`. Default: `null`. Example: `64`.

### `virtualisation.vfio-stealth.macPrefix`

The first three bytes of the MAC address spoofMac gives, as colon-separated hex, for example D8:BB:C1. Set them to those of your board's own network card.

Type: `string matching the pattern ^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}$`. Default: `"D8:BB:C1"`.

### `virtualisation.vfio-stealth.packages`

The packages these options build. qemu is qemu-stealth for cpuVendor with the edid, disk, acpiOem and acpi settings, smbios.chassisType, smbios.memory, apart from its manufacturer, part number and speed, which go in through domain.qemuArgs, and devices; ovmf is the matching ovmf-stealth with smbios.biosVendor as its firmware vendor; libvirtQemu is qemu carrying ovmf's firmware descriptors, which the module sets as libvirt's QEMU so its UEFI firmware is ovmf; secureBootVars is ovmf's variable template with the Microsoft KEK and db enrolled under a Platform Key named secureBoot.platformKeyName and Microsoft's published revocation list as dbx; smbiosTables carries the cache options and, as passthru.cacheHandles, the handles the SMBIOS type 4 in domain.qemuArgs links; acpiTables are the SSDTs with the acpiOem id and table id; kernelFor takes a kernel package, such as pkgs.linux_latest, and returns it with kernelPostPatch appended to its postPatch, for boot.kernelPackages = pkgs.linuxPackagesFor (packages.kernelFor pkgs.linux_latest). The module does not patch boot.kernelPackages itself, because a definition of that option that reads its own value recurses.

Type: `lazy attribute set of (package or function that evaluates to a(n) package)`. Default: built from cpuVendor and the identity options. Read only.

### `virtualisation.vfio-stealth.pciMmio64Mb`

Size of the OVMF 64-bit PCI MMIO window in megabytes. 65536 (64 GB) covers GPUs up to 64 GB VRAM. Set to 0 to omit the flag (OVMF uses its default, which may be too small for modern GPUs).

Type: `unsigned integer, meaning >=0`. Default: `65536`.

### `virtualisation.vfio-stealth.pciSubsystem`

PCI subsystem vendor:device that every emulated PCI device reports in place of QEMU's 1af4:1100. Copy the one your board's chipset devices show in `lspci -nnv`. The device id must be 0040 or more: the virtio spec asks it of modern virtio devices, and OVMF's virtio driver ignores a device below it, so a virtio disk behind a PCIe root port would not boot. Goes into packages.qemu.

Type: `string matching the pattern ^[0-9a-fA-F]{4}:[0-9a-fA-F]{4}$`. Default: `"8086:7270"`.

### `virtualisation.vfio-stealth.pinning.isolate`

While a domain with pinning runs, confine the host's system.slice, user.slice and init.scope to the online CPUs its vCPUs do not use, and give them back when it stops; the emulator and I/O threads share the host's CPUs. The hook reads the online CPUs from sysfs. One pinned domain runs at a time: the hook refuses a second while the first holds the CPUs. Do not combine it with isolcpus.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.pipewireRuntimeDir`

The runtime directory holding the PipeWire socket that a VM's domains.<name>.sound plays and records through: the XDG_RUNTIME_DIR of the user whose desktop session runs PipeWire.

Type: `null or string matching the pattern /[^ ]*`. Default: `/run/user/` and the uid of user, when users.users.<user>.uid is set.

### `virtualisation.vfio-stealth.secureBoot.platformKeyName`

Subject name of the Secure Boot Platform Key in packages.secureBootVars, which a guest can read. Copy your board's own, as `mokutil --pk` prints it on the host. The key is generated at build time and its private half is not kept, so nothing can sign with it.

Type: `string matching the pattern ^[^/]{1,64}$`. Default: `"${smbios.manufacturer} PK"`.

### `virtualisation.vfio-stealth.smbios.baseBoardAsset`

Baseboard asset tag (SMBIOS Type 2).

Type: `string`. Default: `"Default string"`.

### `virtualisation.vfio-stealth.smbios.baseBoardLocation`

Baseboard location in chassis (SMBIOS Type 2).

Type: `string`. Default: `"Default string"`.

### `virtualisation.vfio-stealth.smbios.baseBoardSerial`

Baseboard serial number (SMBIOS Type 2), as `dmidecode -t 2` shows it. Populates WMI Win32_BaseBoard.SerialNumber.

Type: `string`. Default: fifteen digits derived from identity.seed, or `"Default string"` without one.

### `virtualisation.vfio-stealth.smbios.baseBoardVersion`

Baseboard version string (SMBIOS Type 2). Populates Win32_BaseBoard.Version.

Type: `string`. Default: `"Rev 1.xx"`.

### `virtualisation.vfio-stealth.smbios.biosDate`

BIOS release date (MM/DD/YYYY format). Populates Win32_BIOS.ReleaseDate. OVMF defaults to 02/02/2022 which is a generic VM date. Set to your board's actual BIOS date.

Type: `string`. Default: `"01/01/2025"`.

### `virtualisation.vfio-stealth.smbios.biosRelease`

BIOS release version (major.minor). Maps to SMBIOS Type 0 System BIOS Release field.

Type: `string`. Default: `"2.4"`.

### `virtualisation.vfio-stealth.smbios.biosVendor`

SMBIOS BIOS vendor string. Populates WMI Win32_BIOS.Manufacturer. Also the UEFI firmware vendor of packages.ovmf.

Type: `string`. Default: `"American Megatrends Inc."`.

### `virtualisation.vfio-stealth.smbios.biosVersion`

SMBIOS BIOS version string. Populates WMI Win32_BIOS.SMBIOSBIOSVersion.

Type: `string`. Default: `"1001"`.

### `virtualisation.vfio-stealth.smbios.cache.assocL1`

SMBIOS type 7 associativity byte for L1 (7 = 8-way, the AMD Zen 4/5 L1d value). Other common: 8 (16-way), 9 (12-way), 6 (fully associative). See DSP0134 Table 36. Goes into packages.smbiosTables.

Type: `integer between 1 and 14 (both inclusive)`. Default: `7`.

### `virtualisation.vfio-stealth.smbios.cache.assocL2`

SMBIOS type 7 associativity byte for L2 (7 = 8-way, the AMD Zen 4/5 L2 value). Goes into packages.smbiosTables.

Type: `integer between 1 and 14 (both inclusive)`. Default: `7`.

### `virtualisation.vfio-stealth.smbios.cache.assocL3`

SMBIOS type 7 associativity byte for L3 (8 = 16-way, the AMD Zen 4/5 L3 value). Goes into packages.smbiosTables.

Type: `integer between 1 and 14 (both inclusive)`. Default: `8`.

### `virtualisation.vfio-stealth.smbios.cache.ecc`

SMBIOS type 7 error correction type per DSP0134: 1 = Other, 2 = Unknown, 3 = None, 4 = Parity, 5 = Single-bit ECC, 6 = Multi-bit ECC. Consumer Ryzen has no cache ECC; server EPYC has parity on L3. Goes into packages.smbiosTables.

Type: `integer between 1 and 6 (both inclusive)`. Default: `3`.

### `virtualisation.vfio-stealth.smbios.cache.l1`

L1 cache size in KB for SMBIOS type 7. Goes into packages.smbiosTables.

Type: `positive integer, meaning >0`. Default: `512`.

### `virtualisation.vfio-stealth.smbios.cache.l2`

L2 cache size in KB for SMBIOS type 7. Goes into packages.smbiosTables.

Type: `positive integer, meaning >0`. Default: `8192`.

### `virtualisation.vfio-stealth.smbios.cache.l3`

L3 cache size in KB for SMBIOS type 7. Goes into packages.smbiosTables.

Type: `positive integer, meaning >0`. Default: `32768`.

### `virtualisation.vfio-stealth.smbios.chassisAsset`

SMBIOS type 3 Asset Tag, as `dmidecode -t 3` shows it. Populates WMI Win32_SystemEnclosure.SMBIOSAssetTag.

Type: `string matching the pattern [ -~]{1,64}`. Default: `"Default string"`.

### `virtualisation.vfio-stealth.smbios.chassisSerial`

SMBIOS type 3 Serial Number, as `dmidecode -t 3` shows it. Populates WMI Win32_SystemEnclosure.SerialNumber.

Type: `string matching the pattern [ -~]{1,64}`. Default: `"Default string"`.

### `virtualisation.vfio-stealth.smbios.chassisSku`

SMBIOS type 3 SKU Number, as `dmidecode -t 3` shows it; AMI firmware on ASUS and ASRock boards reports Default string.

Type: `string matching the pattern [ -~]{1,64}`. Default: `"Default string"`.

### `virtualisation.vfio-stealth.smbios.chassisType`

SMBIOS chassis type number (type 3) from DSP0134 3.x, as `cat /sys/class/dmi/id/chassis_type` shows it: 3 = Desktop, 4 = Low Profile Desktop, 6 = Mini Tower, 7 = Tower, 9 = Laptop, 10 = Notebook, 13 = All in One, 35 = Mini PC. QEMU writes 1, Other, which VMAware's CTYPE check flags, and its -smbios option has no field for it. Populates WMI Win32_SystemEnclosure.ChassisTypes. Goes into packages.qemu.

Type: `integer between 1 and 36 (both inclusive)`. Default: `3`.

### `virtualisation.vfio-stealth.smbios.chassisVersion`

SMBIOS type 3 Version, as `dmidecode -t 3` shows it; AMI firmware on ASUS and ASRock AM5 and LGA1700 boards reports Default string. Populates WMI Win32_SystemEnclosure.Version.

Type: `string matching the pattern [ -~]{1,64}`. Default: `"Default string"`.

### `virtualisation.vfio-stealth.smbios.manufacturer`

SMBIOS system manufacturer string. Populates WMI Win32_ComputerSystem.Manufacturer.

Type: `string`. Default: `"To Be Filled By O.E.M."`.

### `virtualisation.vfio-stealth.smbios.memory.errorCorrection`

SMBIOS type 16 memory array error correction per DSP0134: 1 = Other, 2 = Unknown, 3 = None, 4 = Parity, 5 = Single-bit ECC, 6 = Multi-bit ECC, 7 = CRC. A consumer desktop with non-ECC DIMMs reports 3; QEMU writes 6, which no such board has. Populates WMI Win32_PhysicalMemoryArray.MemoryErrorCorrection. Goes into packages.qemu.

Type: `integer between 1 and 7 (both inclusive)`. Default: `3`.

### `virtualisation.vfio-stealth.smbios.memory.manufacturer`

DIMM manufacturer for SMBIOS type 17. Populates WMI Win32_PhysicalMemory.Manufacturer. Set to your real RAM vendor.

Type: `string`. Default: `"Unknown"`.

### `virtualisation.vfio-stealth.smbios.memory.maxCapacityGb`

The board's maximum memory in GB for the SMBIOS type 16 memory array, as `dmidecode -t 16` shows it under Maximum Capacity; AMD AM5 boards report 128. QEMU reports the VM's memory. A domain whose memory exceeds what its populated slots take, maxCapacityGb divided over every slot, is refused. Populates WMI Win32_PhysicalMemoryArray.MaxCapacity. Goes into packages.qemu.

Type: `positive integer, meaning >0`. Default: `128`.

### `virtualisation.vfio-stealth.smbios.memory.partNumber`

DIMM part number. Populates WMI Win32_PhysicalMemory.PartNumber. Set to your real DIMM part number.

Type: `string`. Default: `"Unknown"`.

### `virtualisation.vfio-stealth.smbios.memory.rank`

Rank of every populated SMBIOS type 17 device, as `dmidecode -t 17` shows it; a 16 GB DDR5 DIMM is single rank, a 32 GB one dual rank. QEMU writes Unknown. Goes into packages.qemu.

Type: `integer between 1 and 15 (both inclusive)`. Default: `1`.

### `virtualisation.vfio-stealth.smbios.memory.slots`

Every DIMM slot of the board in `dmidecode -t 17` order, one SMBIOS type 17 memory device each, and the slot count of the type 16 memory array. The default is the four slots of an AMD AM5 board with the second slot of each channel populated, as its manual asks for two modules. QEMU builds one memory device per machine-type chunk of the VM's memory, named by loc_pfx and an index, and no empty slot. Populates WMI Win32_PhysicalMemory and Win32_PhysicalMemoryArray.MemoryDevices. Goes into packages.qemu.

Type: `non-empty (list of (submodule))`.

Default:

```nix
[
  { locator = "DIMM 0"; bank = "P0 CHANNEL A"; populated = false; }
  { locator = "DIMM 1"; bank = "P0 CHANNEL A"; populated = true; }
  { locator = "DIMM 0"; bank = "P0 CHANNEL B"; populated = false; }
  { locator = "DIMM 1"; bank = "P0 CHANNEL B"; populated = true; }
]
```

### `virtualisation.vfio-stealth.smbios.memory.slots.*.bank`

The slot's Bank Locator, as `dmidecode -t 17` shows it.

Type: `string matching the pattern [A-Za-z0-9 _./#:-]{1,64}`.

### `virtualisation.vfio-stealth.smbios.memory.slots.*.locator`

The slot's Locator, as `dmidecode -t 17` shows it.

Type: `string matching the pattern [A-Za-z0-9 _./#:-]{1,64}`.

### `virtualisation.vfio-stealth.smbios.memory.slots.*.populated`

Whether the slot holds one of the VM's modules. The VM's memory is split evenly over the populated slots; an empty slot reports No Module Installed.

Type: `boolean`.

### `virtualisation.vfio-stealth.smbios.memory.slots.*.serial`

The module's Serial Number, as `dmidecode -t 17` shows it. null takes eight hex digits derived from identity.seed and the slot's place, or none without a seed. An empty slot reports none.

Type: `null or string matching the pattern [A-Za-z0-9]{1,32}`. Default: `null`.

### `virtualisation.vfio-stealth.smbios.memory.speed`

Memory speed in MT/s. Populates WMI Win32_PhysicalMemory.Speed.

Type: `positive integer, meaning >0`. Default: `4800`.

### `virtualisation.vfio-stealth.smbios.memory.type`

Memory type of every populated SMBIOS type 17 device, one of the DSP0134 7.18.2 names in smbios/memory-types.nix, as the Type line of `dmidecode -t 17` shows it. QEMU writes RAM, which no DIMM reports. Populates WMI Win32_PhysicalMemory.SMBIOSMemoryType. Goes into packages.qemu.

Type: `one of "3DRAM", "CDRAM", "DDR", "DDR2", "DDR2 FB-DIMM", "DDR3", "DDR4", "DDR5", "DRAM", "EDRAM", "EEPROM", "EPROM", "FBD2", "FEPROM", "Flash", "HBM", "HBM2", "HBM3", "LPDDR", "LPDDR2", "LPDDR3", "LPDDR4", "LPDDR5", "Logical non-volatile device", "MRDIMM", "Other", "RAM", "RDRAM", "ROM", "SDRAM", "SGRAM", "SRAM", "Unknown", "VRAM"`. Default: `"DDR5"`.

### `virtualisation.vfio-stealth.smbios.memory.typeDetail`

Type Detail bit field of every populated SMBIOS type 17 device, DSP0134 7.18.3: 128 = Synchronous, 16384 = Unbuffered (Unregistered), 8192 = Registered (Buffered). The default 16512 is the Synchronous Unbuffered (Unregistered) a desktop DDR5 DIMM reports; QEMU writes Other. Populates WMI Win32_PhysicalMemory.TypeDetail. Goes into packages.qemu.

Type: `16 bit unsigned integer; between 0 and 65535 (both inclusive)`. Default: `16512`.

### `virtualisation.vfio-stealth.smbios.memory.voltageMillivolts`

Minimum, maximum and configured voltage in millivolts of every populated SMBIOS type 17 device, as `dmidecode -t 17` shows them in volts; a module running an XMP or EXPO profile reports its own. null reports Unknown, as QEMU does. Populates WMI Win32_PhysicalMemory.ConfiguredVoltage. Goes into packages.qemu.

Type: `null or integer between 1 and 65535 (both inclusive)`. Default: the JEDEC voltage of smbios.memory.type: 1100 for DDR5, 1200 for DDR4, 1500 for DDR3, null otherwise.

### `virtualisation.vfio-stealth.smbios.oemStrings`

OEM Strings for SMBIOS Type 11. Real boards populate 4-6 entries. Empty Type 11 is a VM indicator.

Type: `list of string`.

Default:

```nix
[
  "Default string"
  "Default string"
  "Default string"
  "Default string"
]
```

### `virtualisation.vfio-stealth.smbios.onboardDevices`

Onboard devices for SMBIOS Type 41. Set to match your board (e.g., LAN, SATA controllers from dmidecode -t 41). Empty = no Type 41 entries.

Type: `list of (submodule)`. Default: `[ ]`.

### `virtualisation.vfio-stealth.smbios.onboardDevices.*.designation`

Device designation string.

Type: `string`.

### `virtualisation.vfio-stealth.smbios.onboardDevices.*.instance`

Device instance number.

Type: `integer between 1 and 255 (both inclusive)`.

### `virtualisation.vfio-stealth.smbios.onboardDevices.*.kind`

Device type.

Type: `one of "other", "unknown", "video", "scsi", "ethernet", "tokenring", "sound", "pata", "sata", "sas"`.

### `virtualisation.vfio-stealth.smbios.perDomainSerials`

Give each VM in domains its own system and baseboard serial, twelve hex digits derived from the VM's name, in place of serial and baseBoardSerial. Two VMs that run at once with the same serials are two machines no vendor ships; one VM at a time keeps the host's.

Type: `boolean`. Default: `false`.

### `virtualisation.vfio-stealth.smbios.ports`

The board's port connectors in `dmidecode -t 8` order, one SMBIOS type 8 structure each, with the numbers DSP0134 gives the names dmidecode prints. Copy them from `sudo dmidecode -t 8` on the host; an empty list leaves type 8 out, as some boards do. Populates WMI Win32_PortConnector.

Type: `list of (submodule)`. Default: the port connectors an ASRock X670E Pro RS reports, from smbios/board-connectors.nix.

### `virtualisation.vfio-stealth.smbios.ports.*.externalConnectorType`

External Connector Type byte, DSP0134 7.9.2: 0 = None, 15 = PS/2, 18 = Access Bus (USB), 35 = USB Type-C Receptacle, 31 = Mini Jack (headphones).

Type: `8 bit unsigned integer; between 0 and 255 (both inclusive)`.

### `virtualisation.vfio-stealth.smbios.ports.*.externalReference`

External Reference Designator; null shows as Not Specified.

Type: `null or string matching the pattern [ -~]{1,64}`. Default: `null`.

### `virtualisation.vfio-stealth.smbios.ports.*.internalConnectorType`

Internal Connector Type byte, DSP0134 7.9.2: 0 = None, 255 = Other, 24 = 9 Pin Dual Inline (pin 10 cut), 34 = SAS/SATA Plug Receptacle.

Type: `8 bit unsigned integer; between 0 and 255 (both inclusive)`.

### `virtualisation.vfio-stealth.smbios.ports.*.internalReference`

Internal Reference Designator; null shows as Not Specified.

Type: `null or string matching the pattern [ -~]{1,64}`. Default: `null`.

### `virtualisation.vfio-stealth.smbios.ports.*.portType`

Port Type byte, DSP0134 7.9.3: 16 = USB, 13 = Keyboard Port, 14 = Mouse Port, 28 = Video Port, 29 = Audio Port, 31 = Network Port, 32 = SATA, 255 = Other.

Type: `8 bit unsigned integer; between 0 and 255 (both inclusive)`.

### `virtualisation.vfio-stealth.smbios.product`

SMBIOS product name string. Populates WMI Win32_ComputerSystem.Model.

Type: `string`. Default: `"To Be Filled By O.E.M."`.

### `virtualisation.vfio-stealth.smbios.serial`

SMBIOS system serial number. Populates WMI Win32_ComputerSystemProduct.IdentifyingNumber.

Type: `string`. Default: `"System Serial Number"`.

### `virtualisation.vfio-stealth.smbios.systemFamily`

SMBIOS type 1 Family, as `dmidecode -t 1` shows it; the default is what an ASUS Z790 board reports. Populates WMI Win32_ComputerSystem.SystemFamily.

Type: `string matching the pattern [ -~]{1,64}`. Default: `"To be filled by O.E.M."`.

### `virtualisation.vfio-stealth.smbios.systemSku`

SMBIOS type 1 SKU Number, as `dmidecode -t 1` shows it; the default is what an ASUS Z790 board reports. Populates WMI Win32_ComputerSystem.SystemSKUNumber.

Type: `string matching the pattern [ -~]{1,64}`. Default: `"SKU"`.

### `virtualisation.vfio-stealth.smbios.systemSlots`

The board's expansion slots in `dmidecode -t 9` order, one SMBIOS type 9 structure each. A slot shows no Bus Address, which QEMU can give only for a device on its root bus. Populates WMI Win32_SystemSlot.

Type: `list of (submodule)`. Default: the four PCI Express slots an ASRock X670E Pro RS reports, from smbios/board-connectors.nix.

### `virtualisation.vfio-stealth.smbios.systemSlots.*.characteristics1`

Slot Characteristics 1 bit field, DSP0134 7.10.6: 4 = 3.3 V is provided, 8 = Opening is shared.

Type: `8 bit unsigned integer; between 0 and 255 (both inclusive)`.

### `virtualisation.vfio-stealth.smbios.systemSlots.*.characteristics2`

Slot Characteristics 2 bit field, DSP0134 7.10.7: 1 = PME signal is supported, 2 = Hot-plug, 8 = PCIe slot bifurcation is supported.

Type: `8 bit unsigned integer; between 0 and 255 (both inclusive)`.

### `virtualisation.vfio-stealth.smbios.systemSlots.*.currentUsage`

Current Usage, DSP0134 7.10.3: 3 = Available, 4 = In Use, 5 = Unavailable.

Type: `integer between 1 and 5 (both inclusive)`.

### `virtualisation.vfio-stealth.smbios.systemSlots.*.dataBusWidth`

Slot Data Bus Width, DSP0134 7.10.2: 8 = x1, 10 = x4, 11 = x8, 13 = x16.

Type: `integer between 1 and 14 (both inclusive)`.

### `virtualisation.vfio-stealth.smbios.systemSlots.*.designation`

The slot's Designation.

Type: `string matching the pattern [ -~]{1,64}`.

### `virtualisation.vfio-stealth.smbios.systemSlots.*.id`

Slot ID.

Type: `16 bit unsigned integer; between 0 and 65535 (both inclusive)`.

### `virtualisation.vfio-stealth.smbios.systemSlots.*.length`

Slot Length, DSP0134 7.10.4: 3 = Short, 4 = Long.

Type: `integer between 1 and 6 (both inclusive)`.

### `virtualisation.vfio-stealth.smbios.systemSlots.*.type`

Slot Type byte, DSP0134 7.10.1: 165 = PCI Express, 182 = PCI Express 3 x16, 189 = PCI Express 4 x16, 195 = PCI Express 5 x16, 23 = M.2 Socket 3.

Type: `8 bit unsigned integer; between 0 and 255 (both inclusive)`.

### `virtualisation.vfio-stealth.smbios.systemVersion`

SMBIOS type 1 Version, as `dmidecode -t 1` shows it; the default is what an ASUS Z790 board reports. Populates WMI Win32_ComputerSystemProduct.Version.

Type: `string matching the pattern [ -~]{1,64}`. Default: `"System Version"`.

### `virtualisation.vfio-stealth.spoofMac`

Give the network card of every VM in domains a MAC address that starts with macPrefix, so its maker is not QEMU's 52:54:00. The last three bytes come from the VM's uuid, so they stay fixed.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.stripVirtio`

List the VirtIO balloon, RNG and tablet devices in domain.devicesToRemove, for the VM definition to leave out. This flake removes nothing from a domain itself.

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.timing.enable`

BetterTiming TSC compensation: traps RDTSC and RDTSCP in every VM on the host, and hides from every guest TSC read the time KVM spends between a CPUID, RDTSC, RDTSCP, WBINVD, XSETBV or INVD exit, or a guest read of the TSC MSR, and the next entry.

Type: `boolean`. Default: `cpuVendor == "amd"`.

### `virtualisation.vfio-stealth.tpm.firmwareVersion`

TPM firmware version, id: and 8 hex digits, such as id:000F0018 for firmware 15.24 of an Infineon SLB9672. The guest reads it as TPM2_PT_FIRMWARE_VERSION_1 and in the EK certificate.

Type: `string matching the pattern ^id:[0-9A-Fa-f]{8}$`. Default: `"id:000F0018"`.

### `virtualisation.vfio-stealth.tpm.harden`

Turn on libvirt's swtpm and make it report a real TPM's identity: the EK and platform certificates (swtpm-localca.options) and the manufacturer and model (libtpms patch).

Type: `boolean`. Default: `true`.

### `virtualisation.vfio-stealth.tpm.manufacturer`

TPM manufacturer ID, id: and 8 hex digits: the TCG vendor code in ASCII, such as id:49465800 (IFX, Infineon), id:414D4400 (AMD fTPM) or id:494E5443 (INTC, Intel PTT). The guest reads it as TPM2_PT_MANUFACTURER and in the EK certificate.

Type: `string matching the pattern ^id:[0-9A-Fa-f]{8}$`. Default: `"id:49465800"`.

### `virtualisation.vfio-stealth.tpm.model`

TPM model string. Common: SLB9672 (Infineon discrete), AMD (fTPM).

Type: `string matching the pattern ^[a-zA-Z0-9 _-]{1,16}$`. Default: `"SLB9672"`.

### `virtualisation.vfio-stealth.tpm.platformManufacturer`

Platform manufacturer in the TPM platform certificate.

Type: `string matching the pattern ^[^"]+$`. Default: `smbios.manufacturer`.

### `virtualisation.vfio-stealth.tpm.platformModel`

Platform model in the TPM platform certificate.

Type: `string matching the pattern ^[^"]+$`. Default: `smbios.product`.

### `virtualisation.vfio-stealth.user`

The user who runs the Looking Glass client. With kvmfr.enable, /dev/kvmfr0 belongs to this user, so the client opens it without root. A VM's sound plays through this user's PipeWire.

Type: `null or (string, not containing newlines or colons)`. Default: `null`. Example: `"alice"`.
