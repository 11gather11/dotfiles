{
  perSystem =
    {
      config,
      localPkgs,
      username,
      darwinHomedir,
      linuxHomedir,
      ...
    }:
    let
      inherit (localPkgs) lib;
      inherit (localPkgs.stdenv) isDarwin;
      homedir = if isDarwin then darwinHomedir else linuxHomedir;
      hostname = username;

      # Package executables, resolved via lib.getExe so the binary name comes
      # from each package's meta.mainProgram instead of being hand-written
      # (e.g. neovim ships nvim, nix-output-monitor ships nom).
      bash = lib.getExe localPkgs.bash;
      neovim = lib.getExe localPkgs.neovim;
      nh = lib.getExe localPkgs.nh;

      treefmt = lib.getExe config.treefmt.build.wrapper;

      # nix-output-monitor draws a live TUI, which is noise in a transcript
      # rather than progress. Detect the agent runners and let nh skip it.
      isAgentCheck = ''
        NOM_FLAG=""
        for var in CLAUDE_CODE CLAUDECODE CODEX_SANDBOX CODEX_THREAD_ID GEMINI_CLI OPENCODE AUGMENT_AGENT GOOSE_PROVIDER CURSOR_AGENT AI_AGENT; do
          eval "val=\''${!var:-}"
          if [ -n "$val" ]; then
            NOM_FLAG="--no-nom"
            break
          fi
        done
      '';

      # `nh darwin` picks the configuration by hostname and `nh home` by
      # attribute name, and neither matches this machine's actual hostname —
      # both configurations are keyed on the username.
      nhTarget = if isDarwin then "darwin switch -H ${hostname}" else "home switch -c ${username}";
      nhBuildTarget = if isDarwin then "darwin build -H ${hostname}" else "home build -c ${username}";
    in
    {
      apps = {
        nvim-restore = {
          type = "app";
          program = toString (
            localPkgs.writeShellScript "nvim-restore" ''
              : "''${DOTFILES_DIR:=${homedir}/ghq/github.com/11gather11/dotfiles}"
              if [ ! -d "$DOTFILES_DIR" ]; then
                DOTFILES_DIR="$(pwd)"
              fi
              exec ${bash} \
                ${../modules/home/programs/neovim/check.sh} \
                "$DOTFILES_DIR/nvim" \
                "$HOME/.local/share/nvim/lazy" \
                ${neovim}
            ''
          );
        };

        build = {
          type = "app";
          program = toString (
            localPkgs.writeShellScript (if isDarwin then "darwin-build" else "home-manager-build") ''
              set -e
              ${isAgentCheck}
              echo "Building ${if isDarwin then "darwin" else "Home Manager"} configuration..."
              ${nh} ${nhBuildTarget} $NOM_FLAG "$@" .
              echo "Build successful! Run 'nix run .#switch' to apply."
            ''
          );
        };

        switch = {
          type = "app";
          program = toString (
            localPkgs.writeShellScript (if isDarwin then "darwin-switch" else "home-manager-switch") ''
              set -eo pipefail
              ${isAgentCheck}
              echo "Building and switching to ${if isDarwin then "darwin" else "Home Manager"} configuration..."
              ${nh} ${nhTarget} $NOM_FLAG "$@" .
              echo "Clearing fish cache..."
              # /tmp, matching FISH_CACHE_DIR in fish/config.fish. $TMPDIR is a
              # per-user directory under /var/folders on macOS, so removing that
              # cleared nothing and the switch said it had.
              rm -rf /tmp/fish-cache
              echo "Done!"
            ''
          );
        };

        update = {
          type = "app";
          program = toString (
            localPkgs.writeShellScript "flake-update" ''
              set -e
              echo "Updating flake.lock..."
              nix flake update
              echo "Done! Run 'nix run .#switch' to apply changes."
            ''
          );
        };

        update-ai-tools = {
          type = "app";
          program = toString (
            localPkgs.writeShellScript "update-ai-tools" ''
              set -e
              echo "Updating AI tools inputs..."
              nix flake update llm-agents
              echo "Done! Run 'nix run .#switch' to apply changes."
            ''
          );
        };

        fmt = {
          type = "app";
          program = toString (
            localPkgs.writeShellScript "treefmt-wrapper" ''
              exec ${treefmt} "$@"
            ''
          );
        };
      };
    };
}
