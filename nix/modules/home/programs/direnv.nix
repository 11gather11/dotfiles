{ inputs, ... }:
{
  imports = [ inputs.direnv-instant.homeModules.direnv-instant ];

  programs.direnv = {
    enable = true;
    # direnv-instant applies its cached environment on revisit; nix-direnv's
    # gcroots are what keep the store paths in that cache from being collected.
    nix-direnv.enable = true;
    config = {
      global = {
        warn_timeout = "0s";
        hide_env_diff = true;
      };
    };
    stdlib = ''
      export DIRENV_LOG_FORMAT=""
    '';
  };

  # Runs direnv in a daemon so the prompt returns before a slow .envrc
  # finishes; past mux_delay it opens a herdr pane showing direnv's output.
  # Only the package comes from here. fish/config.fish writes its own hook into
  # the config cache, and programs.fish is not enabled, so the module's shell
  # integrations would have nowhere to go — and turning them on would also
  # force off direnv's hooks for shells this configuration does not manage.
  programs.direnv-instant = {
    enable = true;
    enableBashIntegration = false;
    enableZshIntegration = false;
    enableFishIntegration = false;
    enableNushellIntegration = false;
  };
}
