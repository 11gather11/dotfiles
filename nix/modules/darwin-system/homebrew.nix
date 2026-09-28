{
  # Homebrew configuration
  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";

    # Vendors' own taps, for apps that are not in homebrew-core
    taps = [
      "arto-app/tap"
      "kot149/tap"
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
      # macOS shows only one battery per BLE keyboard, so the Ergonaut One's
      # two halves are read by this menu bar app. Homebrew 6+ refuses casks
      # from untrusted taps.
      {
        name = "kot149/tap/zmk-battery-center";
        trusted = true;
      }
    ];

    masApps = {
      "Klack" = 6446206067;
    };
  };

  # Arto and zmk-battery-center are neither signed nor notarized, so
  # Gatekeeper refuses to open them while the download's quarantine flag is
  # on, and their casks say to clear the flag by hand. Every upgrade brings a
  # fresh one, so it is cleared on each activation, which runs after the brew
  # bundle that installs them.
  system.activationScripts.postActivation.text = ''
    for app in /Applications/Arto.app /Applications/zmk-battery-center.app; do
      if xattr -p com.apple.quarantine "$app" >/dev/null 2>&1; then
        echo "Clearing quarantine from $app..."
        xattr -dr com.apple.quarantine "$app" || true
      fi
    done
  '';
}
