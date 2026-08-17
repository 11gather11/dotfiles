# A herdr plugin, packaged as a directory herdr can link rather than install.
#
# `herdr plugin install` clones the repository and runs the manifest's [[build]]
# step — here `herdr/install.sh`, which downloads the release binary matching the
# running platform into the plugin's bin/. That cannot write into the Nix store,
# and it would fetch an unpinned artifact at activation time besides. So both
# halves are fetched here, pinned, and assembled into the layout the manifest
# expects: [[panes]] runs "$HERDR_PLUGIN_ROOT/bin/herdr-reviewr".
#
# The binary is the project's own release archive, and the hash below is the one
# published beside it — the same artifact and the same check install.sh performs.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  fetchurl,
  stdenv,
}:
let
  version = "0.32.0";

  # Only the hosts this configuration runs on are listed, so an unsupported
  # platform fails at eval rather than linking a plugin whose pane command is
  # missing.
  targets = {
    aarch64-darwin = {
      triple = "aarch64-apple-darwin";
      hash = "sha256-RHsNXc/rkgWxRW43CIJ92qM8evWAT3ooLv4agJ3H0sI=";
    };
  };

  target =
    targets.${stdenv.hostPlatform.system}
      or (throw "herdr-reviewr: no release asset for ${stdenv.hostPlatform.system}");

  src = fetchFromGitHub {
    owner = "persiyanov";
    repo = "herdr-reviewr";
    tag = "v${version}";
    hash = "sha256-JzJ8CA2MTOnu1DnfKoDDM2DFhODDAmSTPsYke4QI/+s=";
  };

  bin = fetchurl {
    url = "https://github.com/persiyanov/herdr-reviewr/releases/download/v${version}/herdr-reviewr-${target.triple}.tar.gz";
    inherit (target) hash;
  };
in
stdenvNoCC.mkDerivation {
  pname = "herdr-reviewr";
  inherit version src;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp -r . $out/
    tar -xzf ${bin} -C $out/bin
    chmod 755 $out/bin/herdr-reviewr

    runHook postInstall
  '';

  meta = {
    description = "Code-review pane for herdr: comment on an agent's diff and send it back";
    homepage = "https://github.com/persiyanov/herdr-reviewr";
    license = lib.licenses.mit;
    platforms = builtins.attrNames targets;
  };
}
