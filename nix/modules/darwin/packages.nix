{
  pkgs,
  ...
}:
{
  home.packages =
    with pkgs;
    [
      # macOS-specific packages
      terminal-notifier
      mas

      # macOS GUI applications (not available on Linux in nixpkgs)
      google-chrome
    ]
    # brew-nix packages (Homebrew casks managed via Nix)
    ++ (with pkgs.brewCasks; [
      shottr
    ]);
  # brew-nix packages requiring hash override
}
