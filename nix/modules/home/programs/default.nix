{
  pkgs,
  lib,
  config,
  dotfilesDir,
  helpers,
  fish-na,
  ...
}:
{
  imports = [
    ./go.nix

    # Fish shell plugin configuration
    (import ./fish {
      inherit
        pkgs
        fish-na
        lib
        config
        ;
    })

    # Claude Code configuration
    (import ./claude-code {
      inherit
        pkgs
        lib
        config
        dotfilesDir
        ;
    })

    # Direnv configuration with nix-direnv
    ./direnv.nix

    # jj configuration
    (import ./jj.nix {
      inherit
        pkgs
        lib
        config
        helpers
        ;
    })

    # GitHub CLI configuration
    (import ./gh.nix {
      inherit
        pkgs
        lib
        config
        ;
    })

    # Git configuration
    (import ./git {
      inherit
        pkgs
        lib
        config
        helpers
        ;
    })
  ];
}
