# A herdr plugin, packaged as a directory herdr can link rather than install.
#
# Its manifest's [[build]] step is `bun install --production --frozen-lockfile`,
# which would write node_modules into the plugin root at activation time. The
# store is read-only and that fetch is unpinned, so the dependencies are built
# here instead, as a fixed-output derivation — the one place Nix allows network
# access, in exchange for pinning the result by hash.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  bun,
  cacert,
}:
let
  version = "0.1.1";

  src = fetchFromGitHub {
    owner = "iurysza";
    repo = "herdr-tab-smart-rename";
    tag = "v${version}";
    hash = "sha256-b/Cvxv2T/OvAzucPoPqDT058Kpv83heKtPNDu/SvqWc=";
  };

  node_modules = stdenvNoCC.mkDerivation {
    pname = "herdr-tab-smart-rename-node_modules";
    inherit version src;

    nativeBuildInputs = [
      bun
      cacert
    ];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      export HOME=$TMPDIR
      bun install --production --frozen-lockfile --no-progress
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r node_modules/. $out/
      runHook postInstall
    '';

    # The lockfile is frozen, so the resolved tree is fixed; the hash pins what
    # the network is allowed to produce.
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-D2baep7WREvqVRycRFNsh+XzbJE8cZBZkq2b/UM+ssU=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "herdr-tab-smart-rename";
  inherit version src;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r . $out/
    cp -r ${node_modules} $out/node_modules

    # The plugin exposes `start` only as an action, so the worker has to be
    # launched by hand after every reboot — it detaches and survives herdr
    # itself, but not the machine. A [[startup]] entry hands that to herdr,
    # which runs it whenever the server comes up; `start` is already
    # idempotent, reporting "already running" off its pid file, so the extra
    # invocations from a server restart cost nothing.
    cat >> $out/herdr-plugin.toml <<'MANIFEST'

    [[startup]]
    command = ["sh", "src/run-bun.sh", "src/cli.ts", "start"]
    MANIFEST

    runHook postInstall
  '';

  meta = {
    description = "Context-aware workspace and tab names for herdr";
    homepage = "https://github.com/iurysza/herdr-tab-smart-rename";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
