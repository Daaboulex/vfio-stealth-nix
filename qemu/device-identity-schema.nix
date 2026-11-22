let
  usbId = {
    pattern = "0x[0-9a-f]{4}";
    form = "0x and four lower-case hex digits";
  };
  text = {
    pattern = "[A-Za-z0-9 .,()/+_-]{1,64}";
    form = "1 to 64 letters, digits, spaces or any of .,()/+_-";
  };
  serialLength = {
    min = 1;
    max = 64;
    form = "the length of the serial derived from the VM uuid, 1 to 64";
  };
  usb = {
    vendor = usbId;
    product = usbId;
    manufacturer = text;
    name = text;
  };
in
{
  usbStorageBridge = usb // {
    inherit serialLength;
  };
  usbHub = {
    vendor = usbId;
    product = usbId;
  };
  usbSerial = usb // {
    release = usbId;
    inherit serialLength;
  };
  usbBraille = {
    manufacturer = text;
    name = text;
  };
  usbSmartcard = {
    manufacturer = text;
    name = text;
    release = usbId;
    inherit serialLength;
  };
  usbFidoKey = usb;
  usbTablet.manufacturer = text;
  usbAudio = usb // {
    release = usbId;
  };
  usbPhone = {
    vendor = usbId;
    mtpProduct = usbId;
    tetherProduct = usbId;
    manufacturer = text;
    name = text;
    androidRelease = {
      pattern = "[0-9]{1,2}(\\.[0-9]{1,2}){0,2}";
      form = "an Android release such as 12 or 13.0.1";
    };
    inherit serialLength;
  };
  vmgenidHardwareId = {
    pattern = "[A-Za-z0-9_]{1,32}";
    form = "an ACPI hardware id of 1 to 32 letters, digits or underscores";
  };
  megasas = {
    package = {
      pattern = "[0-9][0-9.-]{0,31}";
      form = "an LSI package version such as 12.15.0-0239";
    };
    serialPrefix = {
      pattern = "[A-Z]{0,4}";
      form = "0 to 4 upper-case letters put before the serial's digits";
    };
    serialDigits = {
      min = 1;
      max = 16;
      form = "the count of digits derived from the VM uuid and the card's PCI path, 1 to 16";
    };
  };
  acpiCreator = {
    id = {
      pattern = "[A-Z0-9 ]{4}";
      form = "the 4-character creator id of a headerless -acpitable, such as \"AMI \"";
    };
    revision = {
      min = 0;
      max = 4294967295;
      form = "the 32-bit creator revision";
    };
  };
}
