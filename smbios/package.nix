{
  lib,
  stdenvNoCC,
  makeWrapper,
  dmidecode,
  coreutils,
}:

stdenvNoCC.mkDerivation {
  pname = "smbios-extract";
  version = "1.0.0";

  src = ./extract.sh;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/smbios-extract
    chmod +x $out/bin/smbios-extract
    wrapProgram $out/bin/smbios-extract \
      --prefix PATH : ${
        lib.makeBinPath [
          dmidecode
          coreutils
        ]
      }
  '';

  meta = {
    description = "Dump and anonymize host SMBIOS tables for VM injection";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "smbios-extract";
  };
}
