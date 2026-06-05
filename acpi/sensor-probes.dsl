/*
 * sensor-probes.dsl — Additional sensor probes for hardware emulation.
 *
 * Populates WMI classes that are empty in default QEMU VMs:
 * - MSAcpi_ThermalZoneTemperature (via additional thermal zone)
 * - Realistic CPU temperature readings
 */
DefinitionBlock ("sensor-probes.aml", "SSDT", 2, "ALASKA", "A M I   ", 0x00001000)
{
    External (\_SB, DeviceObj)

    Scope (\_SB)
    {
        // Secondary thermal zone for CPU package
        ThermalZone (CPUZ)
        {
            // CPU temperature: 52-58°C fluctuation using Timer() high bits
            // >>27 gives ~13s granularity (Timer ticks at 10MHz), matching real sensor update rate
            Method (_TMP, 0, Serialized)
            {
                Local0 = Timer
                Local1 = (Local0 >> 27) & 0x3F
                Local1 = Local1 % 61
                Local2 = 3252 + Local1
                Return (Local2)
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
            // VRM temperature: 42-48°C fluctuation using Timer() high bits
            // >>28 gives ~27s granularity, decorrelated from CPUZ
            Method (_TMP, 0, Serialized)
            {
                Local0 = Timer
                Local1 = (Local0 >> 28) & 0x3F
                Local1 = Local1 % 61
                Local2 = 3152 + Local1
                Return (Local2)
            }

            Method (_CRT, 0, Serialized)
            {
                Return (0x0F1E)  // 115°C critical
            }

            Name (_TZP, 300)  // Poll every 30 seconds
        }
    }
}
