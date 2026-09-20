{
  pkgs,
  lib,
  config,
  dotfilesDir,
  helpers,
  ...
}:
let
  nvimDotfilesDir = "${dotfilesDir}/nvim";
  nvimConfigDir = "${config.xdg.configHome}/nvim";
in
{
  programs.neovim = {
    enable = true;
    withPython3 = false;
    withRuby = false;
    withNodeJs = false;

    # Tools available on PATH only while Neovim is running
    extraPackages = with pkgs; [
      # Language servers (nixd is already on system PATH via packages.nix)
      lua-language-server
      # TypeScript 7 is the Go rewrite, so nixpkgs folded typescript-go into
      # this package and its binary is `tsc` — one compiler, which is also the
      # language server (`tsc --lsp`). See the cmd in nvim/lua/plugins/lsp.lua.
      typescript

      # Tools the enabled LazyVim extras (nvim/lazyvim.json) expect. Each extra
      # would have Mason fetch them, and Mason is disabled here.
      marksman # lang.markdown
      markdownlint-cli2 # lang.markdown: linter, and formatter when it reports
      markdown-toc # lang.markdown: formatter, only in files with a toc marker
      vscode-langservers-extracted # lang.json: jsonls
      yaml-language-server # lang.yaml
      taplo # lang.toml
      bash-language-server # util.dot
      shellcheck # util.dot, through bashls
      nushell # lang.nushell: the server is `nu --lsp`
      statix # lang.nix: linter

      # Formatters. The ones treefmt also runs are the same packages, so
      # formatting on save and the pre-commit hook agree.
      stylua
      nixfmt
      oxfmt # markdown, in place of the markdown extra's prettier
      shfmt # LazyVim formats sh with it by default

      # tree-sitter CLI: required by :TSInstall / :TSUpdate to build parsers
      tree-sitter

      # snacks.nvim's image viewer converts every format but PNG — webp, jpg,
      # gif, pdf — with `magick` before handing it to the terminal
      imagemagick
    ];
  };

  # Prevent home-manager from generating ~/.config/nvim/init.lua
  # since linkNvimConfig below symlinks the entire nvim dir from dotfiles
  xdg.configFile."nvim/init.lua".enable = lib.mkForce false;

  # Create symlink to NeoVim configuration in dotfiles (bypassing Nix store)
  home.activation.linkNvimConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${helpers.activation.mkLinkForce}
    link_force "${nvimDotfilesDir}" "${nvimConfigDir}"
  '';

  # Restore Neovim plugins via Lazy.nvim when lock file changes
  # (Lazy.nvim itself is auto-installed by Lua config)
  home.activation.restoreNeovimPlugins = lib.hm.dag.entryAfter [ "linkNvimConfig" ] ''
    LAZY_DIR="$HOME/.local/share/nvim/lazy"
    LAZY_LOCK="${nvimDotfilesDir}/lazy-lock.json"
    LAZY_LOCK_TIMESTAMP="$LAZY_DIR/.lazy-lock-timestamp"

    # Only restore if lock file has been updated
    if [[ ! -f "$LAZY_LOCK_TIMESTAMP" ]] || [[ "$LAZY_LOCK" -nt "$LAZY_LOCK_TIMESTAMP" ]]; then
      ${lib.getExe pkgs.bash} \
        ${./check.sh} \
        "${nvimDotfilesDir}" \
        "$LAZY_DIR" \
        ${lib.getExe pkgs.neovim}
    fi
  '';
}
