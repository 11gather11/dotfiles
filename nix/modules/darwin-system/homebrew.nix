{
  # Homebrew configuration
  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";

    # Vendors' own taps, for apps that are not in homebrew-core
    taps = [
      "stablyai/orca"
      "typewhisper/tap"
    ];

    casks = [
      "1password"
      "alt-tab"
      "appcleaner"
      "autodesk-fusion"
      "bambu-studio"
      "bruno"
      "chatgpt"
      "claude"
      "codexbar"
      "discord"
      "ghostty"
      "google-chrome"
      "hhkb"
      "karabiner-elements"
      "microsoft-teams"
      "raycast"
      "shottr"
      "slack"
      "stablyai/orca/orca"
      "stats"
      "steam"
      "tailscale-app"
      "typewhisper/tap/typewhisper"
      "visual-studio-code"
      "vlc"
    ];

    masApps = {
      "Klack" = 6446206067;
    };
  };
}
