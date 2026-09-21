# Tab and pane names that follow the work: the directory, the branch cut down
# to what identifies it, and — for a pane running Claude Code — what the agent
# is currently doing, read from its transcript.
#
# This replaced qu8n/herdr-automatic-rename, whose naming had to be switched
# off here. That plugin names a tab after its foreground process, which assumes
# one tab is one job; several agents share a tab here, so the name followed
# whichever pane had focus. This one names every pane separately and picks the
# tab's name from the focused, busy, or last-changed pane among them — and the
# per-pane names are also what stops herdr's goto panel listing every agent
# pane as `claude`.
#
# Another [[build]] step herdr never runs on a linked plugin, so the binary is
# built here. The manifest's commands are `./herdr-auto-title`, at the plugin
# root rather than under bin/.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule (finalAttrs: {
  pname = "herdr-auto-title";
  version = "0.8.0";

  src = fetchFromGitHub {
    owner = "kryptamine";
    repo = "herdr-auto-title";
    tag = "v${finalAttrs.version}";
    hash = "sha256-+p041KLUdD9Qjb5MCZQ42s9BDULF4qQnMw8ljqm4exY=";
  };

  vendorHash = "sha256-QxFp1b7pf7bn3Hh0hyaj8ke5Z61N+WwjhHt3pFiapTs=";

  postInstall = ''
    cp herdr-plugin.toml $out/
    ln -s $out/bin/herdr-auto-title $out/herdr-auto-title
  '';

  meta = {
    description = "herdr tab and pane names that follow the work in them";
    homepage = "https://github.com/kryptamine/herdr-auto-title";
    mainProgram = "herdr-auto-title";
    platforms = lib.platforms.unix;
  };
})
