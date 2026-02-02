{
  pkgs,
  ...
}:
{
  home.packages =
    with pkgs;
    [
      # macOS-specific packages
      mas

      # macOS GUI applications (not available on Linux in nixpkgs)
      google-chrome
    ]
    # brew-nix packages (Homebrew casks managed via Nix)
    # Note: imageoptim and hhkb excluded due to extraction issues with brew-nix
    ++ (with pkgs.brewCasks; [
      stats
    ]);
  # brew-nix packages requiring hash override
}
