# A herdr plugin that opens hunk on an agent's changes and sends the comments
# written there back to the agent that made them.
#
# Unlike the other plugins registered here, this one is not just a source tree:
# its manifest's [[build]] step is `npm ci` then `tsc`, and herdr would run both
# at link time against a directory in the Nix store, which is read-only. So the
# build happens here instead, pinned, and what is linked is the finished layout
# the manifest expects — dist/ beside the manifest, with node_modules reachable
# from it.
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  runCommand,
  jq,
}:
let
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "jhochenbaum";
    repo = "herdr-hunk-diff";
    tag = "v${version}";
    hash = "sha256-b+Hh4bKt/aGprYGKrL3RjrRRNX5ws1xDapil+zAmkKA=";
  };

  # Upstream's package-lock.json records 25 packages — zod, bun and chokidar
  # among them — with a version and nothing else: no tarball URL, no integrity.
  # npm fills those in from the registry, so `npm ci` works for anyone with a
  # network and cannot work here, where the point is that there is none.
  # lockfile-additions.json holds what the registry answered for exactly those
  # versions, fetched once and pinned like everything else.
  #
  # The lockfile is repaired here rather than in postPatch because the
  # derivation that fetches the dependencies reads the same source and does not
  # inherit nativeBuildInputs, so jq is not on its PATH.
  #
  # To regenerate after a version bump: for every entry in the lockfile with no
  # `resolved`, ask https://registry.npmjs.org/<name>/<version> and keep
  # .dist.tarball and .dist.integrity. A nested entry is named by the segment
  # after its last node_modules/, not its first.
  patched = runCommand "herdr-hunk-diff-${version}-source" { nativeBuildInputs = [ jq ]; } ''
    cp -r ${src} "$out"
    chmod -R u+w "$out"
    jq --slurpfile add ${./lockfile-additions.json} \
      '.packages |= with_entries(.value += ($add[0][.key] // {}))' \
      "$out/package-lock.json" > lock.patched
    mv lock.patched "$out/package-lock.json"
  '';
in
buildNpmPackage {
  pname = "herdr-hunk-diff";
  inherit version;
  src = patched;

  npmDepsHash = "sha256-sIpydwQQ3F1RB2uCEbVxnvcklCVyn8zNYxvO9HI+GLQ=";

  # The plugin is a directory herdr reads, not a program on PATH, so the usual
  # install of bin/ and lib/node_modules is replaced by the layout above.
  # Pruning first drops typescript and eslint, which only the build needed.
  installPhase = ''
    runHook preInstall
    npm prune --omit=dev
    # typescript is one of the entries the lockfile lost its `dev` marker on,
    # so prune keeps a 23 MB compiler that only the build ever ran. Its two
    # links in .bin go with it, or the output ships symlinks to nothing.
    rm -rf node_modules/typescript node_modules/.bin/tsc node_modules/.bin/tsserver
    mkdir -p "$out"
    cp -r herdr-plugin.toml dist node_modules skills "$out/"
    runHook postInstall
  '';

  dontNpmInstall = true;

  meta = {
    description = "Review agent-authored diffs in hunk from herdr";
    homepage = "https://github.com/jhochenbaum/herdr-hunk-diff";
    license = lib.licenses.mit;
  };
}
