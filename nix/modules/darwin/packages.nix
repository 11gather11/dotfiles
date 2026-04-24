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

      # GUI apps available natively in nixpkgs
      alt-tab-macos
      appcleaner
      discord
      mos
      raycast
      shottr
      slack
      stats
      vscode
    ]
    # brew-nix packages (Homebrew casks managed via Nix)
    ++ (with pkgs.brewCasks; [
      cmux
    ]);
  # brew-nix packages requiring hash override
}
