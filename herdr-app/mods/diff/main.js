// A diff to read, beside the terminals: every changed file one under another,
// its lines tinted added or removed, coloured as code, and the words that
// changed within an edited line marked. Read-only.
//
// What it shows comes from shared('diff.target'), set by openDiff in
// lib/git.js: uncommitted changes, a commit, or a branch against its base.
// Uncommitted changes follow the working tree as it changes.
import { View, div } from 'gpui-kit';
import { h_flex, Scrollbar, v_virtual_list, VirtualListScrollHandle } from 'gpui-base';
import { shared, theme, settings, watchFolder } from 'herdr';
import {
	SPACE,
	TEXT,
	bar,
	title,
	button,
	badge,
	counts,
	changeMark,
	pathLabel,
	sheet,
} from './lib/ui.js';
import { git } from './lib/git.js';
import { languageOf, tokens, changedSpan, marked } from './highlight.js';

const LINE_H = 20;
const FILE_H = 30;
// A monospace character's width at TEXT.ui, for the width the longest line needs.
const CHAR_W = 7.3;
// The gutter: two line numbers and the sign.
const GUTTER = 40 + 40 + 16 + SPACE.sm * 3;
// Past these the rest is cut: every row is kept in memory, and a diff this
// long is read on GitHub, not here.
const MAX_ROWS = 30000;
const MAX_LINE = 2000;
const MAX_UNTRACKED = 50;
const PREFIX = ['--src-prefix=a/', '--dst-prefix=b/'];
// Reads after a change in the working tree wait this long for the rest.
const SETTLE_MS = 400;

// Text draws a tab as nothing: pad each to the next 4-column stop.
const untab = (text) =>
	text.replace(/[^\t]*\t/g, (s) => s.slice(0, -1).padEnd(s.length - 1 - ((s.length - 1) % 4) + 4));

/** Whether two targets show the same thing (a new seq or file alone is not a new diff). */
const sameDiff = (a, b) =>
	Boolean(a && b) &&
	['root', 'on', 'kind', 'rev', 'base', 'head'].every((k) => (a[k] ?? null) === (b[k] ?? null));

/**
 * The git command that prints a target's diff.
 *
 * @param {import('./lib/git.js').DiffTarget} target
 * @returns {string[]}
 */
function diffArgs(target) {
	// The a/ and b/ prefixes parseDiff reads, whatever diff.mnemonicPrefix says.
	const common = ['--no-color', '--no-ext-diff', '--no-textconv', '-M', ...PREFIX];
	if (target.kind === 'commit') return ['show', '--format=', ...common, target.rev];
	if (target.kind === 'range') return ['diff', ...common, `${target.base}...${target.head}`];
	return ['diff', ...common, 'HEAD'];
}

/**
 * Splits `git diff` output into files, each with its lines numbered.
 *
 * @param {string} text
 * @returns {{ path: string, from: string | null, status: string, add: number, del: number, note: string | null, lines: any[] }[]}
 */
export function parseDiff(text) {
	const files = [];
	let file = null;
	let old = 0;
	let now = 0;
	for (const line of text.split('\n')) {
		if (line.startsWith('diff --git ')) {
			// The b/ path, until a rename or /dev/null line says better.
			const m = / b\/(.*)$/.exec(line);
			file = {
				path: m?.[1] ?? line,
				from: null,
				status: 'M',
				add: 0,
				del: 0,
				note: null,
				lines: [],
			};
			files.push(file);
			continue;
		}
		if (!file) continue;
		if (line.startsWith('@@')) {
			const m = /^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@ ?(.*)$/.exec(line);
			old = Number(m?.[1] ?? 0);
			now = Number(m?.[2] ?? 0);
			file.lines.push({ kind: '@', text: m?.[3] ?? '', at: now });
			continue;
		}
		const sign = line[0];
		if (file.lines.length && (sign === '+' || sign === '-' || sign === ' ')) {
			const body = untab(line.slice(1)).slice(0, MAX_LINE);
			if (sign === '+') {
				file.add++;
				file.lines.push({ kind: '+', old: null, now: now++, text: body });
			} else if (sign === '-') {
				file.del++;
				file.lines.push({ kind: '-', old: old++, now: null, text: body });
			} else file.lines.push({ kind: ' ', old: old++, now: now++, text: body });
			continue;
		}
		if (line.startsWith('new file')) file.status = 'A';
		else if (line.startsWith('deleted file')) file.status = 'D';
		else if (line.startsWith('rename from ')) {
			file.from = line.slice(12);
			file.status = 'R';
		} else if (line.startsWith('rename to ')) file.path = line.slice(10);
		else if (line.startsWith('--- a/') && file.status === 'D') file.path = line.slice(6);
		else if (line.startsWith('Binary files')) file.note = 'Binary file';
	}
	return files;
}

/**
 * Colours each line and marks, in each run of removed lines followed by
 * added ones, what changed between the pairs.
 *
 * @param {{ path: string, lines: any[] }} file
 */
function dress(file) {
	const lang = languageOf(file.path);
	const ls = file.lines;
	for (let i = 0; i < ls.length;) {
		if (ls[i].kind !== '-') {
			i++;
			continue;
		}
		let j = i;
		while (j < ls.length && ls[j].kind === '-') j++;
		let k = j;
		while (k < ls.length && ls[k].kind === '+') k++;
		// Pair the n-th removed line with the n-th added one.
		for (let n = 0; n < Math.min(j - i, k - j); n++) {
			const span = changedSpan(ls[i + n].text, ls[j + n].text);
			if (span) [ls[i + n].span, ls[j + n].span] = span;
		}
		i = k;
	}
	for (const l of ls) if (l.kind !== '@') l.pieces = marked(tokens(l.text, lang), l.span ?? null);
}

export default class Diff extends View {
	init(_props, cx) {
		this.target = null;
		this.seq = null;
		this.files = [];
		this.rows = [];
		this.sizes = [];
		this.folded = new Set();
		this.error = null;
		this.loading = false;
		this.width = 0;
		this.scroll = VirtualListScrollHandle.new();
		this.pending = null; // a file to scroll to once its rows are there
		this.take(cx);
	}

	// Takes up the target openDiff left, once per click.
	take(cx) {
		const next = shared('diff.target');
		if (!next || next.seq === this.seq) return;
		this.seq = next.seq;
		this.pending = next.file ?? null;
		if (sameDiff(next, this.target)) {
			this.reveal();
			return;
		}
		this.target = next;
		this.files = [];
		this.rows = [];
		this.sizes = [];
		this.folded.clear();
		this.load(cx);
		this.follow(cx);
	}

	load(cx) {
		const target = this.target;
		if (!target || this.loading) return;
		this.loading = true;
		cx.spawn(async (cx) => {
			try {
				const r = await git(target.root, target.on, diffArgs(target));
				if (r.code !== 0) throw new Error(r.stderr.trim().split('\n').pop() || 'git diff failed');
				const files = parseDiff(r.stdout);
				if (target.kind === 'worktree') files.push(...(await this.untracked(target)));
				if (target !== this.target) return;
				files.sort((a, b) => a.path.localeCompare(b.path));
				for (const f of files) dress(f);
				this.files = files;
				this.error = null;
				this.lay();
				this.reveal();
			} catch (e) {
				if (target === this.target) this.error = String(e.message ?? e);
			} finally {
				this.loading = false;
				cx.notify();
			}
		});
	}

	// Untracked files as added ones, which `git diff HEAD` leaves out.
	async untracked(target) {
		const r = await git(target.root, target.on, [
			'ls-files',
			'--others',
			'--exclude-standard',
			'-z',
		]);
		const paths = r.stdout.split('\0').filter(Boolean).slice(0, MAX_UNTRACKED);
		const out = [];
		for (const path of paths) {
			// --no-index exits 1 when the files differ, which they always do.
			const d = await git(target.root, target.on, [
				'diff',
				'--no-index',
				'--no-color',
				...PREFIX,
				'--',
				'/dev/null',
				path,
			]);
			const [file] = parseDiff(d.stdout);
			if (file) out.push({ ...file, path, status: 'A' });
		}
		return out;
	}

	// Re-reads uncommitted changes as the working tree changes, until another
	// target replaces this one. A commit or a range never changes.
	follow(cx) {
		const target = this.target;
		if (target.kind !== 'worktree' || target.on) return;
		cx.spawn(async (cx) => {
			try {
				while (target === this.target) {
					await watchFolder(target.root);
					if (target !== this.target) break;
					cx.timer.after(SETTLE_MS, (cx) => this.load(cx));
				}
			} catch {
				// A folder that cannot be watched leaves the diff as first read.
			}
		});
	}

	// The rows the list draws: each file's header, then its lines unless folded.
	lay() {
		const rows = [];
		let longest = 0;
		for (const f of this.files) {
			rows.push({ kind: 'file', file: f });
			if (this.folded.has(f.path)) continue;
			if (f.note) rows.push({ kind: 'note', text: f.note });
			for (const l of f.lines) {
				if (rows.length >= MAX_ROWS) break;
				rows.push(l);
				longest = Math.max(longest, l.text.length);
			}
		}
		if (rows.length >= MAX_ROWS)
			rows.push({ kind: 'note', text: 'The rest is cut: this diff is too long to show here' });
		this.rows = rows;
		this.sizes = rows.map((r) => (r.kind === 'file' ? FILE_H : LINE_H));
		this.width = GUTTER + longest * CHAR_W + SPACE.lg;
	}

	reveal() {
		if (!this.pending) return;
		const i = this.rows.findIndex((r) => r.kind === 'file' && r.file.path === this.pending);
		if (i < 0) return;
		this.scroll.scroll_to_item(i, 'top');
		this.pending = null;
	}

	fold(path, cx) {
		if (this.folded.has(path)) this.folded.delete(path);
		else this.folded.add(path);
		this.lay();
		cx.notify();
	}

	// ── rows ──

	fileRow(t, f) {
		return h_flex()
			.id(`file-${f.path}`)
			.h(FILE_H)
			.w_full()
			.flex_none()
			.px(SPACE.sm)
			.gap(SPACE.sm)
			.items_center()
			.bg(t.raised)
			.border_t(1)
			.border_color(t.border)
			.cursor_pointer()
			.text_size(TEXT.ui)
			.child(
				div()
					.w(12)
					.flex_none()
					.text_color(t.dim)
					.child(this.folded.has(f.path) ? '›' : '⌄'),
			)
			.child(changeMark(t, f.status))
			.child(pathLabel(t, f.path, { from: f.from, strong: true }))
			.child(counts(t, f.add, f.del));
	}

	lineRow(t, l) {
		if (l.kind === 'note')
			return div().h(LINE_H).px(GUTTER).flex_none().text_color(t.dim).child(l.text);
		if (l.kind === '@')
			// A hunk's start: where it is, and the enclosing function git names.
			return h_flex()
				.h(LINE_H)
				.w_full()
				.flex_none()
				.pl(SPACE.sm)
				.gap(SPACE.sm)
				.bg(t.ansi4 + '14')
				.text_color(t.dim)
				.child(
					div()
						.w(80 + SPACE.sm)
						.flex_none()
						.text_right()
						.child('⋯'),
				)
				.child(
					div()
						.flex_none()
						.child(l.text ? `line ${l.at} · ${l.text}` : `line ${l.at}`),
				);
		const add = l.kind === '+';
		const del = l.kind === '-';
		const tint = add ? t.ansi2 : del ? t.ansi1 : null;
		const syntax = {
			keyword: t.ansi5,
			string: t.ansi2,
			comment: t.dim,
			function: t.ansi4,
			type: t.ansi3,
			number: t.ansi1,
		};
		return h_flex()
			.h(LINE_H)
			.w_full()
			.flex_none()
			.pl(SPACE.sm)
			.gap(SPACE.sm)
			.when(Boolean(tint), (e) => e.bg(tint + '1c'))
			.child(
				div()
					.w(40)
					.flex_none()
					.text_right()
					.text_color(t.dim)
					.child(l.old === null ? '' : String(l.old)),
			)
			.child(
				div()
					.w(40)
					.flex_none()
					.text_right()
					.text_color(t.dim)
					.child(l.now === null ? '' : String(l.now)),
			)
			.child(
				div()
					.w(16)
					.flex_none()
					.text_color(tint ?? t.dim)
					.child(add ? '+' : del ? '−' : ''),
			)
			.child(
				h_flex()
					.flex_none()
					.children(
						(l.pieces ?? [{ text: l.text, kind: null, em: false }]).map((p) =>
							div()
								.flex_none()
								.text_color(p.kind ? syntax[p.kind] : t.foreground)
								.when(p.em && Boolean(tint), (e) => e.bg(tint + '55').rounded(2))
								.child(p.text || ' '),
						),
					),
			);
	}

	// ── the pane ──

	heading(t) {
		const target = this.target;
		if (!target) return title(t, 'Diff');
		const repo = target.root.split('/').pop();
		if (target.kind === 'commit') return title(t, target.rev.slice(0, 8), target.title ?? repo);
		if (target.kind === 'range') return title(t, `${target.base}…${target.head}`, repo);
		return title(t, 'Uncommitted', repo);
	}

	render(cx) {
		this.take(cx);
		const t = theme();
		const add = this.files.reduce((n, f) => n + f.add, 0);
		const del = this.files.reduce((n, f) => n + f.del, 0);
		const head = bar(t, 'diff-bar')
			.child(this.heading(t))
			.when(this.files.length > 0, (e) =>
				e
					.child(badge(t, `${this.files.length} ${this.files.length === 1 ? 'file' : 'files'}`))
					.child(counts(t, add, del)),
			)
			.when(this.files.length > 1, (e) =>
				e.child(
					// Folds every file to its header, or opens them all again.
					button(t, 'diff-fold', this.folded.size ? 'Expand' : 'Collapse', (_e, cx) => {
						if (this.folded.size) this.folded.clear();
						else for (const f of this.files) this.folded.add(f.path);
						this.lay();
						cx.notify();
					}),
				),
			)
			.child(button(t, 'diff-refresh', this.loading ? '…' : '↻', (_e, cx) => this.load(cx)));

		let body;
		const empty = (text) => div().p(SPACE.lg).text_color(t.dim).child(text);
		if (!this.target) body = empty('Pick a file in Changes to see its diff');
		else if (this.error) body = empty(this.error);
		else if (!this.rows.length) body = empty(this.loading ? 'Reading…' : 'No changes');
		else
			body = div()
				.flex_1()
				.min_h(0)
				.relative()
				.font_family(settings().font_family ?? 'JetBrains Mono')
				.text_size(TEXT.ui)
				.child(
					div()
						.id('diff-x')
						.size_full()
						.overflow_x_scrollbar()
						.child(
							div()
								.w_full()
								.min_w(this.width)
								.h_full()
								.child(
									v_virtual_list(
										'diff-rows',
										this.rows.length,
										this.sizes,
										(i) =>
											this.rows[i]?.kind === 'file' ? `file:${this.rows[i].file.path}` : String(i),
										(range) =>
											this.rows
												.slice(range.start, range.end)
												.map((r) =>
													r.kind === 'file' ? this.fileRow(t, r.file) : this.lineRow(t, r),
												),
									)
										// A file's header folds it (rows take no clicks of their own).
										.on_item_click((key, cx) => {
											if (key.startsWith('file:')) this.fold(key.slice(5), cx);
										})
										.track_scroll(this.scroll)
										.size_full(),
								),
						),
				)
				.child(Scrollbar.vertical('diff-rows').viewport_from_layout().absolute().inset_0());

		return sheet(t).child(head).child(body);
	}
}
