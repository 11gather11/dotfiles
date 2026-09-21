# A herdr plugin that lists every keybinding — herdr's defaults merged with the
# overrides in config.toml — in an overlay, and runs the ones the herdr CLI can
# reach. What which-key did by chords, this does by search.
#
# The manifest's [[build]] step is `npm ci`, which `herdr plugin link` never
# runs, so the dependencies are fetched here and the finished tree is linked.
# The entrypoint is `node src/keymap.ts`: Node runs the TypeScript directly, so
# nothing is compiled and the install is the source plus node_modules.
#
# Pinned to technicalpickles' fork rather than The-Dave-Stack's original: the
# fork replaces the two-level category menu with one fuzzy-searchable list and
# sizes it to the pane. It is offered upstream as PR #1 and has sat there since
# August; when it lands, this moves back to the original's tags.
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
}:

buildNpmPackage {
  pname = "herdr-keymap";
  version = "0-unstable-2026-08-02";

  src = fetchFromGitHub {
    owner = "technicalpickles";
    repo = "herdr-keymap";
    rev = "39b75935f562885eed669e84fb0a5117b658c421";
    hash = "sha256-oPl/J90NVfVR/Bjz2OjKmqommzH2UxZDiIFlw8CAECo=";
  };

  npmDepsHash = "sha256-VWNFxsPAgs6TAqJkOS7PJjFYIZkil/kqkwCi0TSeMD4=";

  # package.json declares no build script, and there is nothing to compile.
  dontNpmBuild = true;

  # npm's own install would place a package; what herdr links is a plugin root,
  # so the tree is copied whole — the manifest at the top, the sources it names
  # beside it, and the dependencies they import.
  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -R herdr-plugin.toml open_palette.sh src node_modules $out/
    runHook postInstall
  '';

  meta = {
    description = "Searchable overlay of every herdr keybinding";
    homepage = "https://github.com/The-Dave-Stack/herdr-keymap";
    platforms = lib.platforms.unix;
    inherit (nodejs.meta) maintainers;
  };
}
