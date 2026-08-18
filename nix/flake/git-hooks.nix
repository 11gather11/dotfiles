{
  perSystem =
    { config, ... }:
    {
      pre-commit = {
        check.enable = false;
        settings.hooks = {
          treefmt = {
            enable = true;
            package = config.treefmt.build.wrapper;
          };
          deadnix.enable = true;
          statix.enable = true;
        };
      };
    };
}
