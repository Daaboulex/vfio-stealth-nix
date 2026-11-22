 DefinitionBlock ("", "SSDT", 1, "ALASKA", "A M I   ", 0x00000001)
 {
     External (_SB_.PCI0, DeviceObj)

     Scope (_SB.PCI0)
     {
         Device (BAT0)
         {
             Name (_HID, EisaId ("PNP0C0A"))
             Name (_UID, Zero)
             Method (_STA, 0, NotSerialized)
             {
                 Return (0x1F)
             }

             Method (_BIF, 0, NotSerialized)
             {
                 Return (Package (0x0D)
                 {
                     One,
                     0x1770,
                     0x1770,
                     One,
                     0x39D0,
                     0x0258,
                     0x012C,
                     0x3C,
                     0x3C,
                     "PABAS0241231",
                     "41167",
                     "LION",
                     "Compal"
                 })
             }

             Method (_BST, 0, NotSerialized)
             {
                 Return (Package (0x04)
                 {
                     Zero,
                     Zero,
                     0x1770,
                     0x39D0
                 })
             }
         }
     }
 }
