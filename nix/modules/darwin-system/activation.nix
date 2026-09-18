{ pkgs, username, ... }:
let
  fishPath = pkgs.lib.getExe pkgs.fish;
in
{
  system = {
    # Homebrew's analytics opt-out, for the path the environment variable cannot
    # reach. `brew bundle` runs from this same activation script under
    # `sudo --preserve-env=PATH`, which drops every variable except PATH and the
    # one HOMEBREW_NO_AUTO_UPDATE it re-adds by hand. So the
    # home.sessionVariables entry in home-darwin/homebrew.nix covers brew typed
    # into a shell, but not the invocation that runs on every switch — and the
    # git hooks make that every commit.
    #
    # `brew analytics off` writes homebrew.analyticsdisabled into the Homebrew
    # repository's own git config, which survives having the environment
    # stripped. preActivation rather than postActivation because the homebrew
    # step runs immediately before postActivation: this way the setting is in
    # place before the bundle it needs to affect. Guarded so an ordinary switch
    # does not shell out to brew for a setting that is already there.
    #
    # --set-home for the same reason nix-darwin's own bundle line carries it:
    # activation runs as root, and brew aborts during startup when HOME is
    # root's rather than the user's. Without it this exits 1 into the `|| true`
    # and the opt-out silently never happens.
    activationScripts.preActivation.text = ''
      if [ -x /opt/homebrew/bin/brew ] \
        && [ "$(/usr/bin/git -C /opt/homebrew config --local --get homebrew.analyticsdisabled || true)" != "true" ]; then
        echo "Disabling Homebrew analytics..."
        sudo --user=${username} --set-home /opt/homebrew/bin/brew analytics off || true
      fi
    '';

    # Set the login shell, and release ctrl+space from macOS.
    #
    # ctrl+space is herdr's prefix, and macOS takes it first for "select the
    # previous input source" (symbolic hotkey 60). Nothing is lost by turning
    # that off: Karabiner switches kana and eisuu on a tap of cmd instead.
    #
    # -dict-add rather than CustomUserPreferences. nix-darwin writes a custom
    # preference with `defaults write <domain> <key> <plist>`, which replaces
    # the whole AppleSymbolicHotKeys dictionary — twenty-seven entries today —
    # with the one declared here, resetting every other shortcut changed in
    # System Settings. activateSettings applies it without a logout.
    activationScripts.postActivation.text = ''
      echo "Setting login shell to fish..."
      sudo chsh -s ${fishPath} ${username} || true

      echo "Releasing ctrl+space from input source switching..."
      launchctl asuser "$(id -u -- ${username})" sudo --user=${username} -- \
        defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 60 \
        '<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>262144</integer></array><key>type</key><string>standard</string></dict></dict>' || true
      launchctl asuser "$(id -u -- ${username})" sudo --user=${username} -- \
        /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u || true
    '';

    # macOS system defaults
  };
}
