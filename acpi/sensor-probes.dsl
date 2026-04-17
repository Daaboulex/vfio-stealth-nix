/*
 * sensor-probes.dsl — Additional sensor probes for anti-detection.
 *
 * Populates WMI classes that are empty in default QEMU VMs:
 * - MSAcpi_ThermalZoneTemperature (via additional thermal zone)
 * - Realistic CPU temperature readings
 */
DefinitionBlock ("sensor-probes.aml", "SSDT", 2, "_ASUS_", "Sensors ", 0x00001000)
{
    External (\_SB, DeviceObj)

    Scope (\_SB)
    {
        // Secondary thermal zone for CPU package
        ThermalZone (CPUZ)
        {
            // CPU temperature: ~55°C idle (in 10ths of Kelvin)
            // 55°C = 328.15K = 3282 (0x0CD2)
            Method (_TMP, 0, Serialized)
            {
                Return (0x0CD2)
            }

            // Critical temperature: 95°C = 368.15K = 3682 (0x0E62)
            Method (_CRT, 0, Serialized)
            {
                Return (0x0E62)
            }

            // Hot temperature: 90°C
            Method (_HOT, 0, Serialized)
            {
                Return (0x0E30)
            }

            // Passive cooling threshold: 85°C
            Method (_PSV, 0, Serialized)
            {
                Return (0x0DFE)
            }

            // Polling period: 10 seconds (in 10ths of seconds)
            Name (_TZP, 100)

            // Thermal constants
            Name (_TC1, 2)
            Name (_TC2, 3)
            Name (_TSP, 100)
        }

        // VRM/chipset thermal zone
        ThermalZone (VRMT)
        {
            // VRM temperature: ~45°C idle = 318.15K = 3182 (0x0C6E)
            Method (_TMP, 0, Serialized)
            {
                Return (0x0C6E)
            }

            Method (_CRT, 0, Serialized)
            {
                Return (0x0F1E)  // 115°C critical
            }

            Name (_TZP, 300)  // Poll every 30 seconds
        }
    }
}
