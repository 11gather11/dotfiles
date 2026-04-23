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
    ]
    # brew-nix packages (Homebrew casks managed via Nix)
    ++ (with pkgs.brewCasks; [
      discord
      mos
      shottr
      slack
      stats
    ]);
  # brew-nix packages requiring hash override
}
