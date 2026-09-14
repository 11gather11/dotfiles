# docs
# ~/.grok/docs/user-guide/ (shipped with grok)
{
  pkgs,
  lib,
  config,
  ...
}:
let
  tomlFormat = pkgs.formats.toml { };

  grokConfig = "${config.home.homeDirectory}/.grok/config.toml";

  # Only the keys this file owns. Everything else in config.toml is left as grok
  # wrote it.
  settings = {
    ui = {
      # Paints no backgrounds, so Ghostty's translucency shows through the way
      # it does behind a shell; colours come from the terminal's own palette.
      theme = "terminal";
    };

    # The terminal theme is still rolling out per account. Until it reaches
    # this one, theme = "terminal" does not parse and silently falls back to
    # the default theme; this reveals it ahead of the rollout.
    features.terminal_theme = true;
  };

  # config.toml cannot be generated whole the way herdr's is: grok writes its
  # own state into the same file — the privacy banner acknowledgement, whether
  # the official marketplace was already installed — and overwriting it would
  # replay those first-run steps on every switch. Nor is there another file to
  # put these in: a project .grok/config.toml supplies only MCP servers,
  # plugins and permission rules, and everything else is read from this one.
  #
  # So the owned keys are deep-merged in, and a key grok has changed since —
  # say, through /theme — is set back at the next switch.
  mergeGrokConfig = pkgs.writers.writeNu "merge-grok-config" ''
    def main [target: path, owned: path] {
      let current = if ($target | path exists) {
        open --raw $target | from toml
      } else {
        {}
      }
      mkdir ($target | path dirname)
      $current | merge deep (open --raw $owned | from toml) | to toml | save --force $target
    }
  '';
in
{
  home.packages = [ pkgs.llm-agents.grok ];

  # A config.toml that no longer parses fails the activation rather than being
  # replaced, since replacing it is exactly what the merge exists to avoid.
  home.activation.writeGrokConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${mergeGrokConfig} ${lib.escapeShellArg grokConfig} ${tomlFormat.generate "grok-config.toml" settings}
  '';
}
