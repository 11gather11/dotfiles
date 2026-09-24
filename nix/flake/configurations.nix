{
  inputs,
  username,
  linuxUsername,
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

  # The Linux machine's account is not the one macOS uses: a name starting
  # with a digit is not a valid Linux user, so `11gather11` cannot exist there.
  # home-manager refuses to activate when home.username is not the user
  # running it, which is what made the Linux configurations unusable.
  mkLinuxHomeConfig =
    system:
    mkSystem {
      inherit system;
      user = linuxUsername;
      homedir = linuxHomedir;
      homeModules = [ (inputs.import-tree ../modules/home-linux) ];
    };

  linuxHomeConfigurations = {
    ${linuxUsername} = mkLinuxHomeConfig "x86_64-linux";
    "${linuxUsername}-aarch64" = mkLinuxHomeConfig "aarch64-linux";
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
  };
}
