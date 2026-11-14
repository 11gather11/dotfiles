{ writeNu, ... }:
# Overlay the keys this repository declares onto a config file the application
# also writes itself, so a switch sets what it owns and leaves the rest alone.
# Reach for it where generating the file whole would drop application state —
# Claude Code's `/permissions` decisions, the hook trust Codex records.
#
# Records are merged recursively; lists are replaced, so a list this repository
# declares is the whole list.
#
# A key this repository stops declaring is removed from the file too. Without
# that a merge only ever adds, and a setting deleted here stayed in force: what
# the last switch declared is kept beside the state of other tools, and a key
# it had that this one lacks goes. A key the application wrote itself was never
# declared, so it is never removed.
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

  # `current` without what `before` declared and `now` no longer does. Under
  # a key both still declare as a record, the same one level down; any other
  # value is the merge's to replace.
  def prune [before: record, now: record]: record -> record {
      let current = $in
      $before | columns | reduce --fold $current {|key, acc|
          if not ($key in $acc) {
              $acc
          } else if not ($key in $now) {
              $acc | reject $key
          } else {
              let was = $before | get $key
              let is = $now | get $key
              let has = $acc | get $key
              if (($was | describe) starts-with "record") and (($is | describe) starts-with "record") and (($has | describe) starts-with "record") {
                  $acc | upsert $key ($has | prune $was $is)
              } else {
                  $acc
              }
          }
      }
  }

  def main [target: path, owned: path]: nothing -> nothing {
      let format = $target | path parse | get extension
      # A target that no longer parses fails the activation rather than being
      # replaced, since replacing it is what the merge exists to avoid.
      let current = if ($target | path exists) { read $target $format } else { {} }
      let now = read $owned $format
      # What the last switch declared for this target, kept as JSON whatever
      # the target's format, under a name made from its path.
      let state = $env.XDG_STATE_HOME? | default ($env.HOME | path join .local/state) | path join merge-config
      let record = $state | path join ($"($target | path expand)" | str replace --all "/" "%" | $"($in).json")
      let before = if ($record | path exists) { open --raw $record | from json } else { {} }
      mkdir ($target | path dirname)
      $current | prune $before $now | merge deep $now | write $target $format
      mkdir $state
      $now | to json | save --force $record
  }
''
