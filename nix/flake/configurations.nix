{
  inputs,
  username,
  darwinHomedir,
  linuxHomedir,
  mkPkgs,
  homeSpecialArgs,
  ...
}:
let
  inherit (inputs)
    nix-darwin
    home-manager
    nix-index-database
    agent-skills
    ;

  # Helper to create Linux home configuration
  mkLinuxHomeConfig =
    linuxSystem:
    home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs linuxSystem;
      extraSpecialArgs = homeSpecialArgs linuxHomedir;
      modules = [
        {
          home.username = username;
          home.homeDirectory = linuxHomedir;
        }
        nix-index-database.homeModules.nix-index
        agent-skills.homeManagerModules.default
        ../modules/home
        ../modules/linux
      ];
    };

  linuxHomeConfigurations = {
    ${username} = mkLinuxHomeConfig "x86_64-linux";
    "${username}-aarch64" = mkLinuxHomeConfig "aarch64-linux";
  };
in
{
  # macOS configuration with nix-darwin
  flake.darwinConfigurations.${username} = nix-darwin.lib.darwinSystem {
    specialArgs = {
      inherit inputs username;
      homedir = darwinHomedir;
    };
    modules = [
      # nixpkgs.pkgs rather than nixpkgs.hostPlatform: the overlays live in
      # mkPkgs, and setting the instantiation here is what lets system.nix be
      # listed as a plain module instead of being called with a hand-built pkgs.
      { nixpkgs.pkgs = mkPkgs "aarch64-darwin"; }

      ../modules/darwin/system.nix

      nix-index-database.darwinModules.nix-index

      home-manager.darwinModules.home-manager
      {
        home-manager = {
          useGlobalPkgs = false;
          useUserPackages = true;
          extraSpecialArgs = homeSpecialArgs darwinHomedir // {
            pkgs = mkPkgs "aarch64-darwin";
          };
          users.${username}.imports = [
            agent-skills.homeManagerModules.default
            ../modules/home
            ../modules/darwin
          ];
        };
      }
    ];
  };

  # Linux configurations with standalone Home Manager
  flake.homeConfigurations = linuxHomeConfigurations;

  # Aliases for tools that can't parse digit-starting attribute segments
  # (e.g. natsukium/nix-diff-action's attribute path validator).
  flake.diffTargets = {
    home-x86_64-linux = linuxHomeConfigurations.${username}.activationPackage;
    home-aarch64-linux = linuxHomeConfigurations."${username}-aarch64".activationPackage;
  };
}
