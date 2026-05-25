{
  lib,
  qemu,
  autovirt,
  # EDID: Generic ASUS monitor
  edidManufacturer ? "ACI",
  edidModelAbbrev ? "ACI     ",
  edidModel ? "ASUS VG248      ",
  edidSerial ? "VG248QE",
  edidProductCode ? "0x2480",
  edidDpi ? 91,
  edidWeek ? 22,
  edidYear ? 2020,
  # ACPI OEM: Generic AMI (6-char and 8-char padded)
  acpiOemId ? "ALASKA",
  acpiOemTableId ? "A M I   ",
  # Disk: Generic WD
  diskModel ? "WDC WD10EZEX-00WN4A0     ",
  diskSerial ? "Default string",
  # Optical: Generic LG
  opticalModel ? "HL-DT-ST DVDRAM GH24NSC0 ",
}:

let
  expectedVersionPrefix = "10.2.";
in

assert lib.assertMsg (lib.hasPrefix expectedVersionPrefix qemu.version)
  "qemu-stealth: expected QEMU ${expectedVersionPrefix}x but got ${qemu.version} — update the patch";

(qemu.override {
  hostCpuOnly = true;
}).overrideAttrs
  (old: {
    pname = "qemu-stealth";
    patches = (old.patches or [ ]) ++ [
      "${autovirt}/patches/QEMU/Archive/AMD-v10.2.0.patch"
    ];
    postPatch = (old.postPatch or "") + ''
            echo "=== Applying EDK2/OVMF stealth patch ==="
            # AutoVirt EDK2 patch: clears VirtualMachine SMBIOS bit, replaces Red Hat
            # PCI vendor IDs (1B36→1022, 1234→1002), renames VMM-prefixed variables,
            # spoofs ACPI OEM fields. Applied inside QEMU's bundled roms/edk2/.
            if [ -d roms/edk2 ]; then
              # Auto-detect EDK2 patch — AutoVirt renames it per EDK2 release tag
              EDK2_PATCH=""
              for p in "${autovirt}"/patches/EDK2/AMD-edk2-stable*.patch; do
                if [ -f "$p" ]; then EDK2_PATCH="$p"; break; fi
              done
              if [ -z "$EDK2_PATCH" ]; then
                echo "FATAL: no AMD EDK2 patch found in ${autovirt}/patches/EDK2/"
                ls -la "${autovirt}/patches/EDK2/" 2>/dev/null || true
                exit 1
              fi
              echo "Using EDK2 patch: $(basename "$EDK2_PATCH")"
              patch -d roms/edk2 -p1 < "$EDK2_PATCH" || {
                echo "FATAL: EDK2 patch failed — firmware will contain VM indicators"
                exit 1
              }
              # Replace firmware vendor string with realistic value
              substituteInPlace roms/edk2/OvmfPkg/OvmfPkgX64.dsc \
                --replace-warn 'L"EDK II"' 'L"American Megatrends Inc."' || true
            fi

            echo "=== Customizing stealth QEMU with unique hardware identifiers ==="

            # EDID: patch defaults to MSI G27C4X — replace with real monitor (${edidModel})
            substituteInPlace hw/display/edid-generate.c \
              --replace-fail '"MSI"' '"${edidManufacturer}"'
            substituteInPlace hw/display/edid-generate.c \
              --replace-fail '"G27C4X"' '"${edidSerial}"'
            # SCSI INQUIRY: AutoVirt sets "MSI     " (vendor) and "MSI TARGET      " (product)
            # in scsi-bus.c — replace with realistic disk vendor/model
            substituteInPlace hw/scsi/scsi-bus.c \
              --replace-fail '"MSI     "' '"${edidModelAbbrev}"'
            substituteInPlace hw/scsi/scsi-bus.c \
              --replace-fail '"MSI TARGET      "' '"${edidModel}"'
            sed -i 's|0x10ad|${edidProductCode}|g' hw/display/edid-generate.c
            # EDID manufacture week/year: patch uses week=12 year=2025-2018(=7), real=week ${toString edidWeek} year ${toString edidYear}
            sed -i 's|edid\[16\] = 12;|edid[16] = ${toString edidWeek};|g' hw/display/edid-generate.c
            sed -i 's|2025 - 2018|${toString edidYear} - 1990|g' hw/display/edid-generate.c
            # EDID DPI: patch uses 82, real is ${toString edidDpi}
            sed -i 's|uint32_t dpi = 82;|uint32_t dpi = ${toString edidDpi};|g' hw/display/edid-generate.c

            # ACPI OEM: patch uses ALASKA/AMI — replace with configured OEM strings
            # These defines are in include/hw/acpi/aml-build.h (6-char and 8-char padded)
            sed -i 's|"ALASKA"|"${acpiOemId}"|g' include/hw/acpi/aml-build.h
            sed -i 's|"A M I   "|"${acpiOemTableId}"|g' include/hw/acpi/aml-build.h

            # QEMU0001/QEMU0002 ACPI device IDs: already patched by AutoVirt
            # (QEMU0001 → UEFI0001, QEMU0002 → UEFI0002). Previous sed
            # commands here were no-ops since the original strings no longer exist.

            # Disk model: patch uses "Hitachi HMS360404D5CF00" — replace with ${diskModel}
            substituteInPlace hw/ide/core.c \
              --replace-fail 'Hitachi HMS360404D5CF00' '${diskModel}'
            # Disk serial: AutoVirt blanks the IDE serial (drive_serial_str = '\0') — set realistic serial
            sed -i "s|s->drive_serial_str\[0\] = '\\\\0';|pstrcpy(s->drive_serial_str, sizeof(s->drive_serial_str), \"${diskSerial}\");|g" hw/ide/core.c
            # SCSI product: AutoVirt uses "Samsung SSD 980 500GB" — replace with ${diskModel}
            substituteInPlace hw/scsi/scsi-disk.c \
              --replace-fail 'Samsung SSD 980 500GB' '${diskModel}'

            # Optical drive: patch uses "HL-DT-ST BD-RE WH16NS60" in core.c — use ${opticalModel}
            substituteInPlace hw/ide/core.c \
              --replace-fail 'HL-DT-ST BD-RE WH16NS60' '${opticalModel}'

            # fw_cfg 4-byte probe signature: selector 0x0000 returns "QEMU"
            # AutoVirt patched the 8-byte DMA signature but left this 4-byte probe.
            # Kernel-mode scanners can detect it via inb(0x511) after outw(0x510, 0x0000).
            sed -i 's|fw_cfg_add_bytes(s, FW_CFG_SIGNATURE, (char \*)"QEMU", 4)|fw_cfg_add_bytes(s, FW_CFG_SIGNATURE, (char *)"AMDK", 4)|g' hw/nvram/fw_cfg.c
            if ! grep -q '"AMDK"' hw/nvram/fw_cfg.c; then
              echo "FATAL: fw_cfg signature patch failed — 4-byte probe still reads QEMU"
              exit 1
            fi

            echo "=== Stealth customization complete ==="

            echo "=== APERF/MPERF backport ==="
            # Backport APERF/MPERF MSR passthrough from AutoVirt v11 to QEMU 10.2.
            # The kernel header KVM_X86_DISABLE_EXITS_APERFMPERF (1 << 4) already exists;
            # only QEMU's own code to USE that flag is missing.
            # Gate: -overcommit cpu-pm=on (already in lib.nix).
            # Activation: -cpu host,aperfmperf=on (already in lib.nix).

            # --- 1. cpu.h: Add FEAT_6_ECX enum after FEAT_6_EAX ---
            grep -q 'FEAT_6_EAX' target/i386/cpu.h || {
              echo "FAIL: cannot find FEAT_6_EAX in target/i386/cpu.h"; exit 1; }
            sed -i '/FEAT_6_EAX/a\    FEAT_6_ECX, \/* CPUID[6].ECX *\/' target/i386/cpu.h

            # --- 2. cpu.h: Add CPUID_6_ECX_APERFMPERF define after CPUID_6_EAX_ARAT ---
            grep -q '#define CPUID_6_EAX_ARAT' target/i386/cpu.h || {
              echo "FAIL: cannot find CPUID_6_EAX_ARAT in target/i386/cpu.h"; exit 1; }
            sed -i '/#define CPUID_6_EAX_ARAT/a\#define CPUID_6_ECX_APERFMPERF  (1U << 0)' target/i386/cpu.h

            # --- 3. cpu.c: Add TCG_6_ECX_FEATURES after TCG_6_EAX_FEATURES ---
            grep -q '#define TCG_6_EAX_FEATURES' target/i386/cpu.c || {
              echo "FAIL: cannot find TCG_6_EAX_FEATURES in target/i386/cpu.c"; exit 1; }
            sed -i '/#define TCG_6_EAX_FEATURES/a\#define TCG_6_ECX_FEATURES 0' target/i386/cpu.c

            # --- 4. cpu.c: Add FEAT_6_ECX entry in feature_word_info[] after FEAT_6_EAX block ---
            grep -q '\.tcg_features = TCG_6_EAX_FEATURES' target/i386/cpu.c || {
              echo "FAIL: cannot find .tcg_features = TCG_6_EAX_FEATURES in target/i386/cpu.c"; exit 1; }
            cat > /tmp/feat_6_ecx_block.c <<'FEAT_BLOCK'
          [FEAT_6_ECX] = {
              .type = CPUID_FEATURE_WORD,
              .feat_names = {
                  "aperfmperf", NULL, NULL, NULL,
                  NULL, NULL, NULL, NULL,
                  NULL, NULL, NULL, NULL,
                  NULL, NULL, NULL, NULL,
                  NULL, NULL, NULL, NULL,
                  NULL, NULL, NULL, NULL,
                  NULL, NULL, NULL, NULL,
                  NULL, NULL, NULL, NULL,
              },
              .cpuid = { .eax = 6, .reg = R_ECX, },
              .tcg_features = TCG_6_ECX_FEATURES,
          },
      FEAT_BLOCK
            # Find the closing '},' of the FEAT_6_EAX entry (line with tcg_features = TCG_6_EAX)
            # then find the next '},' after it and insert the new block.
            awk '
              /\.tcg_features = TCG_6_EAX_FEATURES/ { found=1 }
              found && /^\s*\},/ { found=0; print; inserted=1;
                while ((getline line < "/tmp/feat_6_ecx_block.c") > 0) print line;
                next }
              { print }
            ' target/i386/cpu.c > target/i386/cpu.c.tmp
            mv target/i386/cpu.c.tmp target/i386/cpu.c

            # --- 5. cpu.c: Replace *ecx = 0; in CPUID leaf 6 handler ---
            grep -q 'Thermal and Power Leaf' target/i386/cpu.c || {
              echo "FAIL: cannot find Thermal and Power Leaf in target/i386/cpu.c"; exit 1; }
            # The *ecx = 0; appears in the leaf 6 handler block after the comment.
            # Use awk: after seeing the comment, replace the first '*ecx = 0;' occurrence.
            awk '
              /Thermal and Power Leaf/ { in_leaf6=1 }
              in_leaf6 && /\*ecx = 0;/ { sub(/\*ecx = 0;/, "*ecx = env->features[FEAT_6_ECX];"); in_leaf6=0 }
              { print }
            ' target/i386/cpu.c > target/i386/cpu.c.tmp
            mv target/i386/cpu.c.tmp target/i386/cpu.c

            # --- 6. cpu.c: Add adjust_feat_level call for FEAT_6_ECX after FEAT_6_EAX ---
            grep -q 'adjust_feat_level(cpu, FEAT_6_EAX)' target/i386/cpu.c || {
              echo "FAIL: cannot find adjust_feat_level FEAT_6_EAX in target/i386/cpu.c"; exit 1; }
            sed -i '/adjust_feat_level(cpu, FEAT_6_EAX)/a\    x86_cpu_adjust_feat_level(cpu, FEAT_6_ECX);' target/i386/cpu.c

            # --- 7. kvm.c: Add APERF/MPERF CPUID reporting in kvm_arch_get_supported_cpuid ---
            grep -q 'function == 6 && reg == R_EAX' target/i386/kvm/kvm.c || {
              echo "FAIL: cannot find function == 6 && reg == R_EAX in target/i386/kvm/kvm.c"; exit 1; }
            # Insert an else-if block for function==6 && reg==R_ECX after the EAX block.
            # The EAX block ends with a line setting CPUID_6_EAX_ARAT. Find the closing '}'
            # of that if-block and append the new else-if.
            awk '
              /function == 6 && reg == R_EAX/ { in_6eax=1 }
              in_6eax && /^\s*\}/ {
                in_6eax=0
                print "        } else if (function == 6 && reg == R_ECX) {"
                print "            if (enable_cpu_pm) {"
                print "                int disable_exits = kvm_check_extension(s,"
                print "                                                        KVM_CAP_X86_DISABLE_EXITS);"
                print "                if (disable_exits & KVM_X86_DISABLE_EXITS_APERFMPERF) {"
                print "                    ret |= CPUID_6_ECX_APERFMPERF;"
                print "                }"
                print "            }"
                print "        }"
                next
              }
              { print }
            ' target/i386/kvm/kvm.c > target/i386/kvm/kvm.c.tmp
            mv target/i386/kvm/kvm.c.tmp target/i386/kvm/kvm.c

            # --- 8. kvm.c: Add APERFMPERF to disable_exits mask ---
            grep -q 'KVM_X86_DISABLE_EXITS_CSTATE)' target/i386/kvm/kvm.c || {
              echo "FAIL: cannot find KVM_X86_DISABLE_EXITS_CSTATE) in target/i386/kvm/kvm.c"; exit 1; }
            sed -i 's|KVM_X86_DISABLE_EXITS_CSTATE)|KVM_X86_DISABLE_EXITS_CSTATE | KVM_X86_DISABLE_EXITS_APERFMPERF)|g' target/i386/kvm/kvm.c

            # --- Verification ---
            echo "Verifying APERF/MPERF backport edits..."
            fail=0
            grep -q 'FEAT_6_ECX' target/i386/cpu.h || { echo "VERIFY FAIL: FEAT_6_ECX missing from cpu.h"; fail=1; }
            grep -q 'CPUID_6_ECX_APERFMPERF' target/i386/cpu.h || { echo "VERIFY FAIL: CPUID_6_ECX_APERFMPERF missing from cpu.h"; fail=1; }
            grep -q 'FEAT_6_ECX' target/i386/cpu.c || { echo "VERIFY FAIL: FEAT_6_ECX missing from cpu.c"; fail=1; }
            grep -q 'aperfmperf' target/i386/cpu.c || { echo "VERIFY FAIL: aperfmperf feat_name missing from cpu.c"; fail=1; }
            grep -q 'features\[FEAT_6_ECX\]' target/i386/cpu.c || { echo "VERIFY FAIL: FEAT_6_ECX lookup missing from cpu.c leaf 6"; fail=1; }
            grep -q 'CPUID_6_ECX_APERFMPERF' target/i386/kvm/kvm.c || { echo "VERIFY FAIL: CPUID_6_ECX_APERFMPERF missing from kvm.c"; fail=1; }
            grep -q 'KVM_X86_DISABLE_EXITS_APERFMPERF' target/i386/kvm/kvm.c || { echo "VERIFY FAIL: KVM_X86_DISABLE_EXITS_APERFMPERF missing from kvm.c"; fail=1; }
            if [ "$fail" -ne 0 ]; then
              echo "FATAL: APERF/MPERF backport verification failed"
              exit 1
            fi
            echo "=== APERF/MPERF backport complete ==="
    '';
  })
