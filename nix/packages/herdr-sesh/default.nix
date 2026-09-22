# A herdr plugin that opens workspaces from one searchable list: the ones
# already open, the ones declared as sessions, and zoxide's history. Picking a
# directory that has no workspace yet creates it, with the startup command and
# tabs the session names — which is what `z` does for a shell, moved up to the
# workspace level. Worktrees show nested under the repository they came from,
# so the checkouts `wt` makes are visible beside their parent.
#
# Another plugin whose manifest carries a [[build]] step — `go build -o bin/` —
# that `herdr plugin link` never runs, so the binary is built here and the
# finished layout is linked.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  git,
}:

buildGoModule (finalAttrs: {
  pname = "herdr-sesh";
  version = "0.12.0";

  src = fetchFromGitHub {
    owner = "fullerzz";
    repo = "herdr-plugin-sesh";
    tag = "v${finalAttrs.version}";
    hash = "sha256-wbPKkEnh8Eiw3ZiRsVTmxL7OYVvudM4QolNVYEfTi28=";
  };

  vendorHash = "sha256-AY23TzglTD7SL0bqBcB1Ov4EZC6EgBcJZjGGCoha9cA=";

  # The version upstream's build step stamps in, kept so `herdr-sesh --version`
  # answers the same thing the tag says.
  ldflags = [
    "-X=github.com/fullerzz/herdr-plugin-sesh/internal/app.Version=${finalAttrs.version}"
  ];

  # Two of upstream's tests cannot pass as this is built. TestVersionCommand
  # asserts the version is the unset default, which the ldflags above have just
  # replaced — upstream tests a build without them and ships one with them,
  # while here both happen at once. And the preview test puts a fake `bat` in a
  # temp directory, sets PATH to only that, and runs the preview under each
  # shell present; under zsh macOS's /etc/zshenv runs path_helper, which
  # rebuilds PATH and drops the directory the test just prepared.
  checkFlags = [
    "-skip=TestVersionCommand|TestFZFPreviewCommandFindsSystemToolsWithMinimalPath|TestRenderBatUsesBatForReadmePreview"
  ];

  # The namer tests build a repository with `git init` to read a remote off it,
  # which is also how the plugin names a workspace at runtime.
  nativeCheckInputs = [ git ];

  # Every command in the manifest is `./bin/herdr-sesh`, resolved against the
  # plugin root, so the binary has to sit at that path next to the manifest.
  postInstall = ''
    cp herdr-plugin.toml $out/
    mkdir -p $out/bin
  '';

  meta = {
    description = "Workspace picker for herdr over open workspaces, sessions and zoxide history";
    homepage = "https://github.com/fullerzz/herdr-plugin-sesh";
    mainProgram = "herdr-sesh";
    platforms = lib.platforms.unix;
  };
})
