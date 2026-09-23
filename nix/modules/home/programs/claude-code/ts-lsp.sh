# Starts the TypeScript 7 language server for Claude Code.
#
# TypeScript 7 has no tsserver: `tsc --lsp` is the server. The project's own
# tsc is preferred so diagnostics match what `pnpm tsc` reports there; the
# nearest node_modules/.bin/tsc from the working directory up is used when it
# is 7 or newer. An older one cannot serve LSP, so it is skipped for the tsc
# on PATH, which is TypeScript 7 from nixpkgs. Neovim's lspconfig picks the
# binary the same way.

dir=$PWD
while :; do
  candidate="$dir/node_modules/.bin/tsc"
  if [[ -x $candidate ]]; then
    # `tsc --version` prints "Version 7.0.2"; the major is what decides.
    major=$("$candidate" --version 2>/dev/null | sed -n 's/^Version \([0-9]*\).*/\1/p')
    if [[ -n $major && $major -ge 7 ]]; then
      exec "$candidate" --lsp --stdio "$@"
    fi
    break
  fi
  [[ $dir == / ]] && break
  dir=$(dirname "$dir")
done

exec tsc --lsp --stdio "$@"
