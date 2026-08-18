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
  mkSystem = import ../lib/mk-system.nix {
    inherit
      inputs
      username
      mkPkgs
      homeSpecialArgs
      ;
  };

  mkLinuxHomeConfig =
    system:
    mkSystem {
      inherit system;
      homedir = linuxHomedir;
      homeModules = [ (inputs.import-tree ../modules/home-linux) ];
    };

  linuxHomeConfigurations = {
    ${username} = mkLinuxHomeConfig "x86_64-linux";
    "${username}-aarch64" = mkLinuxHomeConfig "aarch64-linux";
  };
in
{
  flake = {
    # macOS configuration with nix-darwin
    darwinConfigurations.${username} = mkSystem {
      system = "aarch64-darwin";
      homedir = darwinHomedir;
      darwin = true;
      homeModules = [ (inputs.import-tree ../modules/home-darwin) ];
      systemModules = [ (inputs.import-tree ../modules/darwin-system) ];
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
}
