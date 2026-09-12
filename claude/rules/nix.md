# Nix Rules

- Add `--print-build-logs --show-trace` only when debugging a failing build or an
  evaluation error; they are noise otherwise.
- In CI, `nix profile install --inputs-from . nixpkgs#<pkg>` is faster than
  setting up a full `nix develop` shell.
- Prefer `flake-parts` over `flake-utils`.
