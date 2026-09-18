{ pkgs, inputs, ... }:
{
  home.packages = [
    # tgrab shipped an agent skill until 2026-08-04, when upstream moved the
    # contract into `tgrab --help` and dropped it. Only the skill was wired in
    # here, so the rule pointing agents at it named a binary that was never
    # installed — the whole path had been dead. Take the executable instead.
    inputs.tgrab.packages.${pkgs.stdenv.hostPlatform.system}.default

    # A browser in a pane, replacing herdr-browser, which upstream deprecated in
    # its favour.
    #
    # The symlink repairs the package. Opening a split makes the app re-invoke
    # itself at $TERMINAL_BROWSER_DIST_ROOT/bin/terminal-browser, and the
    # packaging deletes exactly that file to replace it with a wrapper placed in
    # $out/bin instead. The split then opens on a shell that reports
    # `Unknown command` while the caller waits twenty seconds for a browser that
    # never registers. Pointing the old path at the wrapper satisfies both.
    (pkgs.llm-agents.terminal-browser.overrideAttrs (previous: {
      postInstall = (previous.postInstall or "") + ''
        ln -s $out/bin/terminal-browser $out/lib/terminal-browser/bin/terminal-browser
      '';
    }))
  ];
}
