{
  perSystem =
    { localPkgs, ... }:
    let
      inherit (localPkgs) lib;

      # Package executables, resolved via lib.getExe so the binary name comes
      # from each package's meta.mainProgram instead of being hand-written.
      fishIndent = lib.getExe' localPkgs.fish "fish_indent";
      gitleaks = lib.getExe localPkgs.gitleaks;
      # nufmt, refusing any change that leaves a file Nushell no longer
      # parses. It has dropped parentheses it took to be redundant: inside
      # `if (…)`, `skip ($i + 1)` became `skip $i + 1`, an extra argument, and
      # the broken script was committed because nothing parsed it afterwards.
      # Such a file is put back as it was and the run fails.
      nufmt = lib.getExe (
        localPkgs.writeShellApplication {
          name = "nufmt-checked";
          runtimeInputs = [
            localPkgs.nufmt
            localPkgs.nushell
            localPkgs.coreutils
          ];
          text = ''
            # $env.F is Nushell's, read from the environment, not the shell's.
            # The path goes absolute: run from a Nushell script (`nix run
            # .#fmt`), nu inherits that script's FILE_PWD and resolves a
            # relative path from there, finds nothing, and every check passes.
            # shellcheck disable=SC2016
            parses() { F="$(realpath -- "$1")" nu --no-config-file -c 'if not (nu-check $env.F) { exit 1 }' >/dev/null 2>&1; }
            status=0
            for f in "$@"; do
              before=$(mktemp)
              cp "$f" "$before"
              parsed=false
              if parses "$f"; then parsed=true; fi
              nufmt "$f" || status=$?
              if [ "$parsed" = true ] && ! parses "$f"; then
                cp "$before" "$f"
                echo "nufmt: formatting broke $f, so it was left as it was; rewrite the expression nufmt mangles" >&2
                status=1
              fi
              rm -f "$before"
            done
            exit "$status"
          '';
        }
      );
      oxfmt = lib.getExe localPkgs.oxfmt;
    in
    {
      treefmt = {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt = {
            enable = true;
            package = localPkgs.nixfmt-rfc-style;
          };
          stylua.enable = true;
          shfmt.enable = true;
          # Workflow linters. They change nothing, but treefmt is where the
          # pre-commit hook and the flake check both already look, and they
          # only ever match .github/workflows/.
          actionlint.enable = true;
          zizmor.enable = true;
        };
        settings = {
          global.excludes = [
            ".git/**"
            "*.lock"
          ];
          formatter = {
            oxfmt = {
              command = oxfmt;
              options = [ "--no-error-on-unmatched-pattern" ];
              includes = [ "*" ];
              excludes = [
                "nvim/template/**"
                "nvim/lazy-lock.json"
              ];
            };
            gitleaks = {
              command = gitleaks;
              options = [
                "detect"
                "--no-git"
                "--exit-code"
                "0"
              ];
              includes = [ "*" ];
              excludes = [
                "*.png"
                "*.jpg"
                "*.jpeg"
                "*.gif"
                "*.ico"
                "*.pdf"
                "*.woff"
                "*.woff2"
                "*.ttf"
                "*.eot"
                "node_modules/**"
                ".direnv/**"
                "nix/packages/node/**/package-lock.json"
              ];
            };
            fish-indent = {
              command = fishIndent;
              options = [ "--write" ];
              includes = [ "*.fish" ];
            };
            nufmt = {
              command = nufmt;
              includes = [ "*.nu" ];
            };
          };
        };
      };
    };
}
