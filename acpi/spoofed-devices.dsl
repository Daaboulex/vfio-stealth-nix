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
    External (_SB_.PCI0, DeviceObj)

    Scope (_SB)
    {
        Device (PWRB)
        {
            Name (_HID, EisaId ("PNP0C0C") /* Power Button Device */)  // _HID: Hardware ID
            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Return (0x0B)
            }
        }

        Device (SLPB)
        {
            Name (_HID, EisaId ("PNP0C0E") /* Sleep Button Device */)  // _HID: Hardware ID
            Name (_STA, 0x0B)  // _STA: Status
        }

        Device (ACAD)
        {
            Name (_HID, "ACPI0003" /* Power Source Device */)  // _HID: Hardware ID
            Name (_PCL, Package (0x01)  // _PCL: Power Consumer List
            {
                _SB
            })
            Name (ACP, Ones)
            Method (_PSR, 0, NotSerialized)  // _PSR: Power Source
            {
                Return (One)
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
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

        // Voltage probe — Win32_VoltageProbe WMI detection
        Device (VLT0)
        {
            Name (_HID, "PNP0C02")
            Name (_STR, Unicode ("Voltage Regulator Module"))
            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }
        }
    }

    Scope (_SB.PCI0)
    {
        Device (EC0)
        {
            Name (_HID, EisaId ("PNP0C09") /* Embedded Controller Device */)  // _HID: Hardware ID
            Name (_CRS, ResourceTemplate ()  // _CRS: Current Resource Settings
            {
                IO (Decode16,
                    0x0062,             // Range Minimum
                    0x0062,             // Range Maximum
                    0x00,               // Alignment
                    0x01,               // Length
                    )
                IO (Decode16,
                    0x0066,             // Range Minimum
                    0x0066,             // Range Maximum
                    0x00,               // Alignment
                    0x01,               // Length
                    )
            })
            Name (_GPE, Zero)  // _GPE: General Purpose Events
            OperationRegion (EC0, EmbeddedControl, Zero, 0xFF)
            Field (EC0, ByteAcc, Lock, Preserve)
            {
                MODE,   1, 
                FAN,    1, 
                Offset (0x01), 
                TMP,    16, 
                AC0,    16, 
                Offset (0x07), 
                PSV,    16, 
                CRT,    16
            }

            Method (_Q07, 0, NotSerialized)  // _Qxx: EC Query, xx=0x00-0xFF
            {
            }

            PowerResource (PFAN, 0x00, 0x0000)
            {
                Method (_STA, 0, NotSerialized)  // _STA: Status
                {
                    Return (0x0F)
                }

                Method (_ON, 0, NotSerialized)  // _ON_: Power On
                {
                }

                Method (_OFF, 0, NotSerialized)  // _OFF: Power Off
                {
                }
            }

            Device (FAN0)
            {
                Name (_HID, EisaId ("PNP0C0B") /* Fan (Thermal Solution) */)  // _HID: Hardware ID
                Name (_PR0, Package (0x01)  // _PR0: Power Resources for D0
                {
                    PFAN
                })

                Name (FPKG, Package (3) { One, One, 0x04B0 })

                // Fan speed: 1100-1300 RPM fluctuation using Timer() high bits
                // >>29 gives ~54s granularity, decorrelated from thermal zones
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
                // 38-44°C idle fluctuation using Timer() high bits
                // >>26 gives ~7s granularity, decorrelated from CPUZ (>>27) and VRMT (>>28)
                Method (_TMP, 0, Serialized)  // _TMP: Temperature
                {
                    Local0 = Timer
                    Local1 = (Local0 >> 26) & 0x3F
                    Local1 = Local1 % 61
                    Local2 = 3112 + Local1
                    Return (Local2)
                }

                // 55°C fan-on threshold
                Method (_AC0, 0, NotSerialized)  // _ACx: Active Cooling, x=0-9
                {
                    Return (0x0CD2)
                }

                // 85°C passive cooling
                Method (_PSV, 0, NotSerialized)  // _PSV: Passive Temperature
                {
                    Return (0x0DFE)
                }

                // 90°C hot
                Method (_HOT, 0, NotSerialized)  // _HOT: Hot Temperature
                {
                    Return (0x0E30)
                }

                // 95°C critical
                Method (_CRT, 0, NotSerialized)  // _CRT: Critical Temperature
                {
                    Return (0x0E62)
                }

                Method (_SCP, 1, NotSerialized)  // _SCP: Set Cooling Policy
                {
                }

                Name (_TC1, 0x04)  // _TC1: Thermal Constant 1
                Name (_TC2, 0x03)  // _TC2: Thermal Constant 2
                Name (_TSP, 0x96)  // _TSP: Thermal Sampling Period
                Name (_TZP, Zero)  // _TZP: Thermal Zone Polling
                Name (_STR, Unicode ("System thermal zone"))  // _STR: Description String
            }
        }
    }
}

