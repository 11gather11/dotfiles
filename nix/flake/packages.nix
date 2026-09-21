{
  perSystem =
    { config, localPkgs, ... }:
    {
      # Expose custom overlay packages as flake outputs so nix-update --flake
      # can target them directly.
      packages = {
        inherit (localPkgs)
          herdr-automatic-rename
          herdr-command-palette
          herdr-keymap
          herdr-nvim
          herdr-pluck
          herdr-window-title-sync
          herdr-worktrunk
          ;
      };

      # DevShell with pre-commit hooks
      devShells.default = localPkgs.mkShell {
        shellHook = ''
          ${config.pre-commit.installationScript}
        '';
      };
    };
}
