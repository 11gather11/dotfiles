{ pkgs, ... }:
let
  go_1_24_6 = pkgs.go_1_24.overrideAttrs (oldAttrs: rec {
    version = "1.24.6";
    src = pkgs.fetchurl {
      url = "https://go.dev/dl/go${version}.src.tar.gz";
      hash = "sha256-4ctVgqq1iGaLwEwH3hhogHD2uMmyqvNh+CHhm9R8/b0=";
    };
  });
in
{
  home.packages = [ go_1_24_6 ];
}
