# A herdr plugin, packaged as a directory herdr can link rather than install.
#
# `herdr plugin install` clones the repository and runs the manifest's [[build]]
# step, which fetches or compiles a binary into the plugin root. That cannot work
# from the Nix store, which is read-only, and it would pull an unpinned artifact
# at activation time besides. So the two halves are fetched separately here, both
# pinned, and assembled into the layout the manifest expects: the [[panes]] entry
# runs `./target/release/herdr-file-viewer` relative to the plugin root.
#
# The binary is the project's own release artifact, and the hash below is the one
# published in its SHA256SUMS — the same value the build script would verify.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  stdenv,
}:
let
  version = "1.16.0";

  # Release assets are named per target; only the hosts this configuration runs
  # on are listed, so an unsupported platform fails at eval with a clear message
  # rather than linking a plugin whose pane command is missing.
  targets = {
    aarch64-darwin = {
      asset = "herdr-file-viewer-aarch64-apple-darwin";
      hash = "sha256-yTSYlWdDB9MN0evbkx5QZ2m9TI9hkcUqG6h7sOHsIQo=";
    };
  };

  target =
    targets.${stdenv.hostPlatform.system}
      or (throw "herdr-file-viewer: no release asset for ${stdenv.hostPlatform.system}");

  src = fetchFromGitHub {
    owner = "smarzban";
    repo = "herdr-file-viewer";
    tag = "v${version}";
    hash = "sha256-2vI98QRm6vXDe8IkJBPAqFsQH86zX1oJVwCaoOVYrQs=";
  };

  bin = fetchurl {
    url = "https://github.com/smarzban/herdr-file-viewer/releases/download/v${version}/${target.asset}";
    inherit (target) hash;
  };
in
stdenvNoCC.mkDerivation {
  pname = "herdr-file-viewer";
  inherit version src;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r . $out/
    install -Dm755 ${bin} $out/target/release/herdr-file-viewer

    runHook postInstall
  '';

  meta = {
    description = "Git-aware, read-only file viewer in a herdr pane";
    homepage = "https://github.com/smarzban/herdr-file-viewer";
    license = lib.licenses.mit;
    platforms = builtins.attrNames targets;
  };
}
