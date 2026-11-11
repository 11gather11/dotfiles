# The icons of the VS Code extension Material Icon Theme, for the file tree in
# herdr-app (herdr-app/mods/files-icons). Only the SVGs and the extension's
# lookup tables are taken; the npm package carries both, built.
{
  lib,
  stdenvNoCC,
  fetchurl,
  jq,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "material-icon-theme";
  version = "5.40.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/material-icon-theme/-/material-icon-theme-${finalAttrs.version}.tgz";
    hash = "sha256-bqE6LeznypU8AxWx6TNIZgwCuyNXBiddIVvmnwnZjvs=";
  };

  nativeBuildInputs = [ jq ];

  dontConfigure = true;
  dontBuild = true;

  # map.json is the theme's manifest cut to what a file tree reads, with every
  # name lowercased: VS Code matches file and folder names without regard to
  # case, and the mod then looks a name up with one lowercase key. The light
  # and high-contrast variants are left out; the app runs one dark theme.
  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp -r icons $out/icons
    cp LICENSE $out/LICENSE
    jq -c '
      def lower: with_entries(.key |= ascii_downcase);
      {
        file,
        folder,
        folderOpen: .folderExpanded,
        extensions: (.fileExtensions | lower),
        names: (.fileNames | lower),
        folders: (.folderNames | lower),
        foldersOpen: (.folderNamesExpanded | lower)
      }' dist/material-icons.json > $out/map.json
    runHook postInstall
  '';

  meta = {
    description = "File and folder icons of the Material Icon Theme for VS Code";
    homepage = "https://github.com/material-extensions/vscode-material-icon-theme";
    license = lib.licenses.mit;
  };
})
