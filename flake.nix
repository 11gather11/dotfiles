{
  description = "11gather11's home-manager configuration";

  # Note: cachix configuration is defined in nix/cachix.nix
  # but nixConfig must be a literal set, so we inline it here
  nixConfig = {
  };

  inputs = {
    nixpkgs = {
      url = "github:nixos/nixpkgs/nixpkgs-unstable";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code-overlay = {
      url = "github:ryoppippi/claude-code-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    brew-nix = {
      url = "github:BatteredBunny/brew-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nix-darwin.follows = "nix-darwin";
        brew-api.follows = "brew-api";
      };
    };

    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = 
    inputs@{
      nixpkgs,
      flake-parts,
      nix-darwin,
      home-manager,
      claude-code-overlay,
      brew-nix,
      nix-index-database,
      ...
    }:
    let
      username = "11gather11";
      darwinHomeDir = "/Users/${username}";
      linuxHomeDir = "/home/${username}";

      # Create pkgs with overlays
      mkPkgs =
        system:
        let
          isDarwin = builtins.match ".*-darwin" system != null;
        in
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            (_final: _prev: {
              _claude-code-overlay = claude-code-overlay;
            })
          ]
            ++ nixpkgs.lib.optionals isDarwin [
              brew-nix.overlays.default
            ];
        };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ 
        "aarch64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];

      flake = {
        darwinConfigurations.${username} = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";

          modules = [
            (import ./nix/modules/darwin/system.nix {
              pkgs = mkPkgs "aarch64-darwin";
              inherit (nixpkgs) lib;
              inherit username;
              homeDir = darwinHomeDir;
            })

            nix-index-database.darwinModules.nix-index
            
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = false;
                useUserPackages = true;
                extraSpecialArgs = { 
                  pkgs = mkPkgs "aarch64-darwin";
                };
                users.${username} = 
                  {
                    pkgs,
                    config,
                    lib,
                    ...
                  }:
                  let
                    helpers = import ./nix/modules/lib/helpers { inherit lib; };
                  in
                  {
                    imports = [
                      (import ./nix/modules/home {
                        inherit
                          pkgs
                          config
                          lib
                          ;
                        dotfilesDir = "${darwinHomeDir}/ghq/github.com/${username}/dotfiles";
                        system = "aarch64-darwin";
                        nodePackages = import ./nix/packages/node { inherit pkgs; };
                      })
                    ];
                  };
              };
            }
          ];
        };
      };
    };
}