# Language servers for Claude Code, as one personal plugin: after an edit the
# server's diagnostics come back to the agent, before anything is built.
#
# Not the official *-lsp plugins. Those are only a command name to look up on
# PATH, and here the servers live in Neovim's extraPackages, which PATH does not
# see outside Neovim. Naming each server by store path needs no PATH at all.
#
# Imported by default.nix; the leading underscore keeps import-tree from loading
# it as a module of its own.
{ pkgs, lib }:
let
  jsonFormat = pkgs.formats.json { };

  tsServer = lib.getExe (
    pkgs.writeShellApplication {
      name = "claude-ts-lsp";
      runtimeInputs = with pkgs; [
        typescript
        coreutils
        gnused
      ];
      text = builtins.readFile ./ts-lsp.sh;
    }
  );

  # gopls and rust-analyzer read the project through its toolchain — `go list`,
  # `cargo metadata` — so each needs one. It is appended to PATH rather than
  # prepended: a devshell or rustup toolchain the project brings wins, and
  # nixpkgs' is only what is there when nothing else is.
  goServer = lib.getExe (
    pkgs.writeShellScriptBin "gopls" ''
      export PATH="''${PATH:+$PATH:}${lib.makeBinPath [ pkgs.go ]}"
      exec ${lib.getExe pkgs.gopls} "$@"
    ''
  );

  rustServer = lib.getExe (
    pkgs.writeShellScriptBin "rust-analyzer" ''
      # rust-analyzer finds the standard library's source through rustc's
      # sysroot. nixpkgs' rustc has none, so name it — but only when that rustc
      # is the one about to be used, or a rustup toolchain would get the wrong
      # library.
      if ! command -v cargo >/dev/null; then
        export RUST_SRC_PATH="''${RUST_SRC_PATH:-${pkgs.rustPlatform.rustLibSrc}}"
      fi
      export PATH="''${PATH:+$PATH:}${
        lib.makeBinPath [
          pkgs.cargo
          pkgs.rustc
        ]
      }"
      exec ${lib.getExe pkgs.rust-analyzer} "$@"
    ''
  );

  servers = {
    typescript = {
      command = tsServer;
      extensionToLanguage = {
        ".ts" = "typescript";
        ".tsx" = "typescriptreact";
        ".mts" = "typescript";
        ".cts" = "typescript";
        ".js" = "javascript";
        ".jsx" = "javascriptreact";
        ".mjs" = "javascript";
        ".cjs" = "javascript";
      };
    };
    go = {
      command = goServer;
      extensionToLanguage.".go" = "go";
    };
    rust = {
      command = rustServer;
      extensionToLanguage.".rs" = "rust";
    };
    nix = {
      command = lib.getExe pkgs.nixd;
      extensionToLanguage.".nix" = "nix";
    };
    python = {
      command = lib.getExe' pkgs.pyright "pyright-langserver";
      args = [ "--stdio" ];
      extensionToLanguage = {
        ".py" = "python";
        ".pyi" = "python";
      };
    };
  };
in
pkgs.runCommand "claude-lsp-plugin" { } ''
  install -Dm644 ${
    jsonFormat.generate "plugin.json" { name = "lsp"; }
  } $out/.claude-plugin/plugin.json
  install -Dm644 ${jsonFormat.generate "lsp.json" servers} $out/.lsp.json
''
