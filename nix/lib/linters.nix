# The Nix linters, named once.
#
# Two places run them and they cannot share an implementation: the flake check
# goes through cachix's git-hooks.nix, and the local pre-commit hook calls the
# binaries directly because putting `pre-commit` in the system closure costs
# 1.5 GiB (see nix/flake/git-hooks.nix). What they can share is this list, so
# adding a linter is one edit rather than two that drift apart.
#
# `scope` records the difference that is real: deadnix takes a file list, so the
# local hook can limit it to what is staged, while statix takes a single target
# and reads the tree. Written down here rather than discovered by reading both
# call sites.
[
  {
    name = "deadnix";
    package = pkgs: pkgs.deadnix;
    scope = "files";
    args = [ "--fail" ];
  }
  {
    name = "statix";
    package = pkgs: pkgs.statix;
    scope = "tree";
    args = [ "check" ];
  }
]
