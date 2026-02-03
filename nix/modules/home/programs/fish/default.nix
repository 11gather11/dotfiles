{ config, pkgs, ... }:
let
  # nix-env.fish plugin for Nix environment support
  nix-env-fish = pkgs.fetchFromGitHub {
    owner = "lilyball";
    repo = "nix-env.fish";
    rev = "7b65bd228429e852c8fdfa07601159130a818cfa";
    sha256 = "sha256-RG/0rfhgq6aEKNZ0XwIqOaZ6K5S4+/Y5EEMnIdtfPhk=";
  };
in
{
  # Install nix-env.fish plugin
  home.file.".local/share/fish/nix-plugins/nix-env.fish" = {
    source = nix-env-fish;
    recursive = true;
  };

  # Generate conf.d files for PATH setup and plugin initialization
  # Note: config.fish is managed via dotfiles symlink

  xdg.configFile."fish/conf.d/00-nix-env.fish".text = ''
    # Nix environment support (nix-env.fish plugin)
    set -gp fish_function_path ${nix-env-fish}/functions
    if test -d ${nix-env-fish}/conf.d
      for file in ${nix-env-fish}/conf.d/*.fish
        source $file
      end
    end
  '';

  xdg.configFile."fish/conf.d/01-nix-home-manager-path.fish".text = ''
    # Add Home Manager packages to PATH
    fish_add_path ~/.local/state/home-manager/gcroots/current-home/home-path/bin
  '';

  xdg.configFile."fish/conf.d/02-nix-darwin-path.fish".text = ''
    # Add nix-darwin system packages to PATH
    # This includes comma, nix-locate, and other system-level packages
    if test -d /run/current-system/sw/bin
      fish_add_path /run/current-system/sw/bin
    end
  '';
}
