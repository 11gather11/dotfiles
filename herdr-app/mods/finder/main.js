// Search the focused pane's repository: files by name (fuzzy), then lines of
// text (ripgrep, literal and smart-case). Enter or a click opens the result in
// the viewer, at the matching line for a text hit.
//
// The editor-side search reading code wants, for a setup where the agents
// write the code and it is mostly read: one box for both, as typing a path
// fragment and typing an identifier are the same gesture.
import { View, div, svg } from 'gpui-kit';
import { v_flex, h_flex, InputState, Input } from 'gpui-base';
import { exec, theme, props, closeOverlay, openOverlay } from 'herdr';
import { SIZE, SPACE, TEXT, RADIUS } from './lib/ui.js';
import { focusedFolder } from './lib/focus.js';

// Typing pauses this long before ripgrep runs, so a word is searched once
// rather than once per letter.
const TEXT_DELAY = 180;
// What a list shows at most; past this the query is too loose to read anyway.
const MAX_FILES = 30;
const MAX_TEXT = 150;
// Text search needs this much of a query, or it lists half the repository.
const MIN_TEXT = 3;
// The results list's height (px at zoom 1).
const RESULTS_H = 440;

const folder = focusedFolder;

/**
 * How well `query` matches `path` as a subsequence, or -1 when it does not.
 * Consecutive letters, letters at the start of a word, and a match that ends
 * in the file's own name score higher; a shorter path breaks ties.
 *
 * @param {string} query lowercase, spaces removed
 * @param {string} path
 * @returns {number}
 * @example
 * fuzzy("mainjs", "herdr-app/mods/viewer/main.js") > fuzzy("mainjs", "src/m/a/i/n.json") // => true
 */
function fuzzy(query, path) {
	const p = path.toLowerCase();
	let qi = 0,
		score = 0,
		last = -1;
	for (let i = 0; i < p.length && qi < query.length; i++) {
		if (p[i] !== query[qi]) continue;
		score += i === last + 1 ? 5 : 1; // runs of letters
		if (i === 0 || '/._- '.includes(p[i - 1])) score += 3; // start of a word
		last = i;
		qi++;
	}
	if (qi < query.length) return -1;
	if (last >= p.lastIndexOf('/') + 1) score += 10; // ends in the file's name
	return score - p.length * 0.01;
}

export default class Finder extends View {
	init(_props, cx) {
		this.query = '';
		this.root = null;
		this.files = [];
		this.text = [];
		this.searching = false;
		this.at = 0;
		this.handle = cx.focus_handle();
		this.input = InputState.new({ placeholder: 'Search files and text…' });
		this.input.on('change', (_e, cx) => {
			this.query = this.input.value();
			this.at = 0;
			this.searchText(cx);
			cx.notify();
		});
		this.input.on('submit', () => this.open(this.results()[this.at]));
		this.input.focus();
		this.loadFiles(cx);
	}

	// Every file git would show, tracked or not, minus what it ignores. Read
	// once per opening: the finder lives as long as one search.
	loadFiles(cx) {
		const cwd = folder();
		if (!cwd) return;
		cx.spawn(async (cx) => {
			const top = await exec('git', ['rev-parse', '--show-toplevel'], { cwd }).catch(() => null);
			this.root = top?.code === 0 ? top.stdout.trim() : cwd;
			const ls = await exec('git', ['ls-files', '--cached', '--others', '--exclude-standard'], {
				cwd: this.root,
			}).catch(() => null);
			this.files = ls?.code === 0 ? ls.stdout.split('\n').filter(Boolean) : [];
			cx.notify();
		});
	}

	// ripgrep for the query once typing pauses; a reply to an older query is
	// dropped, as the box has moved on.
	searchText(cx) {
		const query = this.query.trim();
		this.text = [];
		if (query.length < MIN_TEXT || !this.root) return;
		cx.timer.after(TEXT_DELAY, (cx) => {
			if (this.query.trim() !== query) return;
			this.searching = true;
			cx.notify();
			cx.spawn(async (cx) => {
				const r = await exec(
					'rg',
					[
						'--line-number',
						'--no-heading',
						'--color=never',
						'--smart-case',
						'--fixed-strings',
						'--max-count=5',
						'--max-columns=300',
						'--max-filesize=1M',
						'--',
						query,
					],
					{ cwd: this.root, timeout: 10000 },
				).catch(() => null);
				if (this.query.trim() !== query) return;
				this.searching = false;
				this.text = (r?.stdout ?? '')
					.split('\n')
					.filter(Boolean)
					.slice(0, MAX_TEXT)
					.map((l) => {
						// path:line:text, where the path holds no colon in practice
						const m = /^([^:]+):(\d+):(.*)$/.exec(l);
						return m && { kind: 'text', path: m[1], line: Number(m[2]), text: m[3].trim() };
					})
					.filter(Boolean);
				cx.notify();
			});
		});
	}

	/** The selectable rows: file matches, then text matches. */
	results() {
		const q = this.query.toLowerCase().replace(/\s+/g, '');
		if (!q) return [];
		const files = this.files
			.map((path) => ({ kind: 'file', path, score: fuzzy(q, path) }))
			.filter((f) => f.score >= 0)
			.sort((a, b) => b.score - a.score)
			.slice(0, MAX_FILES);
		return [...files, ...this.text];
	}

	open(hit) {
		if (!hit || !this.root) return;
		closeOverlay(props().overlay);
		openOverlay({
			mod: 'viewer',
			kind: 'dialog',
			width: 0.8,
			height: 0.85,
			props: { file: `${this.root}/${hit.path}`, line: hit.kind === 'text' ? hit.line : null },
		});
	}

	row(t, hit, i) {
		const on = i === this.at;
		const slash = hit.path.lastIndexOf('/');
		const name = hit.path.slice(slash + 1);
		const dir = slash >= 0 ? hit.path.slice(0, slash) : '';
		return h_flex()
			.id(`find-${i}`)
			.h(hit.kind === 'text' ? 40 : 26)
			.flex_none()
			.px(10)
			.gap(SPACE.md)
			.items_center()
			.rounded(RADIUS.control)
			.cursor_pointer()
			.when(on, (e) => e.bg(t.selected))
			.when(!on, (e) => e.hover((s) => s.bg(t.hover)))
			.on_click(() => this.open(hit))
			.child(
				hit.kind === 'file'
					? h_flex()
							.flex_1()
							.min_w(0)
							.gap(SPACE.sm)
							.child(div().flex_none().text_color(t.foreground).child(name))
							.child(div().min_w(0).truncate().text_size(TEXT.meta).text_color(t.dim).child(dir))
					: v_flex()
							.flex_1()
							.min_w(0)
							.child(
								h_flex()
									.gap(SPACE.sm)
									.text_size(TEXT.meta)
									.child(div().flex_none().text_color(t.muted).child(name))
									.child(div().flex_none().text_color(t.dim).child(`:${hit.line}`))
									.child(div().min_w(0).truncate().text_color(t.dim).child(dir)),
							)
							.child(div().truncate().text_color(t.foreground).child(hit.text)),
			);
	}

	render() {
		const t = theme();
		const rows = this.results();
		const files = rows.filter((r) => r.kind === 'file').length;
		const head = (label, n) =>
			h_flex()
				.h(SIZE.row)
				.px(10)
				.gap(SPACE.sm)
				.items_center()
				.text_size(TEXT.meta)
				.text_color(t.dim)
				.child(label.toUpperCase())
				.child(String(n));
		const repo = this.root?.split('/').pop() ?? '';
		return v_flex()
			.id('finder')
			.track_focus(this.handle)
			.size_full()
			.min_h(0)
			.p(14)
			.gap(SPACE.sm)
			.bg(t.popover)
			.text_size(TEXT.body)
			.on_key_down((e, cx) => {
				if (e.key === 'down') this.at = Math.min(this.at + 1, Math.max(0, rows.length - 1));
				else if (e.key === 'up') this.at = Math.max(0, this.at - 1);
				else return;
				cx.stop_propagation();
				cx.notify();
			})
			.child(
				h_flex()
					.h(SIZE.bar)
					.flex_none()
					.px(10)
					.gap(SPACE.sm)
					.items_center()
					.rounded(RADIUS.control)
					.border_1()
					.border_color(t.accent)
					.bg(t.background)
					.child(svg('mods/workspace-chrome/search.svg').size(14).text_color(t.dim))
					.child(
						Input.new(this.input).flex_1().h_full().text_size(TEXT.body).text_color(t.foreground),
					)
					.child(div().flex_none().text_size(TEXT.meta).text_color(t.dim).child(repo)),
			)
			.child(
				v_flex()
					.id('finder-results')
					// A popup sizes to its content, so the list states its own
					// height rather than taking what is left.
					.h(RESULTS_H)
					.min_h(0)
					.overflow_y_scrollbar()
					.when(!this.query.trim(), (e) =>
						e.child(
							div()
								.p(10)
								.text_color(t.dim)
								.child(`Type a file name or text to find in ${repo || 'this folder'}`),
						),
					)
					.when(files > 0, (e) => e.child(head('Files', files)))
					.children(rows.slice(0, files).map((hit, i) => this.row(t, hit, i)))
					.when(this.query.trim().length >= MIN_TEXT, (e) =>
						e.child(head(this.searching ? 'Text…' : 'Text', rows.length - files)),
					)
					.children(rows.slice(files).map((hit, i) => this.row(t, hit, files + i))),
			);
	}
}
