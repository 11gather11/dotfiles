# Values the other flake modules in this directory read.
#
# Published through _module.args rather than a `let` in flake.nix, so each
# module asks for what it uses by name. The top-level set and the perSystem set
# are declared separately because flake-parts evaluates perSystem as its own
# submodule and does not forward the outer arguments into it.
{ inputs, ... }:
let
  inherit (inputs) nixpkgs;

  username = "11gather11";
  darwinHomedir = "/Users/${username}";
  linuxHomedir = "/home/${username}";

  # ../.. is this repository's root. Paths resolve against the flake source, so
  # this names the same fileset flake.nix used to write as ./agents/skills.
  local-skills = nixpkgs.lib.fileset.toSource {
    root = ../..;
    fileset = ../../agents/skills;
  };

  helpers = import ../modules/lib/helpers { inherit (nixpkgs) lib; };

  # Create pkgs with overlays
  mkPkgs =
    system:
    import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [
        # 上流が overlays.default を削除したため、その実装を再現する。
        # shared-nixpkgs は消費側の nixpkgs でビルドし直すのでバイナリキャッシュが
        # 効かず、agent-browser のフルソースビルドが走る。
        (final: _prev: {
          llm-agents = inputs.llm-agents.packages.${final.stdenv.hostPlatform.system} or { };
        })
        (_final: _prev: {
          _nix-claude-code = inputs.nix-claude-code;
        })
        inputs.nix-bun.overlays.default
        (import ../overlays)
      ];
    };

  # What every home-manager module in this tree may ask for by name. Modules are
  # listed in `imports` and the module system hands them these, so nothing is
  # threaded down through the intermediate default.nix files. `inputs` covers the
  # flake inputs a module reaches directly — fish-na, tgrab, the two external
  # skill sources — so adding one no longer means editing every file between here
  # and the module that wants it.
  homeSpecialArgs = homedir: {
    inherit inputs helpers local-skills;
    dotfilesDir = "${homedir}/ghq/github.com/11gather11/dotfiles";
  };
in
{
  _module.args = {
    inherit
      username
      darwinHomedir
      linuxHomedir
      local-skills
      helpers
      mkPkgs
      homeSpecialArgs
      ;
  };

  perSystem =
    { system, ... }:
    {
      _module.args = {
        inherit username darwinHomedir linuxHomedir;
        localPkgs = mkPkgs system;
      };
    };
}
