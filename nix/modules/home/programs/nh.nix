{ dotfilesDir, ... }:
{
  programs.nh = {
    enable = true;

    # Sets NH_FLAKE, so `nh darwin switch` and `nh home switch` act on this
    # configuration from any directory. The apps in nix/flake/apps.nix name the
    # flake explicitly instead, so they keep working before the first switch has
    # put this variable in the environment.
    flake = dotfilesDir;
    clean = {
      enable = true;
      dates = "weekly";
      extraArgs = "--keep-since 30d";
    };
  };
}
