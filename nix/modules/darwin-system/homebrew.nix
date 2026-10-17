{
  # Homebrew configuration
  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";

    # Vendors' own taps, for apps that are not in homebrew-core. Homebrew 6+
    # loads nothing from them until it is trusted, so each package taken from
    # one below is marked trusted rather than the whole tap.
    taps = [
      "arto-app/tap"
      "kamillobinski/thock"
      "kot149/tap"
      "rjyo/moshi"
      "typewhisper/tap"
    ];

    brews = [
      # Moshi's host daemon: it installs the Claude Code hooks that push
      # notifications to the phone. Paired by hand, so its service is started
      # by hand too rather than on every activation.
      {
        name = "rjyo/moshi/moshi-hook";
        trusted = true;
      }
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
      {
        name = "arto-app/tap/arto";
        trusted = true;
      }
      "autodesk-fusion"
      "bambu-studio"
      "chatgpt"
      "claude"
      "codexbar"
      "discord"
      "ghostty"
      "google-chrome"
      "karabiner-elements"
      "microsoft-teams"
      "raycast"
      "shottr"
      "slack"
      "stats"
      "steam"
      "tailscale-app"
      # Typing sounds; taken over Klack for its importable sound packs.
      {
        name = "kamillobinski/thock/thock";
        trusted = true;
      }
      {
        name = "typewhisper/tap/typewhisper";
        trusted = true;
      }
      "visual-studio-code"
      "vlc"
      # macOS shows only one battery per BLE keyboard, so the Ergonaut One's
      # two halves are read by this menu bar app.
      {
        name = "kot149/tap/zmk-battery-center";
        trusted = true;
      }
    ];
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
