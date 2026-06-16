/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20240927 (64-bit version)
 * Copyright (c) 2000 - 2023 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of CUSTOM.aml
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x00000255 (597)
 *     Revision         0x01
 *     Checksum         0xC4
 *     OEM ID           "_ASUS_"
 *     OEM Table ID     "Notebook"
 *     OEM Revision     0x00000001 (1)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20240927 (539232551)
 */
DefinitionBlock ("", "SSDT", 1, "ALASKA", "A M I   ", 0x20250321)
{
    Scope (_SB)
    {
        Device (PWRB)
        {
            Name (_HID, EisaId ("PNP0C0C") /* Power Button Device */)
            Method (_STA, 0, NotSerialized)
            {
                Return (0x0B)
            }
        }

        Device (SLPB)
        {
            Name (_HID, EisaId ("PNP0C0E") /* Sleep Button Device */)
            Name (_STA, 0x0B)
        }

        Device (ACAD)
        {
            Name (_HID, "ACPI0003" /* Power Source Device */)
            Name (_PCL, Package (0x01)
            {
                _SB
            })
            Name (ACP, Ones)
            Method (_PSR, 0, NotSerialized)
            {
                Return (One)
            }

            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }
        }

        Device (PIT0)
        {
            Name (_HID, "PNP0000")
            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }
        }

        Device (TIMR)
        {
            Name (_HID, "PNP0100")
            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }
        }

        Device (VLT0)
        {
            Name (_HID, "PNP0C02")
            Name (_STR, Unicode ("Voltage Regulator Module"))
            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }
        }

        // Fan and system thermal zone -- standalone (no EC hardware in Q35)
        PowerResource (PFAN, 0x00, 0x0000)
        {
            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }

            Method (_ON, 0, NotSerialized)
            {
            }

            Method (_OFF, 0, NotSerialized)
            {
            }
        }

        Device (FAN0)
        {
            Name (_HID, EisaId ("PNP0C0B") /* Fan (Thermal Solution) */)
            Name (_PR0, Package (0x01)
            {
                PFAN
            })

            Name (FPKG, Package (3) { One, One, 0x04B0 })

            Method (_FST, 0, Serialized)
            {
                Local0 = Timer
                Local1 = (Local0 >> 29) & 0xFF
                Local1 = Local1 % 201
                FPKG [2] = 1100 + Local1
                Return (FPKG)
            }
        }

        ThermalZone (TZ0)
        {
            Method (_TMP, 0, Serialized)
            {
                Local0 = Timer
                Local1 = (Local0 >> 26) & 0x3F
                Local1 = Local1 % 61
                Local2 = 3112 + Local1
                Return (Local2)
            }

            Method (_AC0, 0, NotSerialized)
            {
                Return (0x0CD2)
            }

            Method (_PSV, 0, NotSerialized)
            {
                Return (0x0DFE)
            }

            Method (_HOT, 0, NotSerialized)
            {
                Return (0x0E30)
            }

            Method (_CRT, 0, NotSerialized)
            {
                Return (0x0E62)
            }

            Method (_SCP, 1, NotSerialized)
            {
            }

            Name (_TC1, 0x04)
            Name (_TC2, 0x03)
            Name (_TSP, 0x96)
            Name (_TZP, Zero)
            Name (_STR, Unicode ("System thermal zone"))
        }
    }
}

