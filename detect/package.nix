{
  lib,
  stdenvNoCC,
  python3,
}:

stdenvNoCC.mkDerivation {
  pname = "stealth-detect";
  version = "1.0.0";

  src = ./stealth-detect.py;

  buildInputs = [ python3 ];

  dontUnpack = true;

  installPhase = ''
    install -Dm755 $src $out/bin/stealth-detect
    patchShebangs --host $out/bin/stealth-detect
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/stealth-detect --help > /dev/null
  '';

  meta = {
    description = "Report, per vector, whether a Linux guest can tell it is virtualized";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    mainProgram = "stealth-detect";
  };
}
