{
  perSystem =
    { config, localPkgs, ... }:
    {
      # Expose custom overlay packages as flake outputs so nix-update --flake
      # can target them (e.g. `nix-update --flake herdr-hunk-diff`).
      packages = {
        inherit (localPkgs)
          herdr-automatic-rename
          herdr-hunk-diff
          herdr-pluck
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
