{
  maxCapacityGb = 128;
  type = "DDR5";
  typeDetail = 16512;
  rank = 1;
  nominalMillivolts = {
    DDR3 = 1500;
    DDR4 = 1200;
    DDR5 = 1100;
  };
  slots = [
    {
      locator = "DIMM 0";
      bank = "P0 CHANNEL A";
      populated = false;
      serial = null;
    }
    {
      locator = "DIMM 1";
      bank = "P0 CHANNEL A";
      populated = true;
      serial = null;
    }
    {
      locator = "DIMM 0";
      bank = "P0 CHANNEL B";
      populated = false;
      serial = null;
    }
    {
      locator = "DIMM 1";
      bank = "P0 CHANNEL B";
      populated = true;
      serial = null;
    }
  ];
}
