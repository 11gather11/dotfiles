// A Claude Code session drawn as a conversation: its messages as rendered
// markdown (diagrams, formulas and pictures drawn, as the viewer does), each
// tool call laid out as the terminal lays it out (what it is for, the
// command, the start of its output, an edit's diff), and the choice Claude
// waits on as buttons. What is typed below goes to Claude.
//
// Claude itself keeps running in its terminal, in the same tab: this pane is
// a second view of it, not a replacement, so everything Claude Code can do
// still works there (`harness-tabs.chat` switches between the two). That is
// also what keeps it alive across a stopped core (claude-resume). The
// messages come from the session's transcript, not the terminal's screen;
// the screen is read only for what no transcript records: a dialog, the
// spinner line, and the footer's mode, context and usage.
//
// props: `terminal`, the address of the terminal Claude runs in.
import { View, div, image } from 'gpui-kit';
import {
	v_flex,
	h_flex,
	TextareaState,
	Textarea,
	ScrollHandle,
	Scrollbar,
	TextView,
	InputState,
	Input,
} from 'gpui-base';
import {
	props,
	exec,
	hc,
	agents,
	panes,
	focused,
	theme,
	settings,
	run,
	notify,
	openOverlay,
	appHome,
	setShared,
	nextCommand,
} from 'herdr';
import { Markdown } from './lib/markdown.js';
import {
	SIZE,
	SPACE,
	TEXT,
	RADIUS,
	button as uiButton,
	dot,
	badge,
	row,
	heading,
	chip,
} from './lib/ui.js';

// How often the transcript and the terminal are looked at. A stat while
// nothing changes; the new lines only when something did.
const POLL_MS = 1200;
// How far back the first read reaches, tried in turn (bytes); see readTail.
const TAIL_STEPS = [2e6, 6e6, 16e6];
// Claude Code's own slash commands, offered with the skills when "/" is
// typed. Those in MENUS open a menu of their own when sent bare, which only
// the terminal draws, so sending one shows the terminal.
const BUILTINS = [
	'add-dir',
	'agents',
	'btw',
	'clear',
	'compact',
	'config',
	'context',
	'cost',
	'doctor',
	'effort',
	'exit',
	'export',
	'fast',
	'help',
	'hooks',
	'init',
	'login',
	'logout',
	'mcp',
	'memory',
	'model',
	'output-style',
	'permissions',
	'plan',
	'plugin',
	'rc',
	'remote-control',
	'rename',
	'resume',
	'review',
	'rewind',
	'security-review',
	'status',
	'statusline',
	'tasks',
	'todos',
	'usage',
];
const MENUS = new Set([
	'agents',
	'config',
	'export',
	'hooks',
	'login',
	'mcp',
	'memory',
	'model',
	'output-style',
	'permissions',
	'plugin',
	'resume',
	'rewind',
	'status',
	'statusline',
	'tasks',
	'usage',
	'effort',
]);
// The skills a session can call, as Claude Code last listed them to it, and
// the person's own commands.
const COMMANDS = String.raw`
my ($path, $root) = @ARGV;
my %seen;
my @names;
open(my $f, '<', $path) or exit 1;
my $last;
while (my $line = <$f>) { $last = $line if $line =~ /"type":"skill_listing"/ }
if ($last && $last =~ /"names":\[([^\]]*)\]/) { push @names, $1 =~ /"([^"]+)"/g }
for my $md (glob("$root/commands/*.md")) { push @names, $1 if $md =~ m{([^/]+)\.md$} }
print join("\n", grep { !$seen{$_}++ } @names), "\n";
`;
// Writes the images of one record (a message, by its uuid) out of the
// transcript into a folder, once each, and prints each file's path and
// size in pixels. The view's reads leave image data out (see READ), so a
// picture is fetched only when its message is drawn.
const PICTURES = String.raw`
f=$(perl -MMIME::Base64 -ne '
	BEGIN { ($u, $d) = splice(@ARGV, 1, 2) }
	next unless /"uuid":"\Q$u\E"/;
	my $k = 0;
	while (/"media_type":"image\/(\w+)","data":"([A-Za-z0-9+\/=]+)"/g) {
		my $f = "$d/$u-$k.$1";
		unless (-e $f) { open(my $o, ">", $f) or die; binmode $o; print $o decode_base64($2); close $o }
		print "$f\n";
		$k++;
	}
	exit;
' "$1" "$2" "$3")
for p in $f; do
	printf '%s %s\n' "$p" "$(sips -g pixelWidth -g pixelHeight "$p" | awk '/pixel/ { printf "%s ", $2 }')"
done
`;
// A picture in a message is drawn at most this wide (px).
const THUMB = 240;
// How much further back each "Show earlier" reaches past what is loaded.
const EARLIER_BYTES = 8e6;
// A background task with no notification after this long is taken as gone.
const TASK_HOURS = 6;
// Reads a transcript from a byte offset to its last complete line, printing
// the offset it stopped at and the one its first whole line starts at, then
// those lines. What the view does not draw is
// left out on the way, and what it draws in part is cut: images' data (the
// view shows "1 image"), long strings, records it never shows. The output
// stays small however far back a read reaches; a command's output past the
// app's limit was cut off silently, and the newest messages with it. With a third argument of 1, the
// first line is skipped, as a read from the middle starts inside one. A
// fourth argument stops the read there (an earlier part of the file).
const READ = String.raw`
my ($path, $start, $skip, $stop) = @ARGV;
open(my $f, '<', $path) or exit 1;
binmode $f;
seek($f, $start, 0);
my $buf = '';
if ($stop) { read($f, $buf, $stop - $start) } else { local $/; $buf = <$f> // '' }
my $off = $start;
if ($skip) {
	my $i = index($buf, "\n");
	if ($i < 0) { print "$start $start\n"; exit }
	$buf = substr($buf, $i + 1);
	$off += $i + 1;
}
my $first = $off;
my $end = rindex($buf, "\n");
if ($end < 0) { print "$off $first\n"; exit }
$buf = substr($buf, 0, $end + 1);
$off += $end + 1;
# A string's inside, at most 4000 bytes (DETAIL_CHARS), cut where no escape is split.
sub cut {
	my ($s) = @_;
	return $s if length($s) <= 4000;
	$s = substr($s, 0, 4000);
	# Not inside a character: the bytes after its last start, if any, go too.
	$s =~ s/[\xC0-\xFF][\x80-\xBF]*$//;
	$s =~ s/\\u[0-9a-fA-F]{0,3}$//;
	$s =~ s/(?<!\\)((?:\\\\)*)\\$/$1/;
	return $s . '…';
}
print "$off $first\n";
for my $line (split /\n/, $buf) {
	# Records the view never draws, some of them the largest in the file:
	# requests as sent to the API, file snapshots, Claude Code's bookkeeping.
	next if $line =~ /"type":"(?:api-request[a-z-]*|file-history-[a-z]+|last-prompt|mode|permission-mode|atis-latch|session-owner|tools-used|cost-state|relocated|bridge-session|frame-link|agent-name|ai-title)"/;
	# Of the attachments, a message sent mid-turn and a hook's refusal are drawn.
	next if $line =~ /"type":"attachment"/ && $line !~ /"type":"(?:queued_command|hook_blocking_error)"/;
	$line =~ s/"data":"[A-Za-z0-9+\/=]{64,}"/"data":""/g;
	# A thinking block's signature: kilobytes of nothing to show.
	$line =~ s/"signature":"[^"]*"/"signature":""/g;
	# A long value (a file read, a command's output, a file written) to its
	# start: the view shows at most DETAIL_CHARS of one. Not what was said:
	# a reply's text and the person's message stay whole, as the view shows
	# all of them and Copy takes them.
	my $tool = $line =~ /"tool_result"/;
	my $reply = $line =~ /"role":"assistant"/;
	$line =~ s/("([A-Za-z_]+)":)"((?:[^"\\]++|\\.)*+)"/
		my ($k, $v) = ($2, $3);
		my $said = !$tool && ($k eq 'text' || (!$reply && ($k eq 'content' || $k eq 'prompt')));
		$1 . '"' . ($said ? $v : cut($v)) . '"'
	/ge;
	print $line, "\n";
}
`;
// Messages drawn at once, and how many more "Show earlier" adds.
const SHOWN = 120;
// A tool's input or result is cut here in its opened line.
const DETAIL_CHARS = 4000;
// The share of the pane's width a message takes at most.
const BUBBLE = 0.85;
// A tool's output shows this many lines until opened, as the terminal's
// "… +N lines" does.
const PREVIEW_LINES = 3;
// An edit's diff shows this many lines until opened.
const DIFF_LINES = 14;

/**
 * The one line a tool call is listed as: its name and what it acted on.
 *
 * @param {string} name
 * @param {Record<string, any>} input
 * @returns {string}
 * @example
 * summary("Read", { file_path: "/a/b/main.js" }) // => "main.js"
 */
function summary(name, input = {}) {
	const base = (p) =>
		String(p ?? '')
			.split('/')
			.pop();
	switch (name) {
		case 'Bash':
			return input.description || String(input.command ?? '').split('\n')[0];
		case 'Read':
		case 'Write':
		case 'Edit':
		case 'NotebookEdit':
			return base(input.file_path ?? input.notebook_path);
		case 'Grep':
		case 'Glob':
			return input.pattern ?? '';
		case 'WebFetch':
			return input.url ?? '';
		case 'WebSearch':
			return input.query ?? '';
		case 'Agent':
		case 'Task':
			return input.description ?? '';
		case 'Skill':
			return input.skill ?? '';
		default: {
			const first = Object.values(input).find((v) => typeof v === 'string');
			return first ? first.split('\n')[0] : '';
		}
	}
}

/**
 * The lines an edit adds and removes, from its input alone.
 *
 * @example
 * diffCount("Edit", { old_string: "a\nb", new_string: "a\nc\nd" }) // => { add: 3, del: 2 }
 */
function diffCount(name, input = {}) {
	const lines = (s) => (s ? String(s).split('\n').length : 0);
	if (name === 'Edit') return { add: lines(input.new_string), del: lines(input.old_string) };
	if (name === 'Write') return { add: lines(input.content), del: 0 };
	if (name === 'MultiEdit')
		return (input.edits ?? []).reduce(
			(n, e) => ({ add: n.add + lines(e.new_string), del: n.del + lines(e.old_string) }),
			{ add: 0, del: 0 },
		);
	return null;
}

/**
 * An edit as a diff block: removed lines, then added ones, per change.
 * Write shows the file as written, in its language.
 */
function diffText(name, input = {}) {
	const block = (old, now) =>
		[
			...String(old ?? '')
				.split('\n')
				.map((l) => `- ${l}`),
			...String(now ?? '')
				.split('\n')
				.map((l) => `+ ${l}`),
		].join('\n');
	if (name === 'Edit') return fenced(block(input.old_string, input.new_string), 'diff');
	if (name === 'MultiEdit')
		return (input.edits ?? [])
			.map((e) => fenced(block(e.old_string, e.new_string), 'diff'))
			.join('\n\n');
	if (name === 'Write')
		return fenced(
			String(input.content ?? ''),
			String(input.file_path ?? '')
				.split('.')
				.pop(),
		);
	return null;
}

/** A tool result's text, whichever shape it came in. */
function resultText(content) {
	if (typeof content === 'string') return content;
	if (Array.isArray(content))
		return content
			.map((b) => (b.type === 'text' ? b.text : b.type === 'image' ? '[image]' : ''))
			.join('\n');
	return '';
}

/** `text` as a fenced code block, its fence longer than any run of backticks in it. */
function fenced(text, lang = '') {
	const longest = Math.max(2, ...(text.match(/`+/g) ?? []).map((r) => r.length));
	const fence = '`'.repeat(longest + 1);
	return `${fence}${lang}\n${text}\n${fence}`;
}

const cut = (s, n) => (s.length > n ? `${s.slice(0, n)}\n… (${s.length - n} more characters)` : s);

/**
 * A choice Claude's screen waits on, read from its last lines: the numbered
 * options (`❯ 1. Yes`), each with the line under it that describes it if
 * any, and the lines above them that ask. Null when the screen shows none.
 *
 * Found by number: from the last option up to option 1, skipping what lies
 * between (descriptions, a rule before "Chat about this"), as the two kinds
 * of dialog lay them out differently.
 *
 * @param {string} screen the terminal's last lines
 * @returns {{ ask: string[], options: { key: string, label: string, note: string|null }[] } | null}
 */
function dialog(screen) {
	const raw = screen.split('\n');
	// Box drawing round the dialog, and dotted rules framing a command.
	// A dialog with previews lays them beside the options, a wide gap
	// between: only the left column is the dialog's.
	const lines = raw.map(
		(l) =>
			l
				.replace(/[│┃╭╮╰╯─━╌┄┈]/g, '')
				.trim()
				.split(/\s{4,}/)[0],
	);
	const option = (l) => /^(?:[❯›>]\s*)?(\d+)\.\s+(.*\S)$/.exec(l);
	let i = lines.length - 1;
	while (i >= 0 && !option(lines[i])) i--;
	if (i < 0) return null;
	const options = [];
	let want = Number(option(lines[i])[1]);
	let first = i;
	for (; i >= 0 && want >= 1 && lines.length - i < 40; i--) {
		const m = option(lines[i]);
		if (!m || Number(m[1]) !== want) continue;
		// A description sits right under its option, indented further.
		const next = lines[i + 1] ?? '';
		const note = next && !option(next) && /^\s{4,}\S/.test(raw[i + 1] ?? '') ? next : null;
		options.unshift({ key: m[1], label: m[2], note });
		first = i;
		want--;
	}
	if (want !== 0) return null; // not a run from 1: a list in a message
	// A dialog has a cursor on one option; a numbered list in a reply has none.
	if (!raw.slice(first).some((l) => /^[\s│|]*[❯›]\s*\d+\./.test(l))) return null;
	// The dialog starts below the last solid rule above option 1.
	let top = first - 1;
	while (top >= 0 && !/^\s*─{10,}\s*$/.test(raw[top])) top--;
	const ask = lines
		.slice(Math.max(top + 1, first - 14), first)
		.filter(Boolean)
		.slice(-10);
	return { ask, options };
}

/**
 * What Claude Code's last lines say about the session: the permission mode
 * ("⏵⏵ auto mode on"), and the context and usage the status line shows
 * ("Context 63% used · 5h 75% left · weekly 21% left"). Null for any it does
 * not show (the context appears once there is a conversation).
 *
 * @param {string} screen
 * @returns {{ mode: string | null, context: number | null, five: number | null, week: number | null }}
 * @example
 * footer("Opus 5.5 · Context ▌ 5% used · 5h ██ 75% left\n⏵⏵ auto mode on (shift+tab to cycle)")
 * // => { mode: "auto", context: 5, five: 75, week: null }
 */
function activity(screen) {
	// "✻ Elucidating… (11s · ↓ 680 tokens)": Claude Code's spinner line, the
	// glyph changing as it turns. The last on screen is the current one.
	const lines = screen.split('\n').slice(-20);
	for (let i = lines.length - 1; i >= 0; i--) {
		const m = /^\s*\S\s+(\p{Lu}[\p{L}-]*…)\s*\(([^)]*)\)/u.exec(lines[i]);
		if (m) return { verb: m[1], detail: m[2] };
	}
	return null;
}

function footer(screen) {
	const tail = screen.split('\n').slice(-8).join('\n');
	const num = (re) => {
		const m = re.exec(tail);
		return m ? Number(m[1]) : null;
	};
	const mode = /(?:⏵⏵|⏸)\s+(.+?)\s+on\b/.exec(tail)?.[1]?.replace(/ mode$/, '') ?? null;
	return {
		mode,
		context: num(/Context\D{0,40}?(\d+)% used/),
		five: num(/5h\D{0,40}?(\d+)% left/),
		week: num(/weekly\D{0,40}?(\d+)% left/),
	};
}

export default class Chat extends View {
	init(_props, cx) {
		this.addr = (props() ?? {}).terminal ?? null;
		this.root = null; // Claude's configuration folder
		this.session = null;
		this.path = null; // the transcript
		this.offset = 0; // bytes of it read
		this.items = [];
		this.tools = new Map(); // tool_use id => its item, for the result
		this.opened = new Set(); // tool lines and runs opened
		this.model = null;
		this.start = 0; // where the loaded part of the transcript begins
		// Background commands and agents started and not yet finished, by id.
		this.tasks = new Map();
		this.queued = []; // messages in Claude's queue, not yet taken in
		this.agents = new Map(); // background subagent id => its tool line
		this.pictures = new Map(); // record uuid => its images, made for the view
		this.commands = null; // the "/" list, read when first wanted
		this.box_text = ''; // the box's text, for the "/" list
		// The first message that came while the pane was not looked at.
		this.unreadFrom = null;
		this.hovered = null; // the message under the pointer, for its buttons
		this.find = null; // { query, hits, at } while searching
		this.findBox = InputState.new({ placeholder: 'Find in this conversation' });
		this.findBox.on('change', (_e, cx) => {
			this.search();
			cx.notify();
		});
		this.findBox.on('submit', (e, cx) => {
			this.step(e?.shift ? -1 : 1);
			cx.notify();
		});
		this.shown = SHOWN;
		this.follow = true; // keep the newest message in view
		this.card = null; // the dialog Claude waits on
		this.error = null;
		this.width = 800;
		this.busy = false;
		this.handle = cx.focus_handle();
		this.scroll = ScrollHandle.new();
		// What was being written here, kept across reloads and restarts.
		this.draftKey = `draft:${this.addr}`;
		this.box = TextareaState.new({
			placeholder: 'Message Claude…  (Shift+Enter: new line, ↑ for earlier ones)',
			value: localStorage.getItem(this.draftKey) ?? '',
		});
		this.footer = null; // what Claude's last lines say (see footer)
		this.recall = null; // which earlier message ↑ has put in the box
		// Room for a few lines from the start, as Shepherdr's box has; it grows
		// with a longer message and scrolls past that.
		this.box.set_auto_grow(3, 12);
		this.box.on('submit', (e, cx) => {
			if (e?.shift) return;
			// A "/" being typed: Enter takes the first offered, as in the terminal.
			const offered = this.offered();
			if (offered.length && !offered.some((c) => `/${c}` === this.box.value().trim())) {
				this.box.set_value(`/${offered[0]}`);
			}
			this.send(cx);
		});
		this.box.on('change', (_e, cx) => {
			this.box_text = this.box.value();
			localStorage.setItem(this.draftKey, this.box_text);
			if (this.box_text.startsWith('/') && this.commands === null) this.loadCommands(cx);
			cx.notify();
		});
		// A paste with no text in it, an image: Claude Code takes images from
		// the clipboard itself on Ctrl+V, into its own input as [Image #n],
		// where it waits to go out with the next message sent from here. The
		// bar counts them; no preview, which only the terminal has the image for.
		this.attached = 0;
		this.box.on('paste_other', (_e, cx) => {
			if (!this.addr) return;
			this.keys('ctrl+v');
			this.attached++;
			cx.notify();
		});
		cx.spawn(async (cx) => {
			for (;;) {
				const c = await nextCommand();
				if (c === 'focus') this.box.focus();
				cx.notify();
			}
		});
		this.poll(cx);
		cx.timer.every(POLL_MS, (cx) => this.poll(cx));
	}

	/** The agent this pane shows, as the app lists it (status, title). */
	agent() {
		return agents().find((a) => a.address === this.addr) ?? null;
	}

	poll(cx) {
		if (!this.addr || this.busy) return;
		this.busy = true;
		cx.spawn(async (cx) => {
			try {
				await this.locate(cx);
				await this.read(cx);
				await this.readScreen();
				await this.loadPictures(cx);
			} catch (e) {
				this.error = String(e.message ?? e);
			} finally {
				this.busy = false;
				cx.notify();
			}
		});
	}

	// Which transcript the terminal's Claude writes: the session the
	// claude-hc-session hook labelled it with, else the newest in its
	// folder's project (a session started before that hook).
	async locate(cx) {
		this.root ??= (
			await exec('sh', [
				'-c',
				'for d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.config/claude" "$HOME/.claude"; do [ -n "$d" ] && [ -d "$d/projects" ] && { printf %s "$d"; break; }; done',
			])
		).stdout.trim();
		if (!this.root) throw new Error('No Claude Code configuration folder');
		const r = await hc(['get', this.addr, '--json']);
		if (r.code !== 0) throw new Error('This terminal is gone');
		const t = JSON.parse(r.stdout);
		const session = t.labels?.['claude.session'] ?? null;
		const cwd = t.foreground?.cwd ?? t.cwd ?? '';
		const key = session ?? `cwd:${cwd}`;
		if (key === this.session && this.path) return;
		const find = session
			? ['-c', 'ls "$1"/projects/*/"$2".jsonl 2>/dev/null | head -1', '_', this.root, session]
			: [
					'-c',
					'ls -t "$1/projects/$2"/*.jsonl 2>/dev/null | head -1',
					'_',
					this.root,
					cwd.replace(/[^A-Za-z0-9]/g, '-'),
				];
		const path = (await exec('sh', find)).stdout.trim();
		// A new session (/clear, a resume elsewhere) starts the view over.
		this.session = key;
		this.path = path || null;
		this.offset = 0;
		this.items = [];
		this.tools.clear();
		this.agents.clear();
		this.shown = SHOWN;
		this.follow = true;
		this.attached = 0;
		this.unreadFrom = null;
		this.offsetRead = false;
		this.tasks.clear();
		this.queued = [];
		this.start = 0; // where the loaded part of the transcript begins
		this.error = path ? null : 'No conversation yet: send a message to start one';
	}

	// The lines added to the transcript since the last read. A line still
	// being written waits for the next read.
	async read(cx) {
		if (!this.path) return;
		if (this.offset === 0) return this.readTail(cx);
		const r = await exec('perl', ['-e', READ, this.path, String(this.offset), '0']);
		if (r.code === 0) this.take(r.stdout, cx);
	}

	// The first read: the transcript's end, as far back as SHOWN messages
	// reach. A transcript runs to tens of megabytes, a pasted screenshot alone
	// to one, so the end read grows until it holds enough or is the whole.
	async readTail(cx) {
		// At most the last step: past it a session's start waits for "Show
		// earlier" rather than slow the first look at its end.
		for (const bytes of TAIL_STEPS) {
			const st = await exec('stat', ['-f', '%z', this.path]);
			const size = Number(st.stdout.trim());
			if (!(size >= 0)) return;
			const start = Math.max(0, size - bytes);
			const r = await exec('perl', ['-e', READ, this.path, String(start), start > 0 ? '1' : '0']);
			if (r.code !== 0) return;
			this.items = [];
			this.tools.clear();
			this.agents.clear();
			this.start = this.take(r.stdout, cx);
			if (start === 0 || this.items.length >= SHOWN) return;
		}
	}

	// The part of the transcript before what is loaded, put in front of it:
	// "Show earlier" once every loaded message is shown.
	loadEarlier(cx) {
		if (!this.path || !this.start) return;
		const stop = this.start;
		const start = Math.max(0, stop - EARLIER_BYTES);
		cx.spawn(async (cx) => {
			const r = await exec('perl', [
				'-e',
				READ,
				this.path,
				String(start),
				start > 0 ? '1' : '0',
				String(stop),
			]);
			if (r.code !== 0) return;
			// take() reads into this.items and moves the offset and the unread
			// mark; for an earlier part none of that should change.
			const later = this.items;
			const offset = this.offset;
			const unread = this.unreadFrom;
			// What runs and waits now was settled by the later records: the
			// earlier part only adds messages above.
			const state = { tasks: this.tasks, queued: this.queued, agents: this.agents };
			this.tasks = new Map();
			this.queued = [];
			this.agents = new Map();
			this.items = [];
			const first = this.take(r.stdout, cx);
			const earlier = this.items;
			this.items = [...earlier, ...later];
			this.offset = offset;
			Object.assign(this, state);
			this.unreadFrom = unread === null ? null : unread + earlier.length;
			this.shown += earlier.length;
			this.start = first;
			this.follow = false;
			cx.notify();
		});
	}

	// READ's output: where it stopped and where its first line starts, then
	// the records between. Returns that start.
	take(out, cx) {
		const nl = out.indexOf('\n');
		if (nl < 0) return 0;
		const [stop, first] = out.slice(0, nl).split(' ').map(Number);
		this.offset = stop || this.offset;
		const before = this.items.length;
		for (const line of out.slice(nl + 1).split('\n')) {
			if (!line) continue;
			try {
				this.add(JSON.parse(line), cx);
			} catch {
				// A line that is not a record is not a message.
			}
		}
		if (this.items.length !== before) {
			if (this.follow) this.toBottom = true;
			// Came while the pane was not looked at: a line marks where.
			if (this.unreadFrom === null && this.offsetRead && !this.looking()) this.unreadFrom = before;
		}
		this.offsetRead = true;
		return first || 0;
	}

	/** Whether this chat pane has the keyboard: the person is looking at it. */
	looking() {
		const f = focused();
		return Boolean(f?.pane) && panes().some((p) => p.pane === f.pane && p.mod === 'chat');
	}

	add(rec, cx) {
		const before = this.items.length;
		this.addRecord(rec, cx);
		// When each message came, for its time and the day lines.
		const at = Date.parse(rec.timestamp) || null;
		for (let i = before; i < this.items.length; i++) {
			this.items[i].at ??= at;
			// The record a message came from: its images are read from it.
			this.items[i].uuid ??= rec.uuid ?? null;
		}
	}

	addRecord(rec, cx) {
		if (rec.isSidechain) return;
		// A pull request this session opened, where it was opened.
		if (rec.type === 'pr-link' && rec.prUrl) {
			if (this.items.some((x) => x.kind === 'pr' && x.url === rec.prUrl)) return;
			this.items.push({ kind: 'pr', url: rec.prUrl, number: rec.prNumber, repo: rec.prRepository });
			return;
		}
		// A message sent while Claude works waits in its queue until Claude
		// takes it in; shown at once, as queued, and dropped when taken (the
		// taken message then comes as a queued_command, or in the next turn).
		if (rec.type === 'queue-operation') {
			const text =
				typeof rec.content === 'string' ? rec.content.replace(/\[Image #\d+\]\s?/g, '').trim() : '';
			// Only what a person typed waits as a bubble: events queue too.
			if (rec.operation === 'enqueue' && text && !text.startsWith('<')) this.queued.push(text);
			else if (rec.operation === 'remove' || rec.operation === 'dequeue') {
				const k = this.queued.indexOf(text);
				if (k >= 0) this.queued.splice(k, 1);
				else if (!text) this.queued.shift();
			}
			return;
		}
		// A hook that stopped a tool call, and why: the first lines of what it said.
		if (rec.type === 'attachment' && rec.attachment?.type === 'hook_blocking_error') {
			const a = rec.attachment;
			const said = String(a.blockingError?.blockingError ?? a.blockingError ?? '').trim();
			this.items.push({
				kind: 'hook',
				name: a.hookName ?? a.hookEvent ?? 'hook',
				text: said,
				id: rec.uuid,
			});
			return;
		}
		// Claude Code's own notices: the recap it writes after a while away,
		// and lines such as "Compacted while idle". Other system records are
		// its bookkeeping.
		if (rec.type === 'system') {
			if (rec.subtype === 'away_summary' && rec.content)
				this.items.push({ kind: 'note', text: `recap: ${rec.content}` });
			else if (rec.subtype === 'informational' && rec.content)
				this.items.push({ kind: 'note', text: rec.content });
			// How long the reply took, closing it as the terminal does.
			else if (rec.subtype === 'turn_duration' && rec.durationMs >= 1000) {
				const s = Math.round(rec.durationMs / 1000);
				const took = s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${s % 60}s`;
				this.items.push({ kind: 'note', text: `Worked for ${took}` });
			}
			return;
		}
		// The summary a compaction leaves, recorded as a user message: one
		// line that opens to it, as the terminal folds it, not a bubble the
		// size of the conversation it replaces.
		if (rec.type === 'user' && rec.isCompactSummary) {
			const text = typeof rec.message?.content === 'string' ? rec.message.content : '';
			const md = new Markdown(`chat-summary-${this.items.length}`);
			md.set(text, rec.cwd ?? null, cx);
			this.items.push({ kind: 'compact', id: rec.uuid ?? `c${this.items.length}`, md });
			return;
		}
		if (rec.isMeta) return;
		// A message sent while Claude was busy: recorded when Claude takes it
		// in, as an attachment rather than a user turn.
		if (rec.type === 'attachment' && rec.attachment?.type === 'queued_command') {
			// Claude Code's own events come this way too (a background task
			// finishing, a subagent's report): notices, never the person's words.
			if (rec.attachment.origin?.kind !== 'human') {
				const prompt = rec.attachment.prompt;
				const text =
					typeof prompt === 'string'
						? prompt
						: Array.isArray(prompt)
							? prompt.map((b) => b.text ?? '').join('\n')
							: '';
				if (/<task-notification>|<agent-message/.test(text)) this.userText(text, 0);
				return;
			}
			const before = this.items.length;
			this.addUser(rec, rec.attachment.prompt);
			if (this.items.length > before) this.turnAt = Date.parse(rec.timestamp) || Date.now();
			return;
		}
		const content = rec.message?.content;
		if (rec.type === 'user') {
			const before = this.items.length;
			this.addUser(rec, content);
			// When the person last spoke: how long the reply has taken so far.
			if (this.items.length > before && this.items[this.items.length - 1].kind === 'user')
				this.turnAt = Date.parse(rec.timestamp) || Date.now();
		} else if (rec.type === 'assistant' && Array.isArray(content)) {
			this.addAssistant(rec, content, cx);
		}
	}

	addUser(rec, content) {
		if (typeof content === 'string') return this.userText(content, 0);
		if (!Array.isArray(content)) return;
		const texts = [];
		let images = 0;
		for (const b of content) {
			if (b.type === 'tool_result') {
				const tool = this.tools.get(b.tool_use_id);
				if (tool) {
					tool.result = resultText(b.content);
					tool.error = Boolean(b.is_error);
					// An edit's hunks with their line numbers, as Claude Code
					// recorded them: the diff the terminal draws.
					const patch = rec.toolUseResult?.structuredPatch;
					if (Array.isArray(patch) && patch.length) tool.patch = patch;
					// Started in the background: listed until its notification.
					// Only a call made to run in the background: a command's output can
					// hold the same words (one that searched transcripts did).
					const bg = tool.input?.run_in_background
						? /running in background with ID: (\w+)\. Output is being written to: (\S+?)\.?(?:\s|$)/.exec(
								tool.result,
							)
						: null;
					const agent =
						(tool.name === 'Agent' || tool.name === 'Task') &&
						/^Async agent launched/.test(tool.result.trim())
							? /agentId: (\w+)/.exec(tool.result)
							: null;
					const at = Date.parse(rec.timestamp) || Date.now();
					if (bg)
						this.tasks.set(bg[1], {
							id: bg[1],
							kind: 'command',
							name: tool.line,
							at,
							output: bg[2],
						});
					else if (agent) {
						this.tasks.set(agent[1], {
							id: agent[1],
							kind: 'agent',
							name: tool.input?.description ?? 'agent',
							at,
							tool,
						});
						// Keyed by the agent too, for its report when it comes.
						this.agents.set(agent[1], tool);
					}
				}
			} else if (b.type === 'text') texts.push(b.text);
			else if (b.type === 'image') images++;
		}
		if (texts.length || images) this.userText(texts.join('\n\n'), images);
	}

	addAssistant(rec, content, cx) {
		// The model each reply came from, for the bar: "claude-opus-5-5" as "Opus 5.5".
		const m = /^claude-([a-z]+)-(\d+)-(\d+)/.exec(rec.message?.model ?? '');
		if (m) this.model = `${m[1][0].toUpperCase()}${m[1].slice(1)} ${m[2]}.${m[3]}`;
		for (const b of content) {
			if (b.type === 'text' && b.text.trim()) {
				const md = new Markdown(`chat-${this.items.length}`);
				md.set(b.text, rec.cwd ?? null, cx);
				const item = {
					kind: 'assistant',
					id: `a${rec.uuid ?? this.items.length}`,
					md,
					text: b.text,
				};
				this.items.push(item);
			} else if (b.type === 'tool_use') {
				const tool = {
					kind: 'tool',
					id: b.id,
					name: b.name,
					line: summary(b.name, b.input),
					diff: diffCount(b.name, b.input),
					input: b.input,
					result: null,
					error: false,
				};
				this.tools.set(b.id, tool);
				this.items.push(tool);
			}
		}
	}

	// What the person sent, or a note for what Claude Code put in their
	// place: a slash command, its output, a `!` command, an interruption.
	userText(raw, images) {
		const text = raw
			.replace(/<system-reminder>[\s\S]*?<\/system-reminder>/g, '')
			// Claude Code's placeholder for a pasted image: the bubble lists images itself.
			.replace(/\[Image #\d+\]\s?/g, '')
			.trim();
		const tag = (name) => new RegExp(`<${name}>([\\s\\S]*?)</${name}>`).exec(text)?.[1]?.trim();
		if (text.startsWith('<command-name>')) {
			const args = tag('command-args');
			return this.items.push({
				kind: 'note',
				text: `${tag('command-name')}${args ? ` ${args}` : ''}`,
			});
		}
		if (text.startsWith('<local-command-stdout>')) {
			const out = tag('local-command-stdout');
			if (out) this.items.push({ kind: 'note', text: out.replace(/\x1b\[[0-9;]*m/g, '') });
			return;
		}
		if (text.startsWith('<bash-input>'))
			return this.items.push({ kind: 'note', text: `! ${tag('bash-input')}` });
		if (/^<(local-command-caveat|bash-stdout|bash-stderr)>/.test(text)) return;
		// A background task or subagent finishing: Claude Code's own event, as
		// one line, the way the terminal shows it.
		// One or several, alone or after a "[SYSTEM NOTIFICATION …]" preface:
		// Claude Code's events, never the person's words.
		if (text.includes('<task-notification>')) {
			for (const [, body] of text.matchAll(/<task-notification>([\s\S]*?)<\/task-notification>/g)) {
				const field = (name) =>
					new RegExp(`<${name}>([\\s\\S]*?)</${name}>`).exec(body)?.[1]?.trim();
				this.tasks.delete(field('task-id'));
				const said = field('summary') ?? `Background task ${field('status') ?? 'finished'}`;
				this.items.push({ kind: 'note', text: `● ${said}` });
			}
			return;
		}
		// A subagent's report handed back: noted; the report itself is the
		// subagent's tool line, opened.
		if (text.startsWith('<agent-message')) {
			const from = /<agent-message from="([^"]+)"/.exec(text)?.[1];
			if (from) this.tasks.delete(from);
			// The report itself, after the hand-back's preface, on its subagent's line.
			const tool = from && this.agents.get(from);
			const report = /The report follows:\n([\s\S]*?)(?:<\/agent-message>|$)/.exec(text)?.[1];
			if (tool && report) tool.report = report.replace(/^ {2}/gm, '').trim();
			return this.items.push({ kind: 'note', text: '● A subagent reported back' });
		}
		if (text.startsWith('[Request interrupted'))
			return this.items.push({ kind: 'note', text: 'Interrupted' });
		if (!text && !images) return;
		this.items.push({ kind: 'user', text, images });
	}

	// The images of the messages on screen not made yet, a few per poll: a
	// record's images are written out of the transcript into the cache, which
	// is under the app's folder, the only place a mod draws images from.
	async loadPictures(cx) {
		const want = this.items
			.slice(-this.shown)
			.filter((x) => x.kind === 'user' && x.images > 0 && x.uuid && !this.pictures.has(x.uuid))
			.slice(-3);
		if (!want.length || !this.path) return;
		const dir = `${appHome()}/cache/chat`;
		await exec('mkdir', ['-p', dir]).catch(() => null);
		// Made again from the transcript when wanted, so pictures not made for
		// a fortnight go, as md-asset prunes the viewer's cache.
		exec('find', [dir, '-type', 'f', '-mtime', '+14', '-delete']).catch(() => null);
		for (const it of want) {
			this.pictures.set(it.uuid, []);
			const r = await exec('sh', ['-c', PICTURES, '_', this.path, it.uuid, dir]).catch(() => null);
			const list = (r?.stdout ?? '')
				.split('\n')
				.map((l) => l.trim().split(/\s+/))
				.filter(([path, w, h]) => path && Number(w) && Number(h))
				.map(([path, w, h]) => ({
					file: path,
					path: path.slice(appHome().length + 1),
					w: Number(w),
					h: Number(h),
				}));
			this.pictures.set(it.uuid, list);
			cx.notify();
		}
	}

	// The dialog Claude waits on, read off its screen while it is blocked.
	// Claude's screen, read each poll for what no transcript records: its
	// footer (mode, context, usage) and a dialog it waits on, from the
	// startup's ("trust this folder?") to a permission. Never while it works:
	// a dialog stops it.
	async readScreen() {
		const r = await hc(['read', this.addr, '--lines', '40']);
		if (r.code !== 0) return;
		const f = footer(r.stdout);
		this.footer = {
			mode: f.mode ?? this.footer?.mode ?? null,
			context: f.context ?? this.footer?.context ?? null,
			five: f.five ?? this.footer?.five ?? null,
			week: f.week ?? this.footer?.week ?? null,
		};
		const working = this.agent()?.status === 'working';
		this.card = working ? null : dialog(r.stdout);
		this.activity = working ? activity(r.stdout) : null;
	}

	send(cx) {
		const text = this.box.value().trim();
		if ((!text && !this.attached) || !this.addr) return;
		this.box.set_value('');
		localStorage.removeItem(this.draftKey);
		this.recall = null;
		this.follow = true;
		// The pasted images go with this message.
		this.attached = 0;
		this.unreadFrom = null;
		const card = this.card;
		this.card = null;
		// Typed while a card waits: the answer in words. A question takes it
		// through its "Type something" option; a permission is declined first
		// ("No"), and the words go to Claude as what to do instead. The option
		// opens a box of its own, so the words follow a moment later.
		const typed = card?.options.find((o) => /^type something/i.test(o.label));
		const no = card?.options.find((o) => /^no\b/i.test(o.label));
		if (card && text && (typed || no)) {
			this.keys((typed ?? no).key);
			cx.timer.after(400, (cx) => this.deliver(text, cx, true));
			return;
		}
		this.deliver(text, cx);
		// A command whose menu only the terminal draws: show the terminal.
		const bare = /^\/([\w:-]+)$/.exec(text);
		if (bare && MENUS.has(bare[1])) this.showTerminal();
	}

	// The "/" list: the skills Claude Code listed to this session, the
	// person's own commands, and Claude Code's.
	loadCommands(cx) {
		this.commands = [];
		cx.spawn(async (cx) => {
			const r = this.path
				? await exec('perl', ['-e', COMMANDS, this.path, this.root ?? '']).catch(() => null)
				: null;
			const own = (r?.stdout ?? '').split('\n').filter(Boolean);
			this.commands = [...new Set([...own, ...BUILTINS])];
			cx.notify();
		});
	}

	/** The commands that fit what is typed after "/": by start, then anywhere. */
	offered() {
		const m = /^\/([\w:-]*)$/.exec(this.box_text.trim());
		if (!m || !this.commands?.length) return [];
		const q = m[1].toLowerCase();
		const starts = this.commands.filter((c) => c.toLowerCase().startsWith(q));
		const inside = this.commands.filter(
			(c) => !c.toLowerCase().startsWith(q) && c.toLowerCase().includes(q),
		);
		return [...starts, ...inside].slice(0, 8);
	}

	// `force`: into the box an answered card opened, which hc send would
	// otherwise refuse as a dialog it might answer by mistake.
	deliver(text, cx, force = false) {
		cx.spawn(async (cx) => {
			// Typed into a shell, the message would run as a command.
			if (!(await this.claudeRuns())) {
				this.box.set_value(text);
				this.box_text = text;
				this.error =
					'Claude is not running in this terminal: start it there, or switch to Terminal';
				cx.notify();
				return;
			}
			// Images alone: they are in Claude's input already, so Enter sends them.
			const send = force ? ['send', '--force', this.addr, text] : ['send', this.addr, text];
			const r = await hc(text ? send : ['keys', this.addr, 'enter']);
			if (r.code !== 0) {
				// Not lost: back in the box, with why.
				this.box.set_value(text);
				this.error = (r.stderr || r.stdout).trim().split('\n').pop() || 'Could not send';
			} else this.error = null;
			this.poll(cx);
			cx.notify();
		});
	}

	// This chat's own Claude in its terminal: harness-tabs switches the tab,
	// told which Claude, as a tab can hold two.
	showTerminal() {
		setShared('chat-origin', { terminal: this.addr, want: 'terminal' });
		run('harness-tabs.chat');
	}

	// The person's earlier messages, newest first, for ↑ and ↓ in the box.
	history() {
		return this.items
			.filter((x) => x.kind === 'user' && x.text)
			.map((x) => x.text)
			.reverse();
	}

	// ↑ (older) or ↓ (newer) through earlier messages, when the box is empty
	// or holds the one recalled: anything else typed is the person's, and
	// the arrows move in it.
	recallStep(by, cx) {
		const past = this.history();
		const now = this.box.value();
		if (now && (this.recall === null || now !== past[this.recall])) return false;
		const next = this.recall === null ? (by > 0 ? 0 : null) : this.recall + by;
		if (next === null || next >= past.length) return false;
		this.recall = next < 0 ? null : next;
		this.box.set_value(this.recall === null ? '' : past[this.recall]);
		this.box_text = this.box.value();
		cx.notify();
		return true;
	}

	// Takes the queued messages back out of Claude's queue: ↑ moves them
	// into its input, Ctrl+U clears that. `edit` puts them in this box to
	// change and send again.
	unqueue(edit, cx) {
		const text = this.queued.join('\n');
		this.keys('up');
		cx.timer.after(300, (cx) => {
			this.keys('ctrl+u');
			this.queued = [];
			if (edit) {
				this.box.set_value(text);
				this.box_text = text;
				this.box.focus();
			}
			cx.notify();
		});
	}

	// Whether the terminal's program in front is Claude Code: once it has
	// exited, the shell behind it would take what is typed as commands.
	// hc ls's `agent` is the program in front now; hc get's `foreground` is
	// the one the terminal started with, a shell even while Claude runs.
	async claudeRuns() {
		const r = await hc(['ls', '--json']).catch(() => null);
		if (r?.code !== 0) return false;
		const list = JSON.parse(r.stdout);
		const t = (Array.isArray(list) ? list : (list.terminals ?? [])).find(
			(x) => x.address === this.addr,
		);
		return t?.agent === 'claude-code';
	}

	// Keys for Claude (a card's answer, Esc, the mode), never for a shell.
	keys(...keys) {
		if (!this.addr) return;
		this.claudeRuns()
			.then((yes) => (yes ? hc(['keys', this.addr, ...keys]) : null))
			.catch(() => null);
	}

	// ── finding ──

	// The messages holding the query, newest last; the view moves to `at`.
	search() {
		const q = this.findBox.value().trim().toLowerCase();
		const text = (it) =>
			it.kind === 'user' || it.kind === 'note'
				? it.text
				: it.kind === 'assistant'
					? it.text
					: it.kind === 'tool'
						? `${it.name} ${it.line}`
						: '';
		const hits = q
			? this.items.flatMap((it, i) => ((text(it) ?? '').toLowerCase().includes(q) ? [i] : []))
			: [];
		this.find = { ...this.find, query: q, hits, at: hits.length ? hits.length - 1 : -1 };
		this.reveal();
	}

	step(by) {
		const f = this.find;
		if (!f?.hits.length) return;
		f.at = (f.at + by + f.hits.length) % f.hits.length;
		this.reveal();
	}

	// Brings the current hit into view: older messages are drawn first if it
	// is among them, and following stops.
	reveal() {
		const f = this.find;
		if (!f || f.at < 0) return;
		const i = f.hits[f.at];
		this.shown = Math.max(this.shown, this.items.length - i);
		const it = this.items[i];
		this.follow = false;
		this.revealing = i;
	}

	openFind(cx) {
		this.find = { query: '', hits: [], at: -1 };
		this.findBox.focus();
		cx.notify();
	}

	closeFind(cx) {
		this.find = null;
		this.revealing = null;
		this.box.focus();
		cx.notify();
	}

	// ── pieces ──

	button(t, id, label, action, strong = false) {
		return uiButton(t, id, label, action, { kind: strong ? 'primary' : 'ghost' });
	}

	// The conversation as rows, as the terminal lays it out: each message and
	// each tool call on its own, a line where the day changes and one where
	// the unread part begins.
	rows(from) {
		const items = this.items.slice(from).map((it, k) => ({ it, i: from + k }));
		const out = [];
		let day = null;
		for (const { it, i } of items) {
			const d = it.at ? new Date(it.at).toDateString() : day;
			if (d && d !== day) {
				if (day !== null) out.push({ kind: 'day', at: it.at, i });
				day = d;
			}
			if (i === this.unreadFrom) out.push({ kind: 'unread', i });
			out.push(it.kind === 'tool' ? { kind: 'tool', it, i } : { ...it, i });
		}
		return out;
	}

	// The time a message came, "14:05", with the day when it is not today.
	clock(at) {
		if (!at) return '';
		const d = new Date(at);
		const hm = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
		return d.toDateString() === new Date().toDateString()
			? hm
			: `${d.getMonth() + 1}/${d.getDate()} ${hm}`;
	}

	// Under a message: its time, and Copy while the pointer is on it. The
	// line is always there, so showing Copy moves nothing.
	meta(t, it, i, right) {
		const hit = this.find?.hits[this.find.at] === i;
		return h_flex()
			.h(SIZE.control)
			.gap(SPACE.sm)
			.items_center()
			.when(right, (e) => e.justify_end())
			.text_size(TEXT.meta)
			.text_color(hit ? t.accent : t.dim)
			.child(this.clock(it.at))
			.when(this.hovered === i, (e) =>
				e.child(
					this.button(t, `copy-${i}`, 'Copy', (_e, cx) => {
						cx.write_to_clipboard(it.text ?? '');
						notify({ title: 'Copied', level: 'success', timeout: 1500 });
					}),
				),
			);
	}

	row(t, it, col) {
		const i = it.i;
		const hover = (e) =>
			e.on_hover((on, cx) => {
				const was = this.hovered;
				if (on) this.hovered = i;
				else if (this.hovered === i) this.hovered = null;
				if (was !== this.hovered) cx.notify();
			});
		const hit = this.find?.hits[this.find.at] === i;
		if (it.kind === 'day')
			return h_flex()
				.id(`chat-day-${i}`)
				.gap(SPACE.sm)
				.items_center()
				.py(SPACE.xs)
				.text_size(TEXT.meta)
				.text_color(t.dim)
				.child(div().flex_1().h(1).bg(t.border))
				.child(new Date(it.at).toLocaleDateString())
				.child(div().flex_1().h(1).bg(t.border));
		if (it.kind === 'unread')
			return h_flex()
				.id('chat-unread')
				.gap(SPACE.sm)
				.items_center()
				.text_size(TEXT.meta)
				.text_color(t.accent)
				.child(div().flex_1().h(1).bg(t.accent))
				.child('New')
				.child(div().flex_1().h(1).bg(t.accent));
		if (it.kind === 'user')
			return hover(
				v_flex()
					.id(`chat-u-${i}`)
					.w_full()
					.items_end()
					.child(
						v_flex()
							.max_w(col * BUBBLE)
							.px(SPACE.md + 2)
							.py(SPACE.sm + 1)
							.gap(SPACE.xs)
							.rounded(RADIUS.card + 2)
							.bg(t.accent + '24')
							.when(hit, (e) => e.border_1().border_color(t.accent))
							// A line break typed is a line break: markdown would join the lines.
							.child(
								TextView.markdown(
									`chat-ut-${i}`,
									(it.text || '').replace(/\n/g, '  \n'),
								).selectable(true),
							)
							.when(it.images > 0, (e) => e.child(this.picturesView(t, it, i))),
					)
					.child(this.meta(t, it, i, true)),
			);
		if (it.kind === 'assistant')
			return hover(
				v_flex()
					.id(`chat-a-${i}`)
					.max_w(col * BUBBLE)
					.child(
						v_flex()
							.px(SPACE.lg)
							.py(SPACE.md - 2)
							.gap(SPACE.xs)
							.rounded(RADIUS.card + 2)
							.bg(t.surface)
							.border_1()
							.border_color(hit ? t.accent : t.border)
							// All of it, as the terminal shows it.
							.child(it.md.view(t, col * BUBBLE - 34)),
					)
					.child(this.meta(t, it, i, false)),
			);
		if (it.kind === 'compact') {
			const open = this.opened.has(it.id);
			return v_flex()
				.id(`chat-c-${i}`)
				.gap(SPACE.xs)
				.child(
					row(t, `chat-ch-${i}`, {
						onClick: (_e, cx) => {
							if (open) this.opened.delete(it.id);
							else this.opened.add(it.id);
							cx.notify();
						},
					})
						.text_size(TEXT.meta)
						.text_color(t.dim)
						.child(
							div()
								.w(12)
								.flex_none()
								.child(open ? '▾' : '▸'),
						)
						.child('Conversation compacted · summary'),
				)
				.when(open, (e) =>
					e.child(
						div()
							.ml(SPACE.lg)
							.px(SPACE.lg)
							.py(SPACE.sm)
							.rounded(RADIUS.card)
							.border_1()
							.border_color(t.border)
							.child(it.md.view(t, col * BUBBLE - 60)),
					),
				);
		}
		if (it.kind === 'pr')
			return h_flex()
				.id(`chat-pr-${i}`)
				.gap(SPACE.sm)
				.items_center()
				.child(
					chip(
						t,
						`chat-prc-${i}`,
						t.accent,
						`PR #${it.number}${it.repo ? ` · ${it.repo}` : ''}`,
						() => exec('open', [it.url]),
					),
				);
		if (it.kind === 'hook') {
			const open = this.opened.has(`hook:${it.id}`);
			const first = it.text.split('\n').find((l) => l.trim()) ?? '';
			return v_flex()
				.id(`chat-h-${i}`)
				.px(SPACE.sm)
				.py(SPACE.xs)
				.gap(SPACE.xs)
				.rounded(RADIUS.control)
				.bg(`${t.ansi1}14`)
				.cursor_pointer()
				.on_click((_e, cx) => {
					if (open) this.opened.delete(`hook:${it.id}`);
					else this.opened.add(`hook:${it.id}`);
					cx.notify();
				})
				.child(
					h_flex()
						.gap(SPACE.sm)
						.text_size(TEXT.meta)
						.child(
							div().flex_none().text_color(t.ansi1).font_semibold().child(`Stopped by ${it.name}`),
						)
						.when(!open, (e) =>
							e.child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(first)),
						),
				)
				.when(open, (e) =>
					e.child(
						div()
							.text_size(TEXT.ui)
							.child(
								TextView.markdown(`chat-hb-${i}`, fenced(cut(it.text, DETAIL_CHARS))).selectable(
									true,
								),
							),
					),
				);
		}
		if (it.kind === 'note')
			return div()
				.id(`chat-n-${i}`)
				.px(SPACE.sm)
				.text_size(TEXT.meta)
				.text_color(hit ? t.accent : t.dim)
				.child(it.text);
		return this.tool(t, it.it, i);
	}

	// A message's pictures as thumbnails, each opening full size; until they
	// are read out of the transcript, how many there are.
	picturesView(t, it, i) {
		const list = it.uuid ? this.pictures.get(it.uuid) : null;
		if (!list?.length)
			return div()
				.text_size(TEXT.meta)
				.text_color(t.muted)
				.child(`📎 ${it.images} image${it.images > 1 ? 's' : ''}`);
		return h_flex()
			.flex_wrap()
			.gap(SPACE.xs)
			.children(
				list.map((p, k) => {
					const scale = Math.min(1, THUMB / p.w);
					return div()
						.id(`chat-img-${i}-${k}`)
						.rounded(RADIUS.control)
						.overflow_hidden()
						.cursor_pointer()
						.on_click(() =>
							openOverlay({
								mod: 'viewer',
								kind: 'dialog',
								width: 0.85,
								height: 0.9,
								props: { file: p.file },
							}),
						)
						.child(
							image(p.path)
								.w(p.w * scale)
								.h(p.h * scale),
						);
				}),
			);
	}

	// Messages in Claude's queue, not taken in yet: drawn as the person's,
	// framed in dashes and marked Queued until Claude reads them.
	queuedView(t, col) {
		return (
			v_flex()
				.gap(SPACE.sm)
				.children(
					this.queued.map((text, k) =>
						v_flex()
							.id(`chat-q-${k}`)
							.w_full()
							.items_end()
							.child(
								div()
									.max_w(col * BUBBLE)
									.px(SPACE.md + 2)
									.py(SPACE.sm + 1)
									.rounded(RADIUS.card + 2)
									.border_1()
									.border_dashed()
									.border_color(t.accent)
									.text_color(t.muted)
									.child(
										TextView.markdown(`chat-qt-${k}`, text.replace(/\n/g, '  \n')).selectable(true),
									),
							)
							.child(div().text_size(TEXT.meta).text_color(t.dim).child('Queued')),
					),
				)
				// Claude Code takes queued messages back all at once (↑), so the
				// two act on them all.
				.child(
					h_flex()
						.justify_end()
						.gap(SPACE.xs)
						.child(this.button(t, 'queue-edit', 'Edit', (_e, cx) => this.unqueue(true, cx)))
						.child(this.button(t, 'queue-cancel', 'Cancel', (_e, cx) => this.unqueue(false, cx))),
				)
		);
	}

	// Claude at work: the terminal's spinner line ("Elucidating… (11s · ↓ 680
	// tokens)"), with a still dot, as for a working agent everywhere else
	// here. Redrawn by each poll.
	liveRow(t) {
		const s = this.turnAt ? Math.max(0, Math.round((Date.now() - this.turnAt) / 1000)) : null;
		const took = s === null ? '' : s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${s % 60}s`;
		return (
			h_flex()
				.h(SIZE.row)
				.px(SPACE.sm)
				.gap(SPACE.sm)
				.items_center()
				.text_size(TEXT.meta)
				.child(dot(t, 'working'))
				// What the terminal shows ("Elucidating… (11s · ↓ 680 tokens)"),
				// else how long since the person spoke.
				.child(
					div()
						.flex_none()
						.text_color(t.muted)
						.child(this.activity?.verb ?? 'Thinking…'),
				)
				.child(
					div()
						.flex_none()
						.text_color(t.dim)
						.child(this.activity?.detail ?? took),
				)
		);
	}

	// One tool call, laid out as the terminal lays it out:
	//   ⏺ what it is for          (a command's description, else Tool(target))
	//     ⎿ $ the command          (or the file, the pattern)
	//       its output's first lines, "… +N lines" opening the rest
	// An edit shows its diff and a subagent its report the same way. The dot
	// is the call's state: working, failed, done.
	tool(t, it, id) {
		const open = this.opened.has(it.id);
		const toggle = (_e, cx) => {
			if (open) this.opened.delete(it.id);
			else this.opened.add(it.id);
			cx.notify();
		};
		const color = it.result === null ? t.working : it.error ? t.ansi1 : t.ansi2;
		const bash = it.name === 'Bash';
		const agent = it.name === 'Agent' || it.name === 'Task';
		const title = bash
			? it.input?.description || 'Bash'
			: agent
				? `${it.input?.subagent_type ?? 'Agent'}(${it.input?.description ?? ''})`
				: `${it.name}(${it.line})`;
		const mono = settings().font_family ?? 'monospace';
		// The second line: what the call acted on.
		const target = bash ? `$ ${String(it.input?.command ?? '').split('\n')[0]}` : null;
		// What it gave back: an edit's diff, a subagent's report, else output.
		const diff = it.patch ? null : diffText(it.name, it.input);
		const said = agent ? (it.report ?? it.result) : it.result;
		const body = it.patch ? null : (diff ?? (said === null ? null : said || '(no output)'));
		const limit = diff ? DIFF_LINES : PREVIEW_LINES;
		const lines = body === null ? [] : body.split('\n');
		const more = lines.length - limit;
		let shown = open || more <= 0 ? body : lines.slice(0, limit).join('\n');
		// A diff cut short keeps its code block closed.
		if (diff && shown !== body) shown += `\n${/^`+/.exec(diff)?.[0] ?? '```'}`;
		const markdown = diff
			? shown
			: agent
				? cut(shown ?? '', DETAIL_CHARS)
				: fenced(cut(shown ?? '', DETAIL_CHARS));
		return v_flex()
			.id(`chat-t-${id}`)
			.px(SPACE.sm)
			.gap(2)
			.child(
				h_flex()
					.gap(SPACE.sm)
					.items_center()
					.child(div().flex_none().text_color(color).child('⏺'))
					.child(
						div()
							.flex_1()
							.min_w(0)
							.truncate()
							.text_color(t.foreground)
							.font_semibold()
							.child(title),
					)
					.when(Boolean(it.diff), (e) =>
						e
							.child(
								div().flex_none().text_size(TEXT.meta).text_color(t.ansi2).child(`+${it.diff.add}`),
							)
							.child(
								div().flex_none().text_size(TEXT.meta).text_color(t.ansi1).child(`−${it.diff.del}`),
							),
					),
			)
			.when(Boolean(target), (e) =>
				e.child(
					h_flex()
						.pl(SPACE.lg)
						.gap(SPACE.sm)
						.text_size(TEXT.ui)
						.font_family(mono)
						.text_color(t.muted)
						.child(div().flex_none().text_color(t.dim).child('⎿'))
						.child(div().flex_1().min_w(0).truncate().child(target)),
				),
			)
			.when(Boolean(it.patch), (e) => e.child(this.patchView(t, it, id, open, toggle)))
			.when(body !== null, (e) =>
				e.child(
					v_flex()
						.pl(SPACE.lg + SPACE.md)
						.child(
							div()
								.text_size(TEXT.ui)
								.text_color(it.error ? t.ansi1 : t.muted)
								.child(TextView.markdown(`chat-tb-${id}`, markdown).selectable(true)),
						)
						.when(more > 0, (e) =>
							e.child(
								div()
									.id(`chat-tm-${id}`)
									.text_size(TEXT.meta)
									.text_color(t.dim)
									.cursor_pointer()
									.hover((st) => st.text_color(t.foreground))
									.on_click(toggle)
									.child(open ? '… show less' : `… +${more} lines`),
							),
						),
				),
			);
	}

	// An edit's hunks, line by line as the terminal draws them: the line's
	// number, its sign, the text in the terminal's font, removed lines on red
	// and added ones on green, "…" between hunks. Its first DIFF_LINES until
	// opened.
	patchView(t, it, id, open, toggle) {
		const rows = [];
		for (const [h, hunk] of it.patch.entries()) {
			if (h > 0) rows.push({ gap: true });
			let old = hunk.oldStart ?? 0;
			let now = hunk.newStart ?? 0;
			for (const line of hunk.lines ?? []) {
				const sign = line[0];
				if (sign === '-') rows.push({ n: old++, sign, text: line.slice(1) });
				else if (sign === '+') rows.push({ n: now++, sign, text: line.slice(1) });
				else {
					rows.push({ n: now, sign: ' ', text: line.slice(1) });
					old++;
					now++;
				}
			}
		}
		const more = rows.length - DIFF_LINES;
		const shown = open || more <= 0 ? rows : rows.slice(0, DIFF_LINES);
		const mono = settings().font_family ?? 'monospace';
		return v_flex()
			.ml(SPACE.lg + SPACE.md)
			.text_size(TEXT.ui)
			.font_family(mono)
			.children(
				shown.map((r, k) =>
					r.gap
						? div().id(`chat-pg-${id}-${k}`).pl(SPACE.sm).text_color(t.dim).child('…')
						: h_flex()
								.id(`chat-pl-${id}-${k}`)
								.when(r.sign === '-', (e) => e.bg(`${t.ansi1}38`))
								.when(r.sign === '+', (e) => e.bg(`${t.ansi2}38`))
								.child(
									div()
										.w(44)
										.flex_none()
										.pr(SPACE.sm)
										.text_right()
										.text_color(t.dim)
										.child(String(r.n)),
								)
								.child(
									div()
										.w(14)
										.flex_none()
										.text_color(r.sign === '-' ? t.ansi1 : r.sign === '+' ? t.ansi2 : t.dim)
										.child(r.sign),
								)
								.child(
									div()
										.flex_1()
										.min_w(0)
										.truncate()
										.text_color(t.foreground)
										.child(r.text.replace(/\t/g, '  ') || ' '),
								),
				),
			)
			.when(more > 0, (e) =>
				e.child(
					div()
						.id(`chat-pm-${id}`)
						.pl(SPACE.sm)
						.text_size(TEXT.meta)
						.text_color(t.dim)
						.cursor_pointer()
						.hover((st) => st.text_color(t.foreground))
						.on_click(toggle)
						.child(open ? '… show less' : `… +${more} lines`),
				),
			);
	}

	cardView(t) {
		const c = this.card;
		return v_flex()
			.p(SPACE.md)
			.gap(SPACE.sm)
			.rounded(RADIUS.card)
			.border_1()
			.border_color(t.blocked)
			.bg(t.background)
			.child(
				v_flex()
					.gap(2)
					.text_size(TEXT.ui)
					.children(
						c.ask.map((l, i) =>
							div()
								.id(`ask-${i}`)
								.text_color(i === c.ask.length - 1 ? t.foreground : t.muted)
								.child(l),
						),
					),
			)
			.child(
				v_flex()
					.gap(SPACE.xs)
					.children(
						c.options.map((o) =>
							h_flex()
								.id(`opt-${o.key}`)
								.min_h(SIZE.row + 4)
								.px(SPACE.md - 2)
								.gap(SPACE.sm)
								.items_center()
								.rounded(RADIUS.control)
								.border_1()
								.border_color(t.border)
								.cursor_pointer()
								.hover((s) => s.bg(t.hover))
								.on_click((_e, cx) => {
									this.keys(o.key);
									this.card = null;
									cx.notify();
								})
								.child(div().flex_none().text_color(t.accent).child(o.key))
								.child(
									v_flex()
										.flex_1()
										.min_w(0)
										.py(SPACE.xs)
										.child(o.label)
										.when(Boolean(o.note), (e) =>
											e.child(div().text_size(TEXT.meta).text_color(t.dim).child(o.note)),
										),
								),
						),
					),
			)
			.child(
				h_flex()
					.gap(SPACE.sm)
					.items_center()
					.child(this.button(t, 'card-esc', 'Esc', () => this.keys('esc')))
					.child(this.button(t, 'card-terminal', 'Open the terminal', () => this.showTerminal()))
					.child(div().text_size(TEXT.meta).text_color(t.dim).child('or type an answer below')),
			);
	}

	// What runs in the background: commands and agents started and not yet
	// finished, with how long each has run. A command opens to its output.
	tasksView(t, tasks) {
		const age = (at) => {
			const s = Math.max(0, Math.round((Date.now() - at) / 1000));
			if (s < 60) return `${s}s`;
			if (s < 3600) return `${Math.floor(s / 60)}m`;
			return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
		};
		return v_flex()
			.py(SPACE.xs)
			.rounded(RADIUS.card)
			.border_1()
			.border_color(t.border)
			.bg(t.surface)
			.child(heading(t, 'Running', tasks.length))
			.children(
				tasks.map((x) =>
					row(t, `task-${x.id}`, {
						onClick: x.output
							? () =>
									openOverlay({
										mod: 'viewer',
										kind: 'dialog',
										width: 0.8,
										height: 0.85,
										props: { file: x.output },
									})
							: undefined,
					})
						.mx(SPACE.xs)
						.child(dot(t, 'working'))
						.child(badge(t, x.kind))
						.child(div().flex_1().min_w(0).truncate().text_color(t.foreground).child(x.name))
						.child(div().flex_none().text_size(TEXT.meta).text_color(t.dim).child(age(x.at))),
				),
			);
	}

	// The commands that fit the "/" being typed; a click (or Tab) puts one
	// in the box.
	slashView(t, offered) {
		return v_flex()
			.py(SPACE.xs)
			.rounded(RADIUS.card)
			.border_1()
			.border_color(t.border)
			.bg(t.surface)
			.children(
				offered.map((c, k) =>
					row(t, `slash-${c}`, { selected: k === 0, onClick: (_e, cx) => this.complete(c, cx) })
						.mx(SPACE.xs)
						.child(div().flex_none().text_color(t.foreground).child(`/${c}`))
						.when(MENUS.has(c), (e) =>
							e.child(div().text_size(TEXT.meta).text_color(t.dim).child('opens in the terminal')),
						),
				),
			);
	}

	complete(command, cx) {
		this.box.set_value(`/${command} `);
		this.box_text = this.box.value();
		this.box.focus();
		cx.notify();
	}

	findBar(t) {
		const f = this.find;
		return h_flex()
			.id('chat-find')
			.h(SIZE.bar)
			.flex_none()
			.px(SPACE.md)
			.gap(SPACE.sm)
			.items_center()
			.border_b(1)
			.border_color(t.border)
			.child(Input.new(this.findBox).flex_1().text_size(TEXT.ui))
			.child(
				div()
					.flex_none()
					.text_size(TEXT.meta)
					.text_color(t.dim)
					.child(f.query ? (f.hits.length ? `${f.at + 1} / ${f.hits.length}` : 'No match') : ''),
			)
			.child(this.button(t, 'find-prev', '↑', (_e, cx) => (this.step(-1), cx.notify())))
			.child(this.button(t, 'find-next', '↓', (_e, cx) => (this.step(1), cx.notify())))
			.child(this.button(t, 'find-close', '✕', (_e, cx) => this.closeFind(cx)));
	}

	render() {
		const t = theme();
		const a = this.agent();
		const status = a?.status ?? null;
		const from = Math.max(0, this.items.length - this.shown);
		const rows = this.rows(from);
		const earlier = from > 0 || this.start > 0;
		const notice = !this.path || this.error;
		// While Claude works, a line at the end says what it is doing, as the
		// terminal's spinner line does, a tool running or not.
		const live = status === 'working';
		// The scroll area's children: the "Show earlier" line and the notice
		// when shown, one per row, the live line, then the end.
		const before = (earlier ? 1 : 0) + (notice ? 1 : 0);
		if (this.revealing !== null && this.revealing !== undefined) {
			const k = rows.findIndex(
				(r) =>
					r.i === this.revealing || r.list?.some((x) => this.items.indexOf(x) === this.revealing),
			);
			if (k >= 0) this.scroll.scroll_to_item(before + k);
			this.revealing = null;
		} else if (this.follow || this.toBottom) {
			// While following, every frame ends at the bottom: a message grows
			// after it arrives (its markdown laid out, a picture made), and one
			// request made when it arrived stops short of what it grows to. The
			// target is an empty last child, so the space under the last
			// message shows too.
			this.scroll.scroll_to_item(
				before + rows.length + (live ? 1 : 0) + (this.queued.length ? 1 : 0),
			);
			this.toBottom = false;
		}
		// The conversation takes the pane's width, as Shepherdr's does: Claude's
		// replies to the left and the person's to the right, each at most
		// BUBBLE of it, so who said what reads from where it sits.
		const col = Math.max(240, this.width - 2 * SPACE.md);
		const said = { working: 'Working…', blocked: 'Waiting for you', done: 'Done', idle: 'Ready' };
		// Background work older than TASK_HOURS lost its notification (a
		// restart ends what it ran): it is not running any more.
		const tasks = [...this.tasks.values()].filter((x) => Date.now() - x.at < TASK_HOURS * 3600e3);
		const offered = this.offered();

		const body = v_flex()
			.id('chat-items')
			.size_full()
			.overflow_y_scrollbar()
			.track_scroll(this.scroll)
			.px(SPACE.md)
			.pt(SPACE.md)
			.gap(SPACE.sm)
			.on_scroll_wheel((e, cx) => {
				// Up: reading back, so new messages stop pulling the view down.
				if (e.delta.y > 0 && this.follow) {
					this.follow = false;
					cx.notify();
				}
			})
			.on_size_change((size, cx) => {
				const w = size.width / (settings().zoom || 1);
				if (Math.abs(w - this.width) > 1) {
					this.width = w;
					cx.notify();
				}
			})
			.when(earlier, (e) =>
				e.child(
					h_flex()
						.id('chat-earlier')
						.justify_center()
						.text_size(TEXT.ui)
						.text_color(t.accent)
						.cursor_pointer()
						.on_click((_e, cx) => {
							this.follow = false;
							if (from > 0) this.shown += SHOWN;
							else this.loadEarlier(cx);
							cx.notify();
						})
						.child(from > 0 ? `Show earlier (${from} more)` : 'Show earlier'),
				),
			)
			.when(notice, (e) =>
				e.child(
					div()
						.py(SPACE.sm)
						.text_color(t.dim)
						.child(this.error ?? 'Reading the conversation…'),
				),
			)
			.children(
				rows.map((r) =>
					div()
						.id(`chat-r-${r.kind}-${r.i}`)
						.w_full()
						.child(this.row(t, r, col)),
				),
			)
			.when(live, (e) => e.child(this.liveRow(t)))
			.when(this.queued.length > 0, (e) => e.child(this.queuedView(t, col)))
			// The space under the last message, as the end itself: scrolling to
			// it then leaves nothing further down to scroll to.
			.child(div().id('chat-end').h(SPACE.md));

		// Under the text: what Claude is doing and what can be done about it on
		// the left; what to show, the model and Send on the right.
		const bar = h_flex()
			.h(SIZE.bar)
			.px(SPACE.md)
			.gap(SPACE.sm)
			.items_center()
			.text_size(TEXT.ui)
			.child(dot(t, status))
			.child(
				div()
					.flex_none()
					.text_color(status === 'blocked' ? t.blocked : t.dim)
					.child(status ? (said[status] ?? status) : 'Not running'),
			)
			.when(status === 'working', (e) =>
				e.child(this.button(t, 'chat-stop', 'Interrupt', () => this.keys('esc'))),
			)
			.when(this.attached > 0, (e) =>
				e.child(
					this.button(t, 'chat-unattach', `📎 ${this.attached} · Remove`, (_e, cx) => {
						// Claude's input holds them: clear it there.
						this.keys('ctrl+u');
						this.attached = 0;
						cx.notify();
					}),
				),
			)
			.when(!this.follow, (e) =>
				e.child(
					this.button(t, 'chat-latest', '↓ Latest', (_e, cx) => {
						this.follow = true;
						this.toBottom = true;
						cx.notify();
					}),
				),
			)
			.child(div().flex_1())
			// The context left and the usage limits, as the status line has them;
			// red when nearly spent.
			.when(Boolean(this.footer), (e) => {
				const f = this.footer;
				const level = (left) =>
					left === null ? t.dim : left <= 10 ? t.ansi1 : left <= 25 ? t.blocked : t.dim;
				return (
					e
						.when(f.context !== null, (e) =>
							e.child(
								div()
									.flex_none()
									.text_size(TEXT.meta)
									.text_color(level(100 - f.context))
									.child(`ctx ${f.context}%`),
							),
						)
						.when(f.five !== null, (e) =>
							e.child(
								div()
									.flex_none()
									.text_size(TEXT.meta)
									.text_color(level(f.five))
									.child(`5h ${f.five}%`),
							),
						)
						.when(f.week !== null, (e) =>
							e.child(
								div()
									.flex_none()
									.text_size(TEXT.meta)
									.text_color(level(f.week))
									.child(`wk ${f.week}%`),
							),
						)
						// The permission mode; a click moves to the next, as Shift+Tab does.
						.when(Boolean(f.mode), (e) =>
							e.child(
								this.button(t, 'chat-mode', f.mode, (_e, cx) => {
									this.keys('shift+tab');
									cx.timer.after(400, (cx) => this.poll(cx));
								}),
							),
						)
				);
			})
			.when(Boolean(this.model), (e) =>
				e.child(div().flex_none().text_color(t.dim).child(this.model)),
			)
			.child(
				div()
					.id('chat-send')
					.size(SIZE.control + 2)
					.flex()
					.flex_none()
					.items_center()
					.justify_center()
					.rounded_full()
					.bg(t.solid)
					.text_color(t.solid_foreground)
					.cursor_pointer()
					.hover((s) => s.opacity(0.85))
					.on_click((_e, cx) => this.send(cx))
					.child('↑'),
			);

		const composer = v_flex()
			.w_full()
			.rounded(RADIUS.card + 2)
			.border_1()
			.border_color(t.input)
			.bg(t.surface)
			.child(
				div().px(SPACE.sm).pt(SPACE.sm).child(Textarea.new(this.box).w_full().text_size(TEXT.body)),
			)
			.child(bar);

		return v_flex()
			.id('chat')
			.track_focus(this.handle)
			.size_full()
			.min_h(0)
			.bg(t.background)
			.text_color(t.foreground)
			.text_size(TEXT.body)
			.on_key_down((e, cx) => {
				// Cmd+F finds, Esc closes the finder, else interrupts Claude when
				// the box is empty, as Esc does in the terminal.
				if (e.key === 'f' && e.modifiers.platform) {
					cx.stop_propagation();
					this.openFind(cx);
				} else if ((e.key === 'up' || e.key === 'down') && !this.offered().length) {
					if (this.recallStep(e.key === 'up' ? 1 : -1, cx)) cx.stop_propagation();
				} else if (e.key === 'tab' && this.offered().length) {
					cx.stop_propagation();
					this.complete(this.offered()[0], cx);
				} else if (e.key === 'escape') {
					if (this.find) this.closeFind(cx);
					// A card up: Esc answers it as Esc does in the terminal (cancel).
					else if (this.card) {
						this.keys('esc');
						this.card = null;
						cx.notify();
					} else if (!this.box.value() && this.agent()?.status === 'working') this.keys('esc');
				}
			})
			.when(Boolean(this.find), (e) => e.child(this.findBar(t)))
			.child(
				div()
					.flex_1()
					.min_h(0)
					.relative()
					.child(body)
					.child(Scrollbar.vertical('chat-items').absolute().inset_0())
					// Over the conversation's foot rather than in line with it, so
					// typing "/" moves nothing.
					.when(offered.length > 0, (e) =>
						e.child(
							div()
								.absolute()
								.left(SPACE.md)
								.right(SPACE.md)
								.bottom(SPACE.xs)
								.child(this.slashView(t, offered).shadow_lg()),
						),
					),
			)
			.when(Boolean(this.card), (e) =>
				e.child(div().px(SPACE.md).pb(SPACE.sm).child(this.cardView(t))),
			)
			.when(tasks.length > 0, (e) =>
				e.child(div().px(SPACE.md).pb(SPACE.sm).child(this.tasksView(t, tasks))),
			)
			.child(div().px(SPACE.md).pb(SPACE.md).child(composer));
	}
}
