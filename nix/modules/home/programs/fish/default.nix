{ config, ... }:
{
  # Generate conf.d files for PATH setup
  # Note: config.fish is managed via dotfiles symlink
  
  xdg.configFile."fish/conf.d/00-nix-home-manager-path.fish".text = ''
    # Add Home Manager packages to PATH
    fish_add_path ~/.local/state/home-manager/gcroots/current-home/home-path/bin
  '';

  xdg.configFile."fish/conf.d/01-nix-darwin-path.fish".text = ''
    # Add nix-darwin system packages to PATH
    # This includes comma, nix-locate, and other system-level packages
    if test -d /run/current-system/sw/bin
      fish_add_path /run/current-system/sw/bin
    end
  '';
}
