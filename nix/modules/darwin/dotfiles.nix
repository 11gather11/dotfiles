{
  pkgs,
  config,
  lib,
  helpers,
  dotfilesDir,
  ...
}:
let
  # inherit (config.home) homeDirectory;
  inherit (config.xdg) configHome;
in
{
  # macOS-specific dotfile symlinks
  home.activation.linkDotfilesDarwin = lib.hm.dag.entryAfter [ "linkGeneration" ] (
    lib.optionalString pkgs.stdenv.isDarwin ''
      ${helpers.activation.mkLinkForce}

      # Kanata configuration
      link_force "${dotfilesDir}/kanata" "${configHome}/kanata"
    ''
  );
}
