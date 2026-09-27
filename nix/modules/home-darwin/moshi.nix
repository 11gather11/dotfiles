{ config, lib, ... }:
let
  # Installed by the Homebrew tap in darwin-system/homebrew.nix; nixpkgs does
  # not package it.
  moshiHook = "/opt/homebrew/bin/moshi-hook";
in
{
  # moshi-hook adds its hooks to Claude Code's settings.json, where this
  # configuration declares PreToolUse, PostToolUse and SessionStart too. The
  # merge replaces declared lists whole, so every switch that rewrote the
  # settings dropped Moshi's entries from those three events. Installing again
  # afterwards puts them back; it is idempotent and leaves other hooks alone.
  # Codex's hooks.json is not generated here, but herdr's integration rewrites
  # it after a change and puts its own hook first, which moshi-hook doctor
  # reports as out of date, so Codex is reinstalled here too. grok's hooks
  # directory is Moshi's alone, so installing it once by hand is enough.
  home.activation.installMoshiHooks =
    lib.hm.dag.entryAfter
      [
        "writeClaudeSettings"
        "installHerdrIntegrations"
      ]
      ''
        # brew bundle may not have installed it yet on a fresh machine.
        if [ -x ${moshiHook} ]; then
          # Activation does not run with the session's environment, and without
          # these the hooks would go to ~/.claude and ~/.codex, which nothing
          # here reads.
          export CLAUDE_CONFIG_DIR=${lib.escapeShellArg config.home.sessionVariables.CLAUDE_CONFIG_DIR}
          export CODEX_HOME=${lib.escapeShellArg config.home.sessionVariables.CODEX_HOME}
          if ! out="$($DRY_RUN_CMD ${moshiHook} install --target claude,codex 2>&1)"; then
            echo "moshi-hook: install --target claude,codex failed:" >&2
            echo "$out" >&2
            exit 1
          fi
        fi
      '';
}
