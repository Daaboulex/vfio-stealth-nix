# Security Policy

## Supported Versions

This repository tracks upstream releases. The latest commit on the default branch is the only supported version.

## Reporting a Vulnerability

Please report security vulnerabilities privately via GitHub Security Advisories:

1. Go to the repository's **Security** tab.
2. Click **Report a vulnerability**.
3. Provide:
   - A description of the issue
   - Steps to reproduce
   - Potential impact
   - Any suggested mitigations

You will receive an initial response within 7 days. If the report is confirmed, a fix will be prepared privately and released with an advisory.

Please do **not** open public issues for security problems.

## Scope

This repository applies source-level patches to QEMU and EDK2/OVMF, generates binary SMBIOS/ACPI artifacts, and provides a NixOS module with kernel post-patch scripts. Security issues within unmodified upstream software should be reported to the upstream project. This repo's security scope covers:

- Patches that introduce memory safety or logic bugs in QEMU/EDK2/kernel
- Build-time supply-chain issues (unpinned inputs, missing hash verification)
- NixOS module configuration surface (options that could expose host data)
- Generated binary artifacts (SMBIOS tables, ACPI AML) that could crash firmware
- Misconfigured CI secrets or tokens
- Malicious overlay or flake output surface
