{
  perSystem =
    { config, localPkgs, ... }:
    {
      # Expose custom overlay packages as flake outputs so nix-update --flake
      # can target them directly.
      packages = {
        inherit (localPkgs)
          herdr-automatic-rename
          herdr-pluck
          herdr-which-key
          herdr-window-title-sync
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
