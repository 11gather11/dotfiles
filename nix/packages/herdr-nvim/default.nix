# A herdr plugin that keeps Neovim in a full-height sidebar pane, with a file
# picker overlay and a way to send the file under the cursor to an agent.
#
# Like herdr-pluck this is not just a source tree: the manifest names
# `bin/herdr-nvim`, a Rust binary its [[build]] step compiles, and
# `herdr plugin link` runs no build steps. So the binary is built here and the
# finished layout is what gets linked.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  runCommand,
}:

let
  # Kept to the binary alone, so a change to the plugin layout below does not
  # rebuild it: a release build plus its 155 tests is half an hour here.
  bin = rustPlatform.buildRustPackage (finalAttrs: {
    pname = "herdr-nvim";
    version = "1.0.1";

    src = fetchFromGitHub {
      owner = "ChmaraX";
      repo = "herdr-nvim";
      tag = "v${finalAttrs.version}";
      hash = "sha256-KpcNuX0I0N5oFzjsLpZV59SYVzaNO8j1+kDtBG2bK5Y=";
    };

    cargoHash = "sha256-+xv2TYn4Vor7nigV0Cw3xfMTQcm/J0y/1/s3K2auvgw=";

    # The one test that shells out to `git ls-files` over its own checkout, which
    # the sandbox is neither: no git on PATH, and the source is a store path with
    # no .git. The other 155 run.
    checkFlags = [ "--skip=picker::tests::fff_end_to_end_over_this_repo" ];

    # The manifest's commands are relative to the plugin root, so the layout it
    # describes has to exist beside the binary cargo installed.
    postInstall = ''
      cp herdr-plugin.toml $out/
      cp -R doc $out/ 2>/dev/null || true
    '';

    meta = {
      description = "Neovim as a herdr sidebar pane, with a picker and agent handoff";
      homepage = "https://github.com/ChmaraX/herdr-nvim";
      mainProgram = "herdr-nvim";
      platforms = lib.platforms.unix;
    };
  });
in
# The sidebar finds its Lua by walking up from its own executable to a
# directory holding lua/herdr-nvim, and exits at once when there is none. The
# binary is copied rather than linked, because the walk starts from the
# resolved path and would otherwise climb the build output, which has no Lua.
runCommand "herdr-nvim-${bin.version}"
  {
    inherit (bin) version meta;
    passthru = { inherit bin; };
  }
  ''
    mkdir -p $out
    cp -R ${bin}/. $out/
    chmod -R u+w $out
    cp -R ${bin.src}/lua ${bin.src}/plugin $out/
  ''
