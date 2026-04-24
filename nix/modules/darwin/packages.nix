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
      discord
      mos
      raycast
      shottr
      stats
      vscode
    ]
    # brew-nix packages (Homebrew casks managed via Nix)
    ++ (with pkgs.brewCasks; [
      slack
    ]);
  # brew-nix packages requiring hash override
}
