{ lib }:

let
  digest = seed: tag: builtins.hashString "sha256" "${seed}:${tag}";
  hexValue = text: (builtins.fromTOML "v = 0x${text}").v;
in
{
  hex =
    seed: tag: length:
    lib.toUpper (builtins.substring 0 length (digest seed tag));

  digits =
    seed: tag: length:
    lib.concatMapStrings (c: toString (lib.mod (hexValue c) 10)) (
      lib.stringToCharacters (builtins.substring 0 length (digest seed tag))
    );

  number = seed: tag: hexValue (builtins.substring 0 8 (digest seed tag));

  uuid =
    seed: tag:
    let
      hash = digest seed tag;
      part = start: length: builtins.substring start length hash;
      variant = builtins.elemAt [
        "8"
        "9"
        "a"
        "b"
      ] (lib.mod (hexValue (part 16 1)) 4);
    in
    "${part 0 8}-${part 8 4}-4${part 13 3}-${variant}${part 17 3}-${part 20 12}";

  memorySlots =
    seed: slots:
    lib.imap0 (
      index: slot:
      slot
      // {
        serial =
          if slot.serial != null || seed == null then
            slot.serial
          else
            lib.toUpper (builtins.substring 0 8 (digest seed "memory:${toString index}"));
      }
    ) slots;

  domainSerial =
    seed: name: tag:
    lib.toUpper (
      builtins.substring 0 12 (digest (if seed == null then name else "${seed}:${name}") tag)
    );
}
