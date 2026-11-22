{
  lib,
  stdenvNoCC,
  makeWrapper,
  dmidecode,
  coreutils,
  python3,
}:

stdenvNoCC.mkDerivation {
  pname = "smbios-extract";
  version = "1.0.0";

  src = ./extract.sh;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin $out/share/smbios-extract
    cp $src $out/bin/smbios-extract
    chmod +x $out/bin/smbios-extract
    cp ${./split.py} $out/share/smbios-extract/split.py
    makeWrapper ${lib.getExe python3} $out/bin/smbios-split \
      --add-flags "-I $out/share/smbios-extract/split.py"
    wrapProgram $out/bin/smbios-extract \
      --prefix PATH : ${
        lib.makeBinPath [
          dmidecode
          coreutils
        ]
      }:$out/bin
  '';

  meta = {
    description = "Dump the host's SMBIOS tables and write them as the per-structure files QEMU's -smbios file= accepts";
    license = lib.licenses.gpl2Only;
    inherit (dmidecode.meta) platforms;
    mainProgram = "smbios-extract";
  };
}
