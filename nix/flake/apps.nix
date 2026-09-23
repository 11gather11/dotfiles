{ inputs, ... }:
{
  perSystem =
    {
      config,
      localPkgs,
      username,
      linuxUsername,
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

      # sudo caches its authentication for five minutes; a rebuild that pulls in
      # a new package outlasts that easily, and the activation nh runs at the
      # very end then stops for a password with nobody watching. Refreshing the
      # timestamp while the build runs keeps the end of a long switch unattended.
      #
      # The loop is a Nushell job — a thread inside this process — so it needs no
      # exit trap the way a detached subshell would; it dies when this script
      # does. It never prompts: `--non-interactive` fails instead, which is the
      # signal to stop. The whole thing is skipped when stdin is not a terminal,
      # because the post-commit hook runs this too and there is no one to ask.
      sudoKeepAlive = lib.optionalString isDarwin ''
        if (is-terminal --stdin) {
            ^sudo --validate
            job spawn {
                loop {
                    sleep 60sec
                    try { ^sudo --non-interactive --validate } catch { break }
                }
            } | ignore
        }
      '';

      # `nh darwin` picks the configuration by hostname and `nh home` by
      # attribute name, and neither matches this machine's actual hostname —
      # both configurations are keyed on the account name, which differs
      # between macOS and Linux, and the aarch64 Linux one is suffixed. See
      # configurations.nix.
      homeConfig =
        if localPkgs.stdenv.hostPlatform.isAarch64 then "${linuxUsername}-aarch64" else linuxUsername;
      nhTarget =
        if isDarwin then
          ''"darwin" "switch" "-H" "${hostname}"''
        else
          ''"home" "switch" "-c" "${homeConfig}"'';
      nhBuildTarget =
        if isDarwin then
          ''"darwin" "build" "-H" "${hostname}"''
        else
          ''"home" "build" "-c" "${homeConfig}"'';

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
                ^${bash} ${../modules/home/programs/neovim/check.sh} $"($dotfiles)/nvim" $"($env.HOME)/.local/share/nvim/lazy" ${neovim} restore
            }
          ''
        );

        # The other half of the same script: move the plugins to their newest
        # revisions and write lazy-lock.json back. Run by hand, or weekly by
        # .github/workflows/update-nvim-plugins.yaml, which turns the resulting
        # lock file into a pull request.
        nvim-update = app (
          writeNu "nvim-update" ''
            def main []: nothing -> nothing {
                let declared = $env | get --optional DOTFILES_DIR | default "${homedir}/ghq/github.com/11gather11/dotfiles"
                let dotfiles = if ($declared | path exists) { $declared } else { pwd }
                ^${bash} ${../modules/home/programs/neovim/check.sh} $"($dotfiles)/nvim" $"($env.HOME)/.local/share/nvim/lazy" ${neovim} update
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
                ${sudoKeepAlive}
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

        # Re-resolves every pin in registry/sources/ and rewrites
        # registry/sources.lock.json. Skill sources live there rather than in
        # flake.lock, so updating them does not move every other input.
        skills-sources-lock = app "${
          inputs.agent-skills.lib.agent-skills.mkSourceLockProgram { pkgs = localPkgs; }
        }/bin/skills-sources-lock";

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
