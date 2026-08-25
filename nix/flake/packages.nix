{
  perSystem =
    { config, localPkgs, ... }:
    {
      # Expose custom overlay packages as flake outputs so nix-update --flake
      # can target them (e.g. `nix-update --flake herdr-hunk-diff`).
      packages = {
        inherit (localPkgs)
          herdr-hunk-diff
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
