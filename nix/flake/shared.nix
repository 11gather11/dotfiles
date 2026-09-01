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

  helpers = import ../lib/helpers { inherit (nixpkgs) lib; };

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
        # Added beside nixpkgs' bun rather than over it. nix-bun's overlay
        # replaces `bun` outright, and `bun` is a build tool: every nixpkgs
        # package that compiles with it is then built against a bun nixpkgs
        # never tested, misses the binary cache, and is rebuilt here. hunk is
        # one of those, and its Linux build has failed ever since — upstream's
        # own x86_64-linux build of the same version is in cache.nixos.org and
        # works. Nothing here needs bun as a build input; the two places that
        # want the newer one want it to run, and ask for it by this name.
        (_final: prev: {
          bun-upstream = inputs.nix-bun.packages.${prev.stdenv.hostPlatform.system}.bun;
        })
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
  # local-skills has exactly one consumer (home/agent-skills.nix). It stays in
  # the shared set rather than being threaded to that one module because
  # threading single values by hand is what this refactor removed — but it is
  # the one entry here that is not genuinely repo-wide, so if a second thing
  # ever needs a fileset, give them a namespace instead of two loose names.
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
