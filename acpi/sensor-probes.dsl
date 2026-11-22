DefinitionBlock ("sensor-probes.aml", "SSDT", 2, "ALASKA", "A M I   ", 0x00001000)
{
    External (\_SB, DeviceObj)

    Scope (\_SB)
    {
        ThermalZone (CPUZ)
        {
            // why: >>27 steps about every 13 s, the update rate of a real sensor
            Method (_TMP, 0, Serialized)
            {
                Local0 = Timer
                Local1 = (Local0 >> 27) & 0x3F
                Local1 = Local1 % 61
                Local2 = 3252 + Local1
                Return (Local2)
            }

            Method (_CRT, 0, Serialized)
            {
                Return (0x0E62)
            }

            Method (_HOT, 0, Serialized)
            {
                Return (0x0E30)
            }

            Method (_PSV, 0, Serialized)
            {
                Return (0x0DFE)
            }

            Name (_TZP, 100)

            Name (_TC1, 2)
            Name (_TC2, 3)
            Name (_TSP, 100)
        }

        ThermalZone (VRMT)
        {
            // why: >>28 keeps this zone decorrelated from CPUZ
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
                Return (0x0F1E)
            }

            Name (_TZP, 300)
        }
    }
}
