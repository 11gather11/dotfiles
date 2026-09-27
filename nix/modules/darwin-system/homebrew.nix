{
  # Homebrew configuration
  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";

    # Vendors' own taps, for apps that are not in homebrew-core
    taps = [
      "arto-app/tap"
      "rjyo/moshi"
      "typewhisper/tap"
    ];

    brews = [
      # Moshi's host daemon: it installs the Claude Code hooks that push
      # notifications to the phone. Paired by hand, so its service is started
      # by hand too rather than on every activation.
      "rjyo/moshi/moshi-hook"
      # zmk-layer-hud's Python wheel links against Homebrew's hidapi, and its
      # own setup installs it imperatively; declared so cleanup keeps it.
      "hidapi"
    ];

    casks = [
      "1password"
      "alt-tab"
      "appcleaner"
      # A Markdown reader: GitHub's rendering, offline, following the file as
      # it changes — for what agents write, read beside them as they write it.
      "arto-app/tap/arto"
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

  # Arto is neither signed nor notarized, so Gatekeeper refuses to open it
  # while the download's quarantine flag is on, and its cask says to clear
  # the flag by hand. Every upgrade brings a fresh one, so it is cleared on
  # each activation, which runs after the brew bundle that installs it.
  system.activationScripts.postActivation.text = ''
    if xattr -p com.apple.quarantine /Applications/Arto.app >/dev/null 2>&1; then
      echo "Clearing quarantine from Arto.app..."
      xattr -dr com.apple.quarantine /Applications/Arto.app || true
    fi
  '';
}
