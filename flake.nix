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

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
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
      treefmt-nix,
      brew-nix,
      nix-index-database,
      ...
    }:
    let
      username = "11gather11";
      darwinHomedir = "/Users/${username}";
      linuxHomedir = "/home/${username}";

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

      # Helper to create Linux home configuration
      mkLinuxHomeConfig =
        linuxSystem:
        home-manager.lib.homeManagerConfiguration {
          pkgs = mkPkgs linuxSystem;
          modules = [
            {
              home.username = username;
              home.homeDirectory = linuxHomedir;
            }
            (
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
                  nix-index-database.hmModules.nix-index

                  (import ./nix/modules/home {
                    inherit
                      pkgs
                      config
                      lib
                      ;
                    dotfilesDir = "${linuxHomedir}/ghq/github.com/${username}/dotfiles";
                    system = linuxSystem;
                    nodePackages = import ./nix/packages/node { inherit pkgs; };
                  })

                  # (import ./nix/modules/linux {
                  #   inherit
                  #     pkgs
                  #     config
                  #     lib
                  #     helpers
                  #     ;
                  #   homedir = linuxHomedir;
                  # })
                ];
              }
            )
          ];
        };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [
        inputs.treefmt-nix.flakeModule
      ];

      perSystem =
        {
          config,
          system,
          ...
        }:
        let
          localPkgs = mkPkgs system;
          inherit (localPkgs.stdenv) isDarwin;
          homedir = if isDarwin then darwinHomedir else linuxHomedir;
          hostname = username;
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

        };

      flake = {
        darwinConfigurations.${username} = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";

          modules = [
            (import ./nix/modules/darwin/system.nix {
              pkgs = mkPkgs "aarch64-darwin";
              inherit (nixpkgs) lib;
              inherit username;
              homedir = darwinHomedir;
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
                        dotfilesDir = "${darwinHomedir}/ghq/github.com/${username}/dotfiles";
                        system = "aarch64-darwin";
                        nodePackages = import ./nix/packages/node { inherit pkgs; };
                      })
                    ];
                  };
              };
            }
          ];
        };



        # Linux configurations with standalone Home Manager
        homeConfigurations = {
          ${username} = mkLinuxHomeConfig "x86_64-linux";
          "${username}-aarch64" = mkLinuxHomeConfig "aarch64-linux";
        };
      };
    };
}
