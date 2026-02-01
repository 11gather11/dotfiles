{
  pkgs,
  # config,
  lib,
  helpers,
  # dotfilesDir,
  ...
}:
# let
#   inherit (config.home) homeDirectory;
#   inherit (config.xdg) configHome;
# in
{
  # Linux-specific dotfile symlinks
  home.activation.linkDotfilesLinux = lib.hm.dag.entryAfter [ "linkGeneration" ] (
    lib.optionalString (!pkgs.stdenv.isDarwin) ''
      ${helpers.activation.mkLinkForce}
    ''
  );
}
