# vfio-stealth-nix

VM anti-detection stack for NixOS — QEMU, OVMF, ACPI, SMBIOS, timing.

## Components

- **qemu-stealth** — Patched QEMU with anti-detection (AutoVirt AMD patch + hardware customizations)
- **ovmf-stealth** — Patched EDK2/OVMF firmware (hides VM BIOS signatures)
- **acpi-ssdt-stealth** — Compiled ACPI tables (fake EC, fan, thermal zone, battery)
- **smbios-extract** — Host SMBIOS dump + anonymization tool
- **Kernel patches** — BetterTiming TSC compensation + CPUID spoofing (via NixOS module)

## Usage

Add as a flake input:

```nix
vfio-stealth.url = "github:Daaboulex/vfio-stealth-nix";
```

Import the overlay and NixOS module in your host config.

## License

GPL-2.0 (kernel patches mandate GPL)
