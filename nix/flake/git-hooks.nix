{
  perSystem =
    { config, lib, ... }:
    {
      pre-commit = {
        # These hooks run as a flake check, which is what makes them run at all:
        # the local .git/hooks/pre-commit is written by home-manager (see
        # nix/modules/home/git-hooks.nix), so the installation this module would
        # otherwise perform through the devShell never happened, and deadnix and
        # statix had never once executed.
        #
        # The local hook runs the same three tools directly rather than through
        # this definition. Sharing the implementation would mean putting
        # `pre-commit` itself in the system closure, and it brings Python 3.14
        # and its module tree with it — 1.5 GiB with no overlap with anything
        # already installed here, to install a shell script.
        check.enable = true;
        settings.hooks = {
          treefmt = {
            enable = true;
            package = config.treefmt.build.wrapper;
          };
        }
        # The linter list lives in nix/lib/linters.nix, which the home-manager
        # hook reads too. git-hooks.nix ships a ready-made hook for each of
        # these, so here the name is all that is needed.
        // lib.genAttrs (map (l: l.name) (import ../lib/linters.nix)) (_: {
          enable = true;
        });
      };
    };
}
