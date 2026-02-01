{
  description = "11gather11's home-manager configuration";

  # Note: cachix configuration is defined in nix/cachix.nix
  # but nixConfig must be a literal set, so we inline it here
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    systems.url = "github:nix-systems/default";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      systems,
      flake-parts,
      treefmt-nix,
      git-hooks,
      ...
    }:
    let
      # username = "11gather11";
      # darwinHomedir = "/Users/${username}";
      # linuxHomedir = "/home/${username}";

      # Create pkgs with overlays
      mkPkgs =
        system:
        # let
        #   isDarwin = builtins.match ".*-darwin" system != null;
        # in
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            # (final: prev: {
            #   home-manager = prev.callPackage ./nix/home-manager-overlay.nix { inherit isDarwin darwinHomedir linuxHomedir; };
            # })
          ];
        };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        treefmt-nix.flakeModule
        git-hooks.flakeModule
      ];

      systems = import systems;

      perSystem =
        {
          config,
          system,
          ...
        }:
        let
          localPkgs = mkPkgs system;
        in
        {
          # Treefmt configuration
          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt = {
                enable = true;
                package = localPkgs.nixfmt-rfc-style;
              };
            };
          };

          # Git hooks configuration
          pre-commit = {
            settings.hooks = {
              treefmt = {
                enable = true;
                package = config.treefmt.build.wrapper;
              };
              deadnix.enable = true;
              statix.enable = true;
            };
          };

          # DevShell with pre-commit hooks
          devShells.default = localPkgs.mkShell {
            shellHook = ''
              ${config.pre-commit.installationScript}
            '';
          };
        };

      flake = {
      };
    };
}
