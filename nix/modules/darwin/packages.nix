{
  pkgs,
  ...
}:
{
  home.packages =
    with pkgs;
    [
      # macOS-specific packages
      kanata
      kanata-vk-agent
      mas

      # macOS GUI applications (not available on Linux in nixpkgs)
      google-chrome
    ]
    # brew-nix packages (Homebrew casks managed via Nix)
    # Note: imageoptim excluded due to tar.xz extraction issues with brew-nix
    ++ (with pkgs.brewCasks; [
      stats
    ]);
  # brew-nix packages requiring hash override
}
