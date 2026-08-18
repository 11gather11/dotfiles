{
  # Homebrew configuration
  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";

    # TypeWhisper ships through the vendor's own tap, not homebrew-core
    taps = [
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
