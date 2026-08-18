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
      homeModules = [ ../modules/linux ];
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
      homeModules = [ ../modules/darwin ];
      systemModules = [ ../modules/darwin/system.nix ];
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
