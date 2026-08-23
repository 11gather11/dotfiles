{
  perSystem =
    { config, localPkgs, ... }:
    {
      # Expose custom overlay packages as flake outputs so nix-update --flake
      # can target them (e.g. `nix-update --flake yazi-eza-preview`).
      packages = {
        inherit (localPkgs)
          herdr-hunk-diff
          yazi-eza-preview
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
