{
  rustPlatform,
  lib,
}: let
  src = lib.sources.sourceByRegex (lib.cleanSource ./.) ["Cargo.*" "(src)(/.*)?"];
in
  rustPlatform.buildRustPackage rec {
    version = "0.1.0";
    pname = "cube";

    inherit src;

    cargoLock = {
      lockFile = ./Cargo.lock;
    };

    meta = with lib; {
      description = "A basic NBD block server with a single gimmick";
      homepage = "https://github.com/icewind1991/cube";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  }
