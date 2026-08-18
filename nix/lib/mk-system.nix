# Every configuration this flake produces is built here.
#
# darwin and Linux previously each spelled out their own module list, special
# arguments and nixpkgs instance, so the two could drift apart silently — fixing
# one and forgetting the other is the failure this removes. `darwin` selects
# nix-darwin with home-manager riding inside it; otherwise the result is a
# standalone home-manager configuration.
{
  inputs,
  username,
  mkPkgs,
  homeSpecialArgs,
}:
{
  system,
  homedir,
  darwin ? false,
  # Platform-specific home-manager modules, appended to the common set.
  homeModules ? [ ],
  # nix-darwin system modules. Ignored when darwin is false.
  systemModules ? [ ],
}:
let
  inherit (inputs)
    nix-darwin
    home-manager
    nix-index-database
    agent-skills
    ;

  pkgs = mkPkgs system;

  extraSpecialArgs = homeSpecialArgs homedir;

  commonHomeModules = [
    agent-skills.homeManagerModules.default
    ../modules/home
  ]
  ++ homeModules;
in
if darwin then
  nix-darwin.lib.darwinSystem {
    specialArgs = {
      inherit inputs username homedir;
    };
    modules = [
      # nixpkgs.pkgs rather than nixpkgs.hostPlatform: the overlays live in
      # mkPkgs, and naming the instance here is what lets the modules below be
      # listed plainly instead of being called with a hand-built pkgs.
      { nixpkgs.pkgs = pkgs; }
    ]
    # Before the modules below, not appended after them: nix-darwin concatenates
    # each module's activation fragments in module order, so moving these would
    # reorder the activation script for no reason.
    ++ systemModules
    ++ [
      nix-index-database.darwinModules.nix-index

      home-manager.darwinModules.home-manager
      {
        home-manager = {
          # The system's pkgs is already the overlaid one, so home-manager
          # reuses it rather than instantiating nixpkgs a second time.
          useGlobalPkgs = true;
          useUserPackages = true;
          inherit extraSpecialArgs;
          users.${username}.imports = commonHomeModules;
        };
      }
    ];
  }
else
  home-manager.lib.homeManagerConfiguration {
    inherit pkgs extraSpecialArgs;
    modules = [
      {
        home.username = username;
        home.homeDirectory = homedir;
      }
      nix-index-database.homeModules.nix-index
    ]
    ++ commonHomeModules;
  }
