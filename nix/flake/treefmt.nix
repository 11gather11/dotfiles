{
  perSystem =
    { localPkgs, ... }:
    let
      inherit (localPkgs) lib;

      # Package executables, resolved via lib.getExe so the binary name comes
      # from each package's meta.mainProgram instead of being hand-written.
      fishIndent = lib.getExe' localPkgs.fish "fish_indent";
      gitleaks = lib.getExe localPkgs.gitleaks;
      nufmt = lib.getExe localPkgs.nufmt;
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
