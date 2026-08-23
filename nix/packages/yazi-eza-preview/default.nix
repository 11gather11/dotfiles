# Directory preview as an eza tree, rather than the single level yazi shows by
# default. Not in nixpkgs, so it is built the same way the ones there are: a
# yazi plugin is a directory named <name>.yazi holding main.lua.
#
# Keys come with it — e t toggles tree and list, e - and e _ change the depth,
# e * shows hidden entries, e g i and e g s bring gitignore and git status in.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  eza,
}:
stdenvNoCC.mkDerivation {
  pname = "yazi-eza-preview";
  version = "0-unstable-2026-06-30";

  src = fetchFromGitHub {
    owner = "ahkohd";
    repo = "eza-preview.yazi";
    rev = "e8fb6c8c57bc5f94ff269089078e76c8ed77cd21";
    hash = "sha256-8isGaJSVu7R76hKfGRszMdBOItYjVOKqvDpv9ccpBAs=";
  };

  dontBuild = true;

  # eza by absolute path: yazi runs the plugin with whatever PATH the session
  # has, and a plugin that silently previews nothing when eza is missing is the
  # kind of quiet failure this configuration keeps finding.
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    substitute main.lua "$out/main.lua" \
      --replace-fail '"eza"' '"${lib.getExe eza}"'
    runHook postInstall
  '';

  meta = {
    description = "Preview directories in yazi as an eza tree";
    homepage = "https://github.com/ahkohd/eza-preview.yazi";
    license = lib.licenses.mit;
  };
}
