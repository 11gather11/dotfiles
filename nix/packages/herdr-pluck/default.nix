# A herdr plugin that overlays one- and two-letter hints on the tokens visible
# in a pane, so a hash, path or URL is copied by typing its hint rather than by
# selecting it with the mouse. tmux-fingers, for panes herdr owns.
#
# Like herdr-hunk-diff, this is not just a source tree: the manifest's [[build]]
# step downloads a release binary, and `herdr plugin link` does not run build
# steps at all. So the binary is built here and the finished layout is what gets
# linked — the manifest at the plugin root, the binary under bin/, which is the
# path the manifest's actions name.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "herdr-pluck";
  version = "0.3.1";

  # Upstream, not Mic92's osc52 fork: that fork exists because wl-copy on
  # Wayland dies together with the picker pane before the clipboard is read.
  # Here the clipboard is pbcopy, which does not have that problem, and
  # upstream's tag is newer than the fork's commit.
  src = fetchFromGitHub {
    owner = "rmarganti";
    repo = "herdr-pluck";
    tag = "v${finalAttrs.version}";
    hash = "sha256-QFHjKbNPuK4pNd9T1S6IlHyFfXBRik93js+1mlXZDT4=";
  };

  cargoHash = "sha256-p6KhaqawJOSwt/JfZGSKXSxa2eU570wkXEAd3j1o92Y=";

  postInstall = ''
    cp herdr-plugin.toml $out/
  '';

  meta = {
    description = "Keyboard hints for copying visible tokens out of herdr panes";
    homepage = "https://github.com/rmarganti/herdr-pluck";
    mainProgram = "herdr-pluck";
    platforms = lib.platforms.unix;
  };
})
