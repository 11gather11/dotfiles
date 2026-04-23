{
  pkgs,
  lib,
  config,
  dotfilesDir,
  helpers,
  ...
}:
let
  nvimDotfilesDir = "${dotfilesDir}/nvim";
  nvimConfigDir = "${config.xdg.configHome}/nvim";
in
{
  programs.neovim = {
    enable = true;
    withPython3 = false;
    withRuby = false;
    withNodeJs = false;
  };

  # Prevent home-manager from generating ~/.config/nvim/init.lua
  # since linkNvimConfig below symlinks the entire nvim dir from dotfiles
  xdg.configFile."nvim/init.lua".enable = lib.mkForce false;

  # Create symlink to NeoVim configuration in dotfiles (bypassing Nix store)
  home.activation.linkNvimConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${helpers.activation.mkLinkForce}
    link_force "${nvimDotfilesDir}" "${nvimConfigDir}"
  '';

  # Restore Neovim plugins via Lazy.nvim when lock file changes
  # (Lazy.nvim itself is auto-installed by Lua config)
  home.activation.restoreNeovimPlugins = lib.hm.dag.entryAfter [ "linkNvimConfig" ] ''
    LAZY_DIR="$HOME/.local/share/nvim/lazy"
    LAZY_LOCK="${nvimDotfilesDir}/lazy-lock.json"
    LAZY_LOCK_TIMESTAMP="$LAZY_DIR/.lazy-lock-timestamp"

    # Only restore if lock file has been updated
    if [[ ! -f "$LAZY_LOCK_TIMESTAMP" ]] || [[ "$LAZY_LOCK" -nt "$LAZY_LOCK_TIMESTAMP" ]]; then
      ${pkgs.bash}/bin/bash \
        ${./check.sh} \
        "${nvimDotfilesDir}" \
        "$LAZY_DIR" \
        ${pkgs.neovim}/bin/nvim
    fi
  '';
}
