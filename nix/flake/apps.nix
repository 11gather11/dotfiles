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
      nom = lib.getExe localPkgs.nix-output-monitor;
      treefmt = lib.getExe config.treefmt.build.wrapper;

      # Detect AI agent environments to skip nix-output-monitor
      isAgentCheck = ''
        IS_AI_AGENT=false
        for var in CLAUDE_CODE CLAUDECODE CODEX_SANDBOX CODEX_THREAD_ID GEMINI_CLI OPENCODE AUGMENT_AGENT GOOSE_PROVIDER CURSOR_AGENT AI_AGENT; do
          eval "val=\''${!var:-}"
          if [ -n "$val" ]; then
            IS_AI_AGENT=true
            break
          fi
        done
      '';

      # Keep sudo credentials warm during long Darwin switches so the
      # activation does not stall waiting for a password prompt. Runs only
      # on an interactive terminal ([ -t 0 ]); refreshes the timestamp every
      # 60s in the background and cleans the helper up on exit.
      sudoKeepAlive = lib.optionalString isDarwin ''
        if [ -t 0 ]; then
          sudo -v
          (
            while kill -0 "$$" 2>/dev/null; do
              sudo -n -v || exit 0
              sleep 60
            done
          ) &
          SUDO_KEEPALIVE_PID=$!
          trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
        fi
      '';

      configurationAttr =
        if isDarwin then
          "darwinConfigurations.${hostname}.system"
        else
          "homeConfigurations.${username}.activationPackage";
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
              if [ "$IS_AI_AGENT" = true ]; then
                nix build .#${configurationAttr}
              else
                ${nom} build .#${configurationAttr}
              fi
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
              ${sudoKeepAlive}
              echo "Building and switching to ${if isDarwin then "darwin" else "Home Manager"} configuration..."
              if [ "$IS_AI_AGENT" = true ]; then
                ${
                  if isDarwin then
                    "sudo nix run nix-darwin -- switch --flake .#${hostname}"
                  else
                    "nix run nixpkgs#home-manager -- switch --flake .#${username}"
                }
              else
                ${
                  if isDarwin then
                    "sudo nix run nix-darwin -- switch --flake .#${hostname} |& ${nom}"
                  else
                    "nix run nixpkgs#home-manager -- switch --flake .#${username} |& ${nom}"
                }
              fi
              echo "Clearing fish cache..."
              rm -rf "$TMPDIR/fish-cache"
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
