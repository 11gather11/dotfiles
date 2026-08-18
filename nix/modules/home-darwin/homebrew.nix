{
  # Opt out of Homebrew's telemetry.
  #
  # This lived in bash/.bashrc as `export HOMEBREW_NO_ANALYTICS=1` until it was
  # deleted along with that file's pre-Nix sediment. It was not sediment — but
  # it was also never doing its job: bash and zsh had it, fish did not, and brew
  # is run from fish. `brew analytics state` reported analytics enabled.
  #
  # home.sessionVariables reaches all three shells through hm-session-vars.sh,
  # which each of them sources, so the opt-out now covers the shell the command
  # is actually run from.
  home.sessionVariables.HOMEBREW_NO_ANALYTICS = "1";
}
