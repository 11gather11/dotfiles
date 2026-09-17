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

      # Nushell, checked at build time — see nix/lib/helpers/write-nu.nix.
      writeNu = import ../lib/helpers/write-nu.nix { pkgs = localPkgs; };

      # Package executables, resolved via lib.getExe so the binary name comes
      # from each package's meta.mainProgram instead of being hand-written
      # (e.g. neovim ships nvim, nix-output-monitor ships nom).
      bash = lib.getExe localPkgs.bash;
      neovim = lib.getExe localPkgs.neovim;
      nh = lib.getExe localPkgs.nh;
      nix = lib.getExe localPkgs.nix;

      treefmt = lib.getExe config.treefmt.build.wrapper;

      # nix-output-monitor draws a live TUI, which is noise in a transcript
      # rather than progress. Detect the agent runners and let nh skip it.
      nomFlag = ''
        let agent_vars = [
            "CLAUDE_CODE"
            "CLAUDECODE"
            "CODEX_SANDBOX"
            "CODEX_THREAD_ID"
            "GEMINI_CLI"
            "OPENCODE"
            "AUGMENT_AGENT"
            "GOOSE_PROVIDER"
            "CURSOR_AGENT"
            "AI_AGENT"
        ]
        let nom = if ($agent_vars | any {|name| $env | get --optional $name | is-not-empty }) {
            ["--no-nom"]
        } else {
            []
        }
      '';

      # `nh darwin` picks the configuration by hostname and `nh home` by
      # attribute name, and neither matches this machine's actual hostname —
      # both configurations are keyed on the username.
      nhTarget =
        if isDarwin then
          ''"darwin" "switch" "-H" "${hostname}"''
        else
          ''"home" "switch" "-c" "${username}"'';
      nhBuildTarget =
        if isDarwin then ''"darwin" "build" "-H" "${hostname}"'' else ''"home" "build" "-c" "${username}"'';

      system = if isDarwin then "darwin" else "Home Manager";

      app = program: {
        type = "app";
        program = toString program;
      };
    in
    {
      apps = {
        nvim-restore = app (
          writeNu "nvim-restore" ''
            def main []: nothing -> nothing {
                let declared = $env | get --optional DOTFILES_DIR | default "${homedir}/ghq/github.com/11gather11/dotfiles"
                # Run from wherever the flake is when the checkout lives elsewhere.
                let dotfiles = if ($declared | path exists) { $declared } else { pwd }
                ^${bash} ${../modules/home/programs/neovim/check.sh} $"($dotfiles)/nvim" $"($env.HOME)/.local/share/nvim/lazy" ${neovim}
            }
          ''
        );

        build = app (
          writeNu (if isDarwin then "darwin-build" else "home-manager-build") ''
            # --wrapped so flags meant for nh — --show-trace, --print-build-logs —
            # pass through instead of being parsed here.
            def --wrapped main [...rest]: nothing -> nothing {
                ${nomFlag}
                print "Building ${system} configuration..."
                ^${nh} ${nhBuildTarget} ...$nom ...$rest .
                print "Build successful! Run 'nix run .#switch' to apply."
            }
          ''
        );

        switch = app (
          writeNu (if isDarwin then "darwin-switch" else "home-manager-switch") ''
            def --wrapped main [...rest]: nothing -> nothing {
                ${nomFlag}
                print "Building and switching to ${system} configuration..."
                ^${nh} ${nhTarget} ...$nom ...$rest .
                print "Clearing fish cache..."
                # /tmp, matching FISH_CACHE_DIR in fish/config.fish. $TMPDIR is a
                # per-user directory under /var/folders on macOS, so removing that
                # cleared nothing and the switch said it had.
                rm --recursive --force /tmp/fish-cache
                print "Done!"
            }
          ''
        );

        update = app (
          writeNu "flake-update" ''
            def --wrapped main [...rest]: nothing -> nothing {
                print "Updating flake.lock..."
                ^${nix} flake update ...$rest
                print "Done! Run 'nix run .#switch' to apply changes."
            }
          ''
        );

        update-ai-tools = app (
          writeNu "update-ai-tools" ''
            def main []: nothing -> nothing {
                print "Updating AI tools inputs..."
                ^${nix} flake update llm-agents
                print "Done! Run 'nix run .#switch' to apply changes."
            }
          ''
        );

        fmt = app (
          writeNu "treefmt-wrapper" ''
            def --wrapped main [...rest]: nothing -> nothing {
                exec ${treefmt} ...$rest
            }
          ''
        );
      };
    };
}
