#!/usr/bin/env nix
#! nix shell --inputs-from . nixpkgs#nushell --command nu
# Build the toolbelt page from content.json, and report where it has drifted
# from what the repository actually installs.
#
#   ./generate.nu            # write toolbelt.html next to this script
#   ./generate.nu --check    # only report drift, write nothing

# Names the repository actually installs right now. Each source is parsed with a
# narrow pattern rather than a general Nix reader: these files are hand-written
# lists, and a stricter parse fails loudly instead of silently returning [].
def installed [root: string] {
    # Every home-manager module, not just home/packages.nix. Platform-specific
    # lists and modules that install alongside their configuration — home-darwin
    # and the docker module — were invisible here, so the docker client and
    # lazydocker could be added without the page noticing.
    #
    # Scoped to the `home.packages = [ … ]` block rather than matching indented
    # words anywhere in the file: activation scripts are shell, and a plain
    # indent-and-word pattern reads `done`, `fi` and `let` as packages.
    let packages = (
		glob $"($root)/nix/modules/home*/**/*.nix"
		| each {|f|
			open --raw $f
			| parse --regex '(?s)home\.packages\s*=\s*(?:with\s+pkgs;\s*)?\[(?<body>.*?)\]'
			| get -o body
			| default []
		}
		| flatten
		| str join "\n"
		| lines
		| each {|l| $l | str trim | str replace --regex '^pkgs\.' '' }
		| where {|l| $l =~ '^_?[a-z0-9][a-z0-9._-]*$' }
		| uniq
	)
    # Casks live wherever the nix-darwin tree currently keeps homebrew. Naming
    # the file broke when darwin-system was split, so find the one that declares
    # them instead — a rename moves the block, it does not delete it.
    let cask_file = (
		glob $"($root)/nix/modules/darwin-system/**/*.nix"
		| where {|f| (open --raw $f) =~ 'casks\s*=\s*\[' }
	)
    if ($cask_file | is-empty) {
        error make {msg: "no module under nix/modules/darwin-system declares casks"}
    }
    let casks = (
		open ($cask_file | first)
		| lines
		| where {|l| $l =~ '^\s+"[a-z0-9/-]+"$' }
		| each {|l| $l | str trim | str replace --all '"' '' }
		| where {|c| not ($c | str ends-with '/tap') }
	)
    let ai = (
		open $"($root)/nix/modules/home/programs/ai-tools.nix"
		| lines
		| where {|l| $l =~ '^\s{4}[a-z0-9-]+$' }
		| each {|l| $l | str trim }
	)
    let abbrs = (
		open $"($root)/fish/config/abbrs_aliases.fish"
		| lines
		| where {|l| $l =~ '^abbr ' }
		| length
	)
    # The names themselves, not just how many. The by-purpose tab lists how a
    # tool is invoked — `ll`, `lzg`, `z` — rather than what is installed, so
    # without these every row there reads as describing something absent.
    let abbr_names = (
		open $"($root)/fish/config/abbrs_aliases.fish"
		| lines
		| each {|l| $l | parse --regex '^(?:abbr -a|alias) (?<name>[a-zA-Z0-9_-]+)' }
		| flatten
		| get -o name
		| default []
		| uniq
	)
    # Local skills, plus the ones selected from external sources. Only the
    # local directory used to be read, so a skill taken from a flake input was
    # installed without the page having to mention it — which is how eight
    # arrived at once and nothing said so.
    let skills = (
        (ls $"($root)/agents/skills" | where type == dir | get name | path basename)
        | append (
            # Skills that live with this repository's own tooling rather than
            # in agents/skills — the toolbelt generator is itself one of them.
            ls $"($root)/.claude/skills" | where type == dir | get name | path basename
        )
        | append (
            # The mattpocock selection is written as lists inside a helper call,
            # not as `name = { ... }` entries, so the parse below never saw any
            # of the eight. They were documented, which is why drift stayed
            # quiet; had one been added upstream and taken, nothing would have
            # said so either.
            open --raw $"($root)/nix/modules/home/agent-skills.nix"
            | parse --regex '(?s)mattpocockSelect\s*\{(?<body>.*?)\n      \}'
            | get -o body
            | default []
            | str join "\n"
            | parse --regex '"(?<name>[a-z0-9][a-z0-9-]*)"'
            | get -o name
            | default []
        )
        | append (
            open --raw $"($root)/nix/modules/home/agent-skills.nix"
            | parse --regex '(?s)explicit\s*=\s*\{(?<body>.*)'
            | get -o body
            | default []
            | str join "\n"
            | lines
            # Quotes and slashes allowed: an id namespaced by its source is
            # written "mattpocock/tdd", and a pattern that only accepted bare
            # words stopped counting nine skills the moment they were namespaced
            # — while still reporting no drift, because it was not looking.
            | each {|l| $l | parse --regex '^\s{8}"?(?<name>[a-z0-9][a-z0-9/-]*)"?\s*=\s*\{' }
            | flatten
            | get -o name
            | default []
        )
        | uniq
    )
    let functions = (
		ls $"($root)/fish/functions"
		| get name | path basename
		| each {|f| $f | str replace '.fish' '' }
	)
    # Flake inputs. tgrab arrives only this way — not through packages.nix, not
    # as a programs.* module — so nothing else here could see it, and it sat
    # undocumented until someone read the page against the config by hand.
    #
    # All of them, plumbing included: the package sets and module systems this
    # configuration is built from belong on a page about this machine as much as
    # the tools do. They get their own section so they do not crowd those.
    let flake_inputs = (
        open --raw $"($root)/flake.lock"
        | from json
        | get nodes.root.inputs
        | columns
        # The page names the tool, not the input: ast-grep-skill ships `ast-grep`.
        | each {|n| $n | str replace --regex '-skill$' '' }
    )
    # herdr plugins, declared in the module as a list of packages. Same blind
    # spot the fish plugins had: nothing here read that file, so three plugins
    # could be added without the page noticing.
    let herdr_plugins = (
        open --raw $"($root)/nix/modules/home/programs/herdr/default.nix"
        | lines
        # Not anchored to the whole line: herdr-reviewr is appended with
        # `++ lib.optional hasReviewr pkgs.herdr-reviewr` because upstream ships
        # it for aarch64-darwin only, and an anchored pattern stopped seeing it.
        | each {|l| $l | parse --regex 'pkgs\.(?<name>herdr-[a-z-]+)' }
        | flatten
        | get -o name
        | default []
        | uniq
    )
    # fish plugins, which live in their own module and were invisible to every
    # check here — four of fifteen went undocumented until the counts were read
    # by hand. The `name = "…"` lines include an install-path template, so the
    # entry containing a slash is dropped.
    let fish_plugins = (
        open --raw $"($root)/nix/modules/home/programs/fish/default.nix"
        | lines
        | each {|l| $l | parse --regex '^\s*name = "(?<name>[^"]+)"' }
        | flatten
        | get -o name
        | default []
        | where {|n| not ($n | str contains "/") }
        | uniq
    )
    # Tools enabled through a home-manager module rather than listed in
    # packages.nix. They are installed just as surely, but nothing above sees
    # them, so a `programs.<tool>.enable` on its own used to read as absent.
    let modules = (
        glob $"($root)/nix/modules/home/programs/**/*.nix"
        | each {|f| open --raw $f | lines }
        | flatten
        | each {|l| $l | parse --regex '^\s*programs\.(?<name>[a-z0-9-]+)\s*=' }
        | flatten
        | get -o name
        | default []
        # The page's module section names the file, not the option: claude-code
        # and codex configure their tools without a `programs.<name>` of their
        # own, so nothing here saw them and they belonged to no set at all.
        | append (
            glob $"($root)/nix/modules/home*/programs/*"
            | each {|f| $f | path basename | str replace --regex '\.nix$' '' }
        )
        | uniq
    )
    {
        packages: $packages
        casks: $casks
        ai: $ai
        modules: $modules
        fish_plugins: $fish_plugins
        herdr_plugins: $herdr_plugins
        flake_inputs: $flake_inputs
        skills: $skills
        functions: $functions
        abbr_count: $abbrs
        abbr_names: $abbr_names
    }
}

# Every name the page currently mentions, flattened across tabs.
def documented [content: record] {
    $content.tabs
    | each {|t| $t.sections | each {|s| $s.items | get name } }
    | flatten
    | flatten
    | each {|n| $n | split row ' ' | first | str lowercase }
    | uniq
}

# A name counts as documented if any mentioned name contains it — entries like
# "ll / la / lt" or "z <部分文字列>" cover several commands in one row.
# Matched against the set of documented names, not against the page's prose.
# A substring test called `gh` documented because some description contained
# "github" — the check said none of these were missing while never having
# looked one of them up.
def is-documented [name: string, documented: list<string>] {
    ($name | str downcase) in $documented
}

# Aliases resolve to a different binary than the name typed, so history records
# the alias. Reading them back means `ls` counts as a use of eza and `cat` as a
# use of bat, instead of both tools looking untouched.
def alias-map [root: string] {
    open $"($root)/fish/config/abbrs_aliases.fish"
    | lines
    | where {|l| $l =~ '^alias [a-z-]+ [a-z0-9_-]+$' }
    | reduce --fold {} {|l, acc|
        let parts = $l | split row ' '
        $acc | insert ($parts | get 1) ($parts | get 2)
    }
}

# How often each command was actually run, read from fish's history. Fish expands
# abbreviations before recording, so `cl` is already stored as `claude`; aliases
# are not expanded, so they are resolved through alias-map. Commands are counted
# wherever they start a pipeline segment, and `sudo` is stepped over.
def usage [names: list<string>, aliases: record = {}] {
    let file = [$env.HOME .local share fish fish_history] | path join
    if not ($file | path exists) {
        return {
            available: false
            counts: {}
            span: ""
        }
    }

    let raw = open --raw $file | lines
    let cmds = (
        $raw
        | where {|l| $l starts-with "- cmd: " }
        | each {|l| $l | str substring 7.. }
    )
    let heads = (
        $cmds
        | each {|c| $c | split row -r '\||;|&&' }
        | flatten
        | each {|seg|
            let words = $seg | str trim | split row ' ' | where {|w| $w != "" }
            if ($words | is-empty) { "" } else if ($words | first) == "sudo" {
                ($words | get -o 1 | default "")
            } else {
                ($words | first)
            }
        }
        | each {|w| $w | path basename }
        | each {|w| $aliases | get -o $w | default $w }
    )
    let stamps = (
        $raw
        | where {|l| ($l | str trim) starts-with "when: " }
        | each {|l| $l | str trim | str substring 6.. | into int }
        | sort
    )
    let span = if ($stamps | is-empty) { "" } else {
        let a = (
            $stamps
            | first
            | $in * 1_000_000_000 | into datetime
            | format date "%Y-%m-%d"
        )
        let b = (
            $stamps
            | last
            | $in * 1_000_000_000 | into datetime
            | format date "%Y-%m-%d"
        )
        $"($a) 〜 ($b), ($cmds | length) commands"
    }
    {
        available: true
        span: $span
        counts: ($names | reduce --fold {} {|n, acc|
            $acc | insert $n ($heads | where {|h| $h == $n } | length)
        })
    }
}

# Entries that point at a file which no longer exists. Removing a tool from the
# Nix side leaves its row on the page, and the undocumented-name check above
# cannot see it: that one only looks for installed names with no row. A row
# whose `expand` names a repository path is checkable in the other direction.
def stale [root: string, content: record] {
    $content.tabs
    | each {|t| $t.sections | each {|s| $s.items } }
    | flatten
    | flatten
    | where {|i| ($i | get -o expand | default "") =~ '^[a-zA-Z0-9._/-]+/[a-zA-Z0-9._-]+$' }
    | where {|i| not ([$root, $i.expand] | path join | path exists) }
    | each {|i| {name: $i.name, path: $i.expand} }
}

# Rows describing something that is no longer installed.
#
# The mirror of the drift check, which only looks the other way: it finds an
# installed name with no row, and cannot see a row whose tool has been removed.
# The stale check above catches some of them, but only rows whose `expand`
# names a path in this repository — a plain package row has none, so serie,
# git-now and terminal-notifier all kept their rows after being removed and
# nothing said so.
#
# Read against every installed set at once rather than per section: the page
# groups by what a thing is for, the sets by how it is declared, and the two do
# not line up — nh is a programs.* module sitting under CLI packages, and the
# module section names files rather than option names. Checking section against
# set reported thirty-three rows that were all installed.
#
# Three sections are left out because their names cannot be matched exactly,
# and a loose match here would be worse than no check: the abbreviation
# sections have no name list to compare against — only a count is collected —
# and the GUI section names applications the way a person does while Homebrew
# names them by cask id, so "Visual Studio Code" would have to be guessed onto
# visual-studio-code. Rather than guess, they are declared unchecked.
def orphaned [content: record, installed: record] {
    let unchecked = [
        # No name list is collected for either — only a count.
        "略語 — git 系"
        "略語 — その他"
        # The page names applications the way a person does; Homebrew names
        # them by cask id, and "Visual Studio Code" would have to be guessed
        # onto visual-studio-code.
        "GUI アプリ"
    ]

    let known = (
        [
            $installed.packages
            $installed.casks
            $installed.ai
            $installed.modules
            $installed.fish_plugins
            $installed.herdr_plugins
            $installed.flake_inputs
            $installed.skills
            $installed.functions
            $installed.abbr_names
        ]
        | flatten
        | each {|n| $n | str downcase }
        | uniq
    )

    $content.tabs
    | where {|t| ($t | get -o id) in ["all", "skills"] }
    | each {|t|
        $t.sections
        | where {|s| $s.title not-in $unchecked }
        | each {|s|
            $s.items
            | each {|i| $i.name | split row " " | first | str downcase }
            | where {|n| $n not-in $known }
            | each {|n| {name: $n, section: $s.title} }
        }
    }
    | flatten
    | flatten
}

# What an external skill source offers that this configuration has not taken.
#
# The allowlist in agent-skills.nix decides what installs, which is what keeps
# a skill from arriving in the agent's context because upstream added it. The
# cost is that upstream growing is invisible: renovate bumps the input, the lock
# moves, and nothing says a new skill appeared. This reports that, so the choice
# stays deliberate in both directions — nothing installs itself, and nothing new
# goes unnoticed either.
def unselected [root: string] {
    # Names come from two places now: the generator's lists, and the few
    # entries still written out with an explicit `path`. Reading only the
    # latter reported everything as unselected, which reads as "nothing is
    # installed" — the opposite of the truth.
    let module = (open --raw $"($root)/nix/modules/home/agent-skills.nix")
    let selected = (
        ($module | lines | each {|l| $l | parse --regex '^\s+"(?<p>[a-z0-9][a-z0-9-]*)"$' } | flatten | get -o p | default [])
        | append ($module | lines | each {|l| $l | parse --regex 'path = "(?<p>[^"]+)"' } | flatten | get -o p | default [])
        | uniq
    )

    # `open --raw` then `from json`: opening flake.lock directly yields a byte
    # stream, which has no cell paths, and the failure is a parse error rather
    # than an empty result.
    let lock = open --raw $"($root)/flake.lock" | from json | get nodes

    # One row per external skill source. Written as data because the report was
    # hardcoded to the first one, so a second source could be added and its
    # unselected skills would go unmentioned — the same silence this report
    # exists to break.
    [
        {
            input: "mattpocock-skills"
            repo: "mattpocock/skills"
            dirs: ["engineering" "productivity"]
        }
        {
            input: "cloudflare-skills"
            repo: "cloudflare/skills"
            dirs: [""]
        }
    ]
    | each {|src|
        let rev = $lock | get -o $src.input | default {} | get -o locked.rev
        if ($rev | is-empty) { return [] }
        let fetched = (^nix flake prefetch --json $"github:($src.repo)/($rev)" | complete)
        if $fetched.exit_code != 0 { return [] }
        let base = $fetched.stdout | from json | get storePath
        $src.dirs | each {|g|
            let dir = if ($g | is-empty) { $"($base)/skills" } else { $"($base)/skills/($g)" }
            if ($dir | path exists) {
                ls $dir | where type == dir | get name | path basename
                | where {|n| $n not-in $selected }
                | each {|n| if ($g | is-empty) { $"($src.repo)/($n)" } else { $"($src.repo)/($g)/($n)" } }
            } else { [] }
        }
    }
    | flatten
    | flatten
    | sort
}

def drift [root: string, content: record] {
    let have = (installed $root)
    # Tabs marked `historical` describe what is *not* installed. Their names
    # must not count as documentation: a tool listed as removed would otherwise
    # read as described the day it is installed again, and drift would go quiet
    # about exactly the change worth noticing.
    let hay = (
		$content.tabs
		| where {|t| ($t | get -o historical) != true }
		| each {|t| $t.sections | each {|s| $s.items | each {|i| $i.name } } }
		| flatten | flatten
		| each {|n| $n | str downcase }
		| uniq
	)
    let missing = (
		[
			...($have.packages | each {|n| {kind: "package", name: $n}})
			...($have.ai | each {|n| {kind: "ai", name: $n}})
			...($have.modules | each {|n| {kind: "module", name: $n}})
			...($have.fish_plugins | each {|n| {kind: "fish-plugin", name: $n}})
			...($have.herdr_plugins | each {|n| {kind: "herdr-plugin", name: $n}})
			...($have.flake_inputs | each {|n| {kind: "flake-input", name: $n}})
			...($have.skills | each {|n| {kind: "skill", name: $n}})
		]
		| where {|r| not (is-documented $r.name $hay) }
	)
    {
        missing: $missing
        counts: {
            packages: ($have.packages | length)
            casks: ($have.casks | length)
            ai: ($have.ai | length)
            modules: ($have.modules | length)
            fish_plugins: ($have.fish_plugins | length)
            herdr_plugins: ($have.herdr_plugins | length)
            flake_inputs: ($have.flake_inputs | length)
            skills: ($have.skills | length)
            functions: ($have.functions | length)
            abbrs: $have.abbr_count
        }
    }
}

# When the page was built, and which commit it describes. The commit matters as
# much as the clock: a rebuild of unchanged content moves the clock but not the
# revision, so the pair distinguishes "regenerated" from "actually changed".
def stamp [root: string] {
    let now = date now | format date "%Y-%m-%d %H:%M"
    let head = (^git -C $root rev-parse --short HEAD | complete)
    let status = (^git -C $root status --porcelain | complete)
    let dirty = ($status.exit_code == 0) and (($status.stdout | str trim) | is-not-empty)

    if $head.exit_code != 0 {
        return $"($now) 生成"
    }
    let rev = $head.stdout | str trim
    let mark = if $dirty {
        ' <span class="dirty">＋未コミットの変更</span>'
    } else { "" }
    $"($now) 生成 · リポジトリの ($rev) 時点($mark)"
}

def esc [s: string] {
    $s | str replace --all '&' '&amp;' | str replace --all '<' '&lt;' | str replace --all '>' '&gt;'
}

def render-item [item: record, cls: record] {
    let tag = if ($item | get -o tag | is-not-empty) {
        $'<span class="tag ($item.tag.kind)">($item.tag.text)</span>'
    } else { "" }
    let expand = if ($item | get -o expand | is-not-empty) {
        $'<span class="($cls.x)">(esc $item.expand)</span>'
    } else { "" }
    $'<div class="($cls.row)"><span class="($cls.key)">(esc $item.name)</span><span class="($cls.desc)">($item.desc)($tag)</span>($expand)</div>'
}

def render-section [section: record, cls: record] {
    let head = if ($section | get -o src | is-not-empty) {
        $'<div class="head"><h2>($section.title)</h2><span class="src">($section.src)</span></div>'
    } else {
        $'<h2>($section.title)</h2>'
    }
    let note = if ($section | get -o note | is-not-empty) { $'<p class="note">($section.note)</p>' } else { "" }
    let wide = if ($section.items | length) > 20 { " wide" } else { "" }
    let items = $section.items | each {|i| render-item $i $cls } | str join "\n      "
    $"    <section>\n      ($head)\n      ($note)\n      <div class=\"grid($wide)\">\n      ($items)\n      </div>\n    </section>"
}

def main [--check, --root: string = ""] {
    let root = if ($root | is-empty) {
        (
            $env.CURRENT_FILE
            | path dirname
            | path join .. .. ..
            | path expand
        )
    } else { $root }

    let content = open ($env.CURRENT_FILE | path dirname | path join content.json)
    let report = (drift $root $content)

    print $"installed: ($report.counts | to json -r)"
    if ($report.missing | is-empty) {
        print "drift: none — every installed package, AI tool and skill is described"
    } else {
        print $"drift: ($report.missing | length) undocumented"
        $report.missing | each {|m| print $"  ($m.kind)  ($m.name)" }
    }

    let gone = (stale $root $content)
    if ($gone | is-not-empty) {
        print $"stale: ($gone | length) row\(s\) point at a file that no longer exists"
        $gone | each {|g| print $"  ($g.name)  →  ($g.path)" }
    }

    let orphans = (orphaned $content (installed $root))
    if ($orphans | is-not-empty) {
        print $"orphaned: ($orphans | length) row\(s\) describe something no longer installed"
        $orphans | each {|o| print $"  ($o.section)  ($o.name)" }
    }

    # Which installed commands were never typed. This is a starting point for
    # deciding what to drop, not a verdict: a tool can be in daily use without
    # ever being typed — invoked by another program (delta by git, tirith by a
    # shell hook), used as a library (nodejs, uv), or reached through a wrapper
    # or editor rather than the prompt. Only the prompt is visible here.
    let have = (installed $root)
    let candidates = $have.packages ++ $have.ai | uniq
    let used = (usage $candidates (alias-map $root))
    if $used.available {
        let unused = $candidates | where {|n| ($used.counts | get $n) == 0 } | sort
        print $"history: ($used.span)"
        if ($unused | is-empty) {
            print "never typed: none — every installed command appears in the history"
        } else {
            print $"never typed: ($unused | length) — ($unused | str join ', ')"
            print "  (check each before removing: some are invoked by other tools, not by hand)"
        }
    } else {
        print "history: fish history not found; usage cannot be measured"
    }

    let spare = (unselected $root)
    if ($spare | is-not-empty) {
        print $"unselected: ($spare | length) skill\(s\) offered by the external sources and not taken"
        print $"  ($spare | str join ', ')"
    }

    if $check { return }

    let template = open ($env.CURRENT_FILE | path dirname | path join template.html)
    let panes = (
		$content.tabs
		| each {|t|
			let cls = if $t.id == "all" {
				{row: "item", key: "n", desc: "d", x: "x"}
			} else {
				{row: "row", key: "key", desc: "desc", x: "expand"}
			}
			let hidden = if $t.id == "use" { "" } else { " hidden" }
			let secs = $t.sections | each {|s| render-section $s $cls } | str join "\n\n"
			$"  <div class=\"pane\" id=\"pane-($t.id)\" role=\"tabpanel\" aria-labelledby=\"tab-($t.id)\"($hidden)>\n($secs)\n  </div>"
		}
		| str join "\n\n"
	)
    let tabs = (
		$content.tabs
		| enumerate
		| each {|r|
			let sel = if $r.index == 0 { "true" } else { "false" }
			$'      <button class="tab" id="tab-($r.item.id)" role="tab" aria-selected="($sel)" aria-controls="pane-($r.item.id)">($r.item.label)</button>'
		}
		| str join "\n"
	)
    let names = (
        $content.tabs
        | get id
        | each {|n| $"'($n)'" }
        | str join ", "
    )
    let ledes = $content.tabs | each {|t| $"    ($t.id): '($t.lede)'" } | str join ",\n"

    let out = (
		$template
		| str replace '<!--TABS-->' $tabs
		| str replace '<!--PANES-->' $panes
		| str replace '<!--NAMES-->' $names
		| str replace '<!--LEDES-->' $ledes
		| str replace '<!--FIRST_LEDE-->' ($content.tabs | first | get lede)
		| str replace '<!--STAMP-->' (stamp $root)
	)
    let dest = $env.CURRENT_FILE | path dirname | path join toolbelt.html
    $out | save -f $dest
    print $"written: ($dest)"
}
