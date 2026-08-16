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
    let packages = (
		open $"($root)/nix/modules/home/packages.nix"
		| lines
		| where {|l| $l =~ '^\s{4}[a-z0-9][a-z0-9._-]*$' }
		| each {|l| $l | str trim }
	)
    let casks = (
		open $"($root)/nix/modules/darwin/system.nix"
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
    let skills = (
        ls $"($root)/agents/skills"
        | where type == dir
        | get name
        | path basename
    )
    let functions = (
		ls $"($root)/fish/functions"
		| get name | path basename
		| each {|f| $f | str replace '.fish' '' }
	)
    {
        packages: $packages
        casks: $casks
        ai: $ai
        skills: $skills
        functions: $functions
        abbr_count: $abbrs
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
def is-documented [name: string, haystack: string] {
    $haystack | str contains ($name | str lowercase)
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

def drift [root: string, content: record] {
    let have = (installed $root)
    let hay = (
		$content.tabs
		| each {|t| $t.sections | each {|s| $s.items | each {|i| $"($i.name) ($i.desc)" } } }
		| flatten | flatten
		| str join ' '
		| str lowercase
	)
    let missing = (
		[
			...($have.packages | each {|n| {kind: "package", name: $n}})
			...($have.ai | each {|n| {kind: "ai", name: $n}})
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
            skills: ($have.skills | length)
            functions: ($have.functions | length)
            abbrs: $have.abbr_count
        }
    }
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
	)
    let dest = $env.CURRENT_FILE | path dirname | path join toolbelt.html
    $out | save -f $dest
    print $"written: ($dest)"
}
