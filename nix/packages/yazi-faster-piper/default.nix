# piper re-runs its command from the top of the file for every line scrolled,
# which is unnoticeable for `tar tf` and unusable for a whole-file git diff.
# This is piper's own recommended replacement: same command syntax, but the
# output is cached and paged from disk, so scrolling costs nothing.
#
# Not in nixpkgs, so it is built the way the ones there are: a yazi plugin is a
# directory named <name>.yazi holding main.lua.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:
stdenvNoCC.mkDerivation {
  pname = "yazi-faster-piper";
  version = "0-unstable-2026-08-16";

  src = fetchFromGitHub {
    owner = "alberti42";
    repo = "faster-piper.yazi";
    rev = "bb90261ce3952762b0de2d5720ea176615c1bbd9";
    hash = "sha256-a7/KTIoIU9idxhYmYFsp6/ezmiBK/mEYfEz9zqZZiEU=";
  };

  dontBuild = true;

  # The wheel sends units, not lines. Every previewer decides what a unit is
  # worth, and yazi's own reads it as a tenth of the pane — which is why the
  # preview used to scroll like the rest of the terminal, and stopped when this
  # took over at one line per unit. piper had no such difference because it
  # handed seek straight back to yazi's previewer.
  #
  # The replacement below is yazi's own formula, from its `code` previewer:
  # a tenth of the pane, and at least one line so a short pane still moves.
  # --replace-fail rather than a patch file so that an upstream rewrite of the
  # line stops the build rather than silently restoring the old feel.
  installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      substitute main.lua "$out/main.lua" \
        --replace-fail \
          "local new_skip = cur + units" \
          "local step = math.floor(units * job.area.h / 10)
    local new_skip = cur + (step == 0 and ya.clamp(-1, units, 1) or step)"
      chmod 444 "$out/main.lua"
      runHook postInstall
  '';

  meta = {
    description = "Cache-backed rewrite of yazi's piper previewer";
    homepage = "https://github.com/alberti42/faster-piper.yazi";
    license = lib.licenses.mit;
  };
}
