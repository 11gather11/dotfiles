{
  config,
  lib,
  helpers,
  dotfilesDir,
  ...
}:
let
  inherit (config.home) homeDirectory;
  inherit (config.xdg) configHome;
in
{
  # Common dotfile symlinks for all platforms
  home.activation.linkDotfilesCommon = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    ${helpers.activation.mkLinkForce}

    # Fish shell configuration
    link_force "${dotfilesDir}/fish" "${configHome}/fish"

    # Bash configuration
    link_force "${dotfilesDir}/bash/.bash_profile" "${homeDirectory}/.bash_profile"
    link_force "${dotfilesDir}/bash/.bashrc" "${homeDirectory}/.bashrc"
  '';
}
