{
  description = "11gather11's home-manager configuration";

  # Note: cachix configuration is defined in nix/cachix.nix
  # but nixConfig must be a literal set, so we inline it here
  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://cache.numtide.com"
      "https://devenv.cachix.org"
      "https://ryoppippi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "ryoppippi.cachix.org-1:b2LbtWNvJeL/qb1B6TYOMK+apaCps4SCbzlPRfSQIms="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

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

    llm-agents.url = "github:numtide/llm-agents.nix";

    claude-code-overlay = {
      url = "github:ryoppippi/claude-code-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    brew-nix = {
      url = "github:BatteredBunny/brew-nix";
      inputs = {
        brew-api.follows = "brew-api";
        nix-darwin.follows = "nix-darwin";
        nixpkgs.follows = "nixpkgs";
      };
    };

    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };

    fish-na = {
      url = "github:ryoppippi/fish-na";
      flake = false;
    };

    gh-graph = {
      url = "github:kawarimidoll/gh-graph";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
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
      flake-parts,
      nix-darwin,
      home-manager,
      llm-agents,
      claude-code-overlay,
      brew-nix,
      fish-na,
      gh-graph,
      nix-index-database,
      treefmt-nix,
      git-hooks,
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
              _llm-agents = llm-agents;
              _claude-code-overlay = claude-code-overlay;
            })
            (import ./nix/overlays)
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
                  nix-index-database.homeModules.nix-index

                  (import ./nix/modules/home {
                    inherit
                      pkgs
                      config
                      lib
                      fish-na
                      helpers
                      ;
                    dotfilesDir = "${darwinHomedir}/ghq/github.com/11gather11/dotfiles";
                    system = "aarch64-darwin";
                  })

                  (import ./nix/modules/linux {
                    inherit
                      pkgs
                      config
                      lib
                      helpers
                      ;
                    dotfilesDir = "${darwinHomedir}/ghq/github.com/11gather11/dotfiles";
                  })
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
        treefmt-nix.flakeModule
        git-hooks.flakeModule
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
              stylua.enable = true;
              shfmt.enable = true;
            };
            settings = {
              global.execlude = [
                ".git/**"
                "*.lock"
              ];
              formatter = {
                oxfmt = {
                  command = "${localPkgs.oxfmt}/bin/oxfmt";
                  options = [ "--no-error-on-unmatched-pattern" ];
                  includes = [ "*" ];
                  excludes = [
                    "nvim/template/**"
                    "nvim/lazy-lock.json"
                  ];
                };
                gitleaks = {
                  command = "${localPkgs.gitleaks}/bin/gitleaks";
                  options = [
                    "detect"
                    "--no-git"
                    "--exit-code"
                    "0"
                  ];
                  includes = [ "*" ];
                  excludes = [
                    "*.png"
                    "*.jpg"
                    "*.jpeg"
                    "*.gif"
                    "*.ico"
                    "*.pdf"
                    "*.woff"
                    "*.woff2"
                    "*.ttf"
                    "*.eot"
                    "node_modules/**"
                    ".direnv/**"
                    "nix/packages/node/**/package-lock.json"
                  ];
                };
                renovate-validator = {
                  command = "${localPkgs.renovate}/bin/renovate-config-validator";
                  options = [ "--strict" ];
                  includes = [
                    ".github/renovate.json5"
                  ];
                };
                fish-indent = {
                  command = "${localPkgs.fish}/bin/fish_indent";
                  options = [ "--write" ];
                  includes = [ "*.fish" ];
                };
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

          # Apps
          apps = {
            build = {
              type = "app";
              program = toString (
                localPkgs.writeShellScript (if isDarwin then "darwin-build" else "home-manager-build") ''
                  set -e
                  echo "Building ${if isDarwin then "darwin" else "Home Manager"} configuration..."
                  nix build .#${
                    if isDarwin then
                      "darwinConfigurations.${hostname}.system"
                    else
                      "homeConfigurations.${username}.activationPackage"
                  }
                  echo "Build successful! Run 'nix run .#switch' to apply."
                ''
              );
            };

            switch = {
              type = "app";
              program = toString (
                localPkgs.writeShellScript (if isDarwin then "darwin-switch" else "home-manager-switch") ''
                  set -e
                  echo "Building and switching to ${if isDarwin then "darwin" else "Home Manager"} configuration..."
                  ${
                    if isDarwin then
                      "sudo nix run nix-darwin -- switch --flake .#${hostname}"
                    else
                      "nix run nixpkgs#home-manager -- switch --flake .#${username}"
                  }
                  echo "Clearing fish cache..."
                  rm -rf "$TMPDIR/fish-cache"
                  echo "Done!"
                ''
              );
            };

            update = {
              type = "app";
              program = toString (
                localPkgs.writeShellScript "flake-update" ''
                  set -e
                  echo "Updating flake.lock..."
                  nix flake update
                  echo "Done! Run 'nix run .#switch' to apply changes."
                ''
              );
            };

            fmt = {
              type = "app";
              program = toString (
                localPkgs.writeShellScript "treefmt-wrapper" ''
                  exec ${config.treefmt.build.wrapper}/bin/treefmt "$@"
                ''
              );
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
        # macOS configuration with nix-darwin
        darwinConfigurations.${username} = nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";

          modules = [
            (import ./nix/modules/darwin/system.nix {
              pkgs = mkPkgs "aarch64-darwin";
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
                          fish-na
                          helpers
                          ;
                        dotfilesDir = "${darwinHomedir}/ghq/github.com/11gather11/dotfiles";
                        system = "aarch64-darwin";
                      })

                      (import ./nix/modules/darwin {
                        inherit
                          pkgs
                          config
                          lib
                          helpers
                          ;
                        dotfilesDir = "${darwinHomedir}/ghq/github.com/11gather11/dotfiles";
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
