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


      # Karabiner Elements configuration
      # Restart Karabiner console user server before updating config to prevent keyboard freeze
      # The daemon can enter an inconsistent state if config changes while running
      if /bin/launchctl list | ${pkgs.gnugrep}/bin/grep -q "org.pqrs.service.agent.karabiner_console_user_server"; then
        echo "Restarting Karabiner console user server before config update..."
        /bin/launchctl kickstart -k gui/$(/usr/bin/id -u)/org.pqrs.service.agent.karabiner_console_user_server 2>/dev/null || true
        sleep 2
      fi

      link_force "${dotfilesDir}/karabiner" "${configHome}/karabiner"
    ''
  );
}
