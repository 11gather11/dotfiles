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

    flake-parts.url = "github:hercules-ci/flake-parts";

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents.url = "github:numtide/llm-agents.nix";

    nix-claude-code = {
      url = "github:ryoppippi/nix-claude-code";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-bun = {
      url = "github:ryoppippi/nix-bun";
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

    fish-na = {
      url = "github:ryoppippi/fish-na";
      flake = false;
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Agent skills framework for managing Claude Code skills
    agent-skills = {
      url = "github:Kyure-A/agent-skills-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Claude Code skills (flake = false for non-flake repos)
    ast-grep-skill = {
      url = "github:ast-grep/claude-skill";
      flake = false;
    };

    agent-browser-skill = {
      url = "github:vercel-labs/agent-browser";
      flake = false;
    };

    tgrab-skill = {
      url = "github:ryoppippi/tgrab";
      flake = false;
    };

  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      nix-darwin,
      home-manager,
      llm-agents,
      nix-claude-code,
      nix-bun,
      treefmt-nix,
      git-hooks,
      fish-na,
      nix-index-database,
      agent-skills,
      ast-grep-skill,
      agent-browser-skill,
      tgrab-skill,
      ...
    }:
    let
      username = "11gather11";
      darwinHomedir = "/Users/${username}";
      linuxHomedir = "/home/${username}";

      local-skills = nixpkgs.lib.fileset.toSource {
        root = ./.;
        fileset = ./agents/skills;
      };

      # Create pkgs with overlays
      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            # 上流が overlays.default を削除したため、その実装を再現する。
            # shared-nixpkgs は消費側の nixpkgs でビルドし直すのでバイナリキャッシュが
            # 効かず、agent-browser のフルソースビルドが走る。
            (final: _prev: {
              llm-agents = llm-agents.packages.${final.stdenv.hostPlatform.system} or { };
            })
            (_final: _prev: {
              _nix-claude-code = nix-claude-code;
            })
            nix-bun.overlays.default
            (import ./nix/overlays)
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
                  agent-skills.homeManagerModules.default

                  (import ./nix/modules/home {
                    inherit
                      pkgs
                      config
                      lib
                      fish-na
                      helpers
                      ast-grep-skill
                      agent-browser-skill
                      tgrab-skill
                      local-skills
                      ;
                    dotfilesDir = "${linuxHomedir}/ghq/github.com/11gather11/dotfiles";
                  })

                  (import ./nix/modules/linux {
                    inherit
                      pkgs
                      config
                      lib
                      helpers
                      ;
                    dotfilesDir = "${linuxHomedir}/ghq/github.com/11gather11/dotfiles";
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
          inherit (localPkgs) lib;
          inherit (localPkgs.stdenv) isDarwin;
          homedir = if isDarwin then darwinHomedir else linuxHomedir;
          hostname = username;

          # Package executables, resolved via lib.getExe so the binary name comes
          # from each package's meta.mainProgram instead of being hand-written
          # (e.g. neovim ships nvim, nix-output-monitor ships nom).
          bash = lib.getExe localPkgs.bash;
          fishIndent = lib.getExe' localPkgs.fish "fish_indent";
          gitleaks = lib.getExe localPkgs.gitleaks;
          neovim = lib.getExe localPkgs.neovim;
          nom = lib.getExe localPkgs.nix-output-monitor;
          nufmt = lib.getExe localPkgs.nufmt;
          oxfmt = lib.getExe localPkgs.oxfmt;
          treefmt = lib.getExe config.treefmt.build.wrapper;

          # Detect AI agent environments to skip nix-output-monitor
          isAgentCheck = ''
            IS_AI_AGENT=false
            for var in CLAUDE_CODE CLAUDECODE CODEX_SANDBOX CODEX_THREAD_ID GEMINI_CLI OPENCODE AUGMENT_AGENT GOOSE_PROVIDER CURSOR_AGENT AI_AGENT; do
              eval "val=\''${!var:-}"
              if [ -n "$val" ]; then
                IS_AI_AGENT=true
                break
              fi
            done
          '';

          # Keep sudo credentials warm during long Darwin switches so the
          # activation does not stall waiting for a password prompt. Runs only
          # on an interactive terminal ([ -t 0 ]); refreshes the timestamp every
          # 60s in the background and cleans the helper up on exit.
          sudoKeepAlive = localPkgs.lib.optionalString isDarwin ''
            if [ -t 0 ]; then
              sudo -v
              (
                while kill -0 "$$" 2>/dev/null; do
                  sudo -n -v || exit 0
                  sleep 60
                done
              ) &
              SUDO_KEEPALIVE_PID=$!
              trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
            fi
          '';
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
              global.excludes = [
                ".git/**"
                "*.lock"
              ];
              formatter = {
                oxfmt = {
                  command = oxfmt;
                  options = [ "--no-error-on-unmatched-pattern" ];
                  includes = [ "*" ];
                  excludes = [
                    "nvim/template/**"
                    "nvim/lazy-lock.json"
                  ];
                };
                gitleaks = {
                  command = gitleaks;
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
                fish-indent = {
                  command = fishIndent;
                  options = [ "--write" ];
                  includes = [ "*.fish" ];
                };
                nufmt = {
                  command = nufmt;
                  includes = [ "*.nu" ];
                };
              };
            };
          };

          # Git hooks configuration
          pre-commit = {
            check.enable = false;
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
            nvim-restore = {
              type = "app";
              program = toString (
                localPkgs.writeShellScript "nvim-restore" ''
                  : "''${DOTFILES_DIR:=${homedir}/ghq/github.com/11gather11/dotfiles}"
                  if [ ! -d "$DOTFILES_DIR" ]; then
                    DOTFILES_DIR="$(pwd)"
                  fi
                  exec ${bash} \
                    ${./nix/modules/home/programs/neovim/check.sh} \
                    "$DOTFILES_DIR/nvim" \
                    "$HOME/.local/share/nvim/lazy" \
                    ${neovim}
                ''
              );
            };

            build = {
              type = "app";
              program = toString (
                localPkgs.writeShellScript (if isDarwin then "darwin-build" else "home-manager-build") ''
                  set -e
                  ${isAgentCheck}
                  echo "Building ${if isDarwin then "darwin" else "Home Manager"} configuration..."
                  if [ "$IS_AI_AGENT" = true ]; then
                    nix build .#${
                      if isDarwin then
                        "darwinConfigurations.${hostname}.system"
                      else
                        "homeConfigurations.${username}.activationPackage"
                    }
                  else
                    ${nom} build .#${
                      if isDarwin then
                        "darwinConfigurations.${hostname}.system"
                      else
                        "homeConfigurations.${username}.activationPackage"
                    }
                  fi
                  echo "Build successful! Run 'nix run .#switch' to apply."
                ''
              );
            };

            switch = {
              type = "app";
              program = toString (
                localPkgs.writeShellScript (if isDarwin then "darwin-switch" else "home-manager-switch") ''
                  set -eo pipefail
                  ${isAgentCheck}
                  ${sudoKeepAlive}
                  echo "Building and switching to ${if isDarwin then "darwin" else "Home Manager"} configuration..."
                  if [ "$IS_AI_AGENT" = true ]; then
                    ${
                      if isDarwin then
                        "sudo nix run nix-darwin -- switch --flake .#${hostname}"
                      else
                        "nix run nixpkgs#home-manager -- switch --flake .#${username}"
                    }
                  else
                    ${
                      if isDarwin then
                        "sudo nix run nix-darwin -- switch --flake .#${hostname} |& ${nom}"
                      else
                        "nix run nixpkgs#home-manager -- switch --flake .#${username} |& ${nom}"
                    }
                  fi
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

            update-ai-tools = {
              type = "app";
              program = toString (
                localPkgs.writeShellScript "update-ai-tools" ''
                  set -e
                  echo "Updating AI tools inputs..."
                  nix flake update llm-agents
                  echo "Done! Run 'nix run .#switch' to apply changes."
                ''
              );
            };

            fmt = {
              type = "app";
              program = toString (
                localPkgs.writeShellScript "treefmt-wrapper" ''
                  exec ${treefmt} "$@"
                ''
              );
            };
          };

          # Expose custom overlay packages as flake outputs so nix-update --flake
          # can target them (e.g. `nix-update --flake git-now`).
          packages = {
            inherit (localPkgs)
              git-now
              git-wtpr
              ;
          };

          # DevShell with pre-commit hooks
          devShells.default = localPkgs.mkShell {
            shellHook = ''
              ${config.pre-commit.installationScript}
            '';
          };
        };

      flake =
        let
          linuxHomeConfigurations = {
            ${username} = mkLinuxHomeConfig "x86_64-linux";
            "${username}-aarch64" = mkLinuxHomeConfig "aarch64-linux";
          };
        in
        {
          # macOS configuration with nix-darwin
          darwinConfigurations.${username} = nix-darwin.lib.darwinSystem {
            modules = [
              { nixpkgs.hostPlatform = "aarch64-darwin"; }

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
                        agent-skills.homeManagerModules.default

                        (import ./nix/modules/home {
                          inherit
                            pkgs
                            config
                            lib
                            fish-na
                            helpers
                            ast-grep-skill
                            agent-browser-skill
                            tgrab-skill
                            local-skills
                            ;
                          dotfilesDir = "${darwinHomedir}/ghq/github.com/11gather11/dotfiles";
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
          homeConfigurations = linuxHomeConfigurations;

          # Aliases for tools that can't parse digit-starting attribute segments
          # (e.g. natsukium/nix-diff-action's attribute path validator).
          diffTargets = {
            home-x86_64-linux = linuxHomeConfigurations.${username}.activationPackage;
            home-aarch64-linux = linuxHomeConfigurations."${username}-aarch64".activationPackage;
          };
        };
    };
}
