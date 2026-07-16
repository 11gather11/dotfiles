{
  pkgs,
  username,
  homedir,
  ...
}:
let
  fishPath = "${pkgs.fish}/bin/fish";
in
{
  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # Disable nix-darwin's Nix management (using Determinate Nix)
  # Note: Nix settings are managed via /etc/nix/nix.custom.conf instead
  # This file should be manually configured with trusted-users and substituters
  nix.enable = false;

  # Define the sudo PAM stack explicitly so the authentication order is
  # controlled (nix-darwin's typed options fix the order and let Touch ID win
  # before Apple Watch is ever offered).
  #   1. pam-reattach: reattach to the user's GUI session so Touch ID / Apple
  #      Watch work inside tmux/screen.
  #   2. pam_tid.so: Touch ID first, so an open MacBook authenticates by finger.
  #   3. pam-watchid: Apple Watch as the fallback when Touch ID is unavailable.
  security.pam.services.sudo_local.text = ''
    auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so
    auth       sufficient     pam_tid.so
    auth       sufficient     ${pkgs.pam-watchid}/lib/pam_watchid.so
  '';

  system = {
    # Set system state version
    stateVersion = 5;

    # Set primary user for homebrew
    primaryUser = username;

    # Set user shell on activation
    activationScripts.postActivation.text = ''
      echo "Setting login shell to fish..."
      sudo chsh -s ${fishPath} ${username} || true
    '';

    # macOS system defaults
    defaults = {
      # Dock settings
      dock = {
        autohide = true; # Automatically hide and show the Dock
        launchanim = true; # Animate opening applications
        magnification = false; # Disable Dock icon magnification on hover
        tilesize = 45; # Icon size
        persistent-apps = [ ]; # Remove all pinned applications
        show-recents = false; # Don't show recent applications
        show-process-indicators = true; # Show indicator dots under running apps
        mineffect = "genie";
        orientation = "bottom"; # Dock position

        # Trackpad gestures handled by the Dock / Mission Control
        showAppExposeGestureEnabled = true; # App Exposé gesture (swipe down)
        showDesktopGestureEnabled = true; # Show Desktop (spread thumb + 3 fingers)
        showMissionControlGestureEnabled = true; # Mission Control (swipe up)

        # Disable the bottom-right hot corner (default: Quick Note).
        # Prevents Quick Note from popping up when the cursor reaches the
        # corner. 1 = no-op; other corners are left untouched.
        wvous-br-corner = 1;
      };

      # Finder settings
      finder = {
        AppleShowAllExtensions = true; # Show all file extensions
        AppleShowAllFiles = true; # Show hidden files
        ShowPathbar = true; # Show path bar
        ShowStatusBar = true; # Show status bar
        FXEnableExtensionChangeWarning = false; # Disable extension change warning
        FXPreferredViewStyle = "Nlsv"; # List view by default
      };

      # Global macOS settings
      NSGlobalDomain = {
        # Appearance
        AppleInterfaceStyle = "Dark"; # Dark mode
        AppleShowAllExtensions = true; # Show all file extensions

        # Keyboard
        KeyRepeat = 2; # Fast key repeat (1-2 is very fast)
        InitialKeyRepeat = 25; # Initial key repeat delay

        # Trackpad gestures & behaviour
        AppleEnableSwipeNavigateWithScrolls = true; # Two-finger swipe to navigate pages (back/forward)
        "com.apple.swipescrolldirection" = true; # Natural scroll direction
        "com.apple.trackpad.forceClick" = true; # Force Click enabled

        # Trackpad speed (0.0 = slowest, 3.0 = fastest)
        "com.apple.trackpad.scaling" = 1.3;

        # Disable auto-correct and substitutions
        NSAutomaticCapitalizationEnabled = false;
        NSAutomaticDashSubstitutionEnabled = false;
        NSAutomaticPeriodSubstitutionEnabled = false;
        NSAutomaticQuoteSubstitutionEnabled = false;
        NSAutomaticSpellingCorrectionEnabled = false;

        # Menu bar spacing (replaces Menu Bar Spacing app)
        NSStatusItemSpacing = 2; # Space between menu bar items
        NSStatusItemSelectionPadding = 2; # Padding for selected items
      };

      # Screenshot settings
      screencapture = {
        location = "~/Pictures/Screenshots";
        type = "png";
      };

      # Trackpad settings (typed options apply to both built-in and Bluetooth trackpads)
      trackpad = {
        Clicking = false; # Tap to click disabled

        # Click pressure & haptics
        ActuationStrength = 1; # 0 = silent clicking, 1 = default click feel
        ActuateDetents = true; # Haptic feedback enabled
        FirstClickThreshold = 0; # Click threshold: 0 = light, 1 = medium, 2 = firm
        SecondClickThreshold = 0; # Force Click threshold (0 = light)
        ForceSuppressed = false; # Force Click enabled

        # Two-finger gestures
        TrackpadRightClick = true; # Two-finger secondary click
        TrackpadPinch = true; # Pinch to zoom
        TrackpadRotate = true; # Two-finger rotate
        TrackpadTwoFingerDoubleTapGesture = true; # Smart zoom
        TrackpadTwoFingerFromRightEdgeSwipeGesture = 3; # Swipe from right edge = Notification Center

        # Three-finger gestures
        TrackpadThreeFingerDrag = false; # Disable three-finger drag
        TrackpadThreeFingerTapGesture = 0; # Disable three-finger tap (Look up)
        TrackpadThreeFingerHorizSwipeGesture = 2; # Swipe between full-screen apps
        TrackpadThreeFingerVertSwipeGesture = 2; # Mission Control / App Exposé

        # Four-finger gestures
        TrackpadFourFingerHorizSwipeGesture = 2; # Swipe between full-screen apps
        TrackpadFourFingerVertSwipeGesture = 2; # Mission Control
        TrackpadFourFingerPinchGesture = 2; # Launchpad (pinch thumb + 3 fingers)
      };

      # Custom preferences for settings not exposed as typed system.defaults options
      CustomUserPreferences = {
        # Keep the desktop free of system-managed window overlays.
        "com.apple.WindowManager" = {
          GloballyEnabled = false; # Disable Stage Manager
          EnableStandardClickToShowDesktop = false; # Clicking the wallpaper does not hide windows (Stage Manager only)
          EnableTilingByEdge = false; # No window tiling when dragging to a screen edge
          EnableTopTilingByEdge = false; # No tiling when dragging to the top edge
          EnableTilingOptionAccelerator = false; # No tiling menu accelerator
          EnableTiledWindowMargins = false; # No margins between tiled windows
          StandardHideDesktopIcons = true; # Hide desktop icons
          StandardHideWidgets = true; # Hide desktop widgets
          StageManagerHideDesktopIcons = true; # Hide desktop icons in Stage Manager
          StageManagerHideWidgets = true; # Hide widgets in Stage Manager
        };
      };
    };
  };

  # Define user
  users.users.${username} = {
    home = homedir;
    shell = pkgs.fish;
    ignoreShellProgramCheck = true;
  };

  # Add fish to system shells
  environment.shells = [ pkgs.fish ];

  programs = {
    # 1Password CLI (GUI is managed via Homebrew cask - requires /Applications)
    _1password.enable = true;

    # nix-index for command-not-found and comma
    nix-index.enable = true;
    nix-index-database.comma.enable = true;
  };

  # Font configuration
  fonts = {
    packages = with pkgs; [
      plemoljp-nf
    ];
  };

  # Homebrew configuration
  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";

    casks = [
      "1password"
      "alt-tab"
      "appcleaner"
      "autodesk-fusion"
      "bambu-studio"
      "bruno"
      "chatgpt"
      "claude"
      "cmux"
      "discord"
      "google-chrome"
      "hhkb"
      "karabiner-elements"
      "microsoft-teams"
      "orbstack"
      "raycast"
      "shottr"
      "slack"
      "stats"
      "steam"
      "tailscale-app"
      "visual-studio-code"
      "vlc"
    ];

    masApps = {
      "Klack" = 6446206067;
    };
  };
}
