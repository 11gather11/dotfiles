{ writeNu, ... }:
# Overlay the keys this repository declares onto a config file the application
# also writes itself, so a switch sets what it owns and leaves the rest alone.
# Reach for it where generating the file whole would drop application state —
# grok's first-run acknowledgements, Claude Code's `/permissions` decisions,
# the hook trust Codex records.
#
# Records are merged recursively; lists are replaced, so a list this repository
# declares is the whole list.
#
# Usage: merge-config <target> <owned>
writeNu "merge-config" ''
  # The target names the format for both files: what Nix generates is a store
  # path that may carry no extension at all.
  def read [file: path, format: string]: nothing -> record {
      match $format {
          "toml" => (open --raw $file | from toml)
          "json" => (open --raw $file | from json)
          _ => (error make { msg: $"merge-config: unsupported format: ($format)" })
      }
  }

  def write [file: path, format: string]: record -> nothing {
      # Bound before the match: the pipeline input is not in scope inside its
      # arms, where it reads as nothing and serialises to null.
      let data = $in
      let text = match $format {
          "toml" => ($data | to toml)
          "json" => ($data | to json --indent 2)
          _ => (error make { msg: $"merge-config: unsupported format: ($format)" })
      }
      $text | save --force $file
  }

  def main [target: path, owned: path]: nothing -> nothing {
      let format = $target | path parse | get extension
      # A target that no longer parses fails the activation rather than being
      # replaced, since replacing it is what the merge exists to avoid.
      let current = if ($target | path exists) { read $target $format } else { {} }
      mkdir ($target | path dirname)
      $current | merge deep (read $owned $format) | write $target $format
  }
''
