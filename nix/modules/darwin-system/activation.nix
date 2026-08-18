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

    # Set user shell on activation
    activationScripts.postActivation.text = ''
      echo "Setting login shell to fish..."
      sudo chsh -s ${fishPath} ${username} || true
    '';

    # macOS system defaults
  };
}
