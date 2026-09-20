{
  lib,
  stdenvNoCC,
  python3,
}:

stdenvNoCC.mkDerivation {
  pname = "stealth-detect-arm64";
  version = "1.0.0";

  src = ./stealth-detect.py;

  buildInputs = [ python3 ];

  dontUnpack = true;

  installPhase = ''
    install -Dm755 $src $out/bin/stealth-detect-arm64
    patchShebangs --host $out/bin/stealth-detect-arm64
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/stealth-detect-arm64 --help > /dev/null
  '';

  meta = {
    description = "Report, per vector, whether an aarch64 guest can tell it is virtualized";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
    mainProgram = "stealth-detect-arm64";
  };
}
