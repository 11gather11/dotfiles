// The commit graph of the repository being worked in, as VS Code's Git Graph
// draws it: a coloured lane per branch, curves where branches fork and merge,
// branch and tag labels on their commits, uncommitted changes on top.
// Read-only: a click shows a commit in the diff pane, a right-click on a
// commit with a branch shows what that branch adds over the base branch, as
// its pull request would.
//
// In place of rabeeh-ta/herdr-git-graph, whose lane layout it borrows
// (lanes.js): that mod is mostly actions (checkout, rebase, push, a
// repository list), and here the graph is only for reading what the
// harness's workers did.
import { div, PathBuilder, View } from 'gpui-kit';
import { h_flex, Scrollbar, v_virtual_list } from 'gpui-base';
import { shared, theme, settings, watchFolder } from 'herdr';
import { SPACE, TEXT, RADIUS, bar, spacer, button, badge, card, ago } from './lib/ui.js';
import { focusedPlace } from './lib/focus.js';
import { git, openDiff } from './lib/git.js';
import { layoutLanes } from './lanes.js';

const LIMIT = 400;
const ROW = 24;
const LANE = 12;
const PAD = 6;
const DOT = 8;
const SETTLE_MS = 500;
// The working tree's changes are looked at this often; refs are watched.
const STATUS_MS = 5000;
const UNCOMMITTED = 'uncommitted';
// Fields of a commit, NUL-separated: hash, parents, author time, refs, subject.
const FORMAT = '%H%x00%P%x00%at%x00%D%x00%s';

/**
 * The refs `--decorate=full` names on a commit, as labels.
 *
 * @param {string} text e.g. "HEAD -> refs/heads/main, refs/remotes/origin/main, tag: refs/tags/v1"
 * @returns {{ kind: 'branch' | 'remote' | 'tag', name: string, head?: boolean }[]}
 */
function parseRefs(text) {
	const out = [];
	for (let name of text ? text.split(', ') : []) {
		const head = name.startsWith('HEAD -> ');
		if (head) name = name.slice(8);
		if (name.startsWith('refs/heads/')) out.push({ kind: 'branch', name: name.slice(11), head });
		else if (name.startsWith('tag: refs/tags/')) out.push({ kind: 'tag', name: name.slice(15) });
		else if (name.startsWith('refs/remotes/') && !name.endsWith('/HEAD'))
			out.push({ kind: 'remote', name: name.slice(13) });
	}
	// A remote branch where its local one also is says nothing more.
	const local = new Set(out.filter((r) => r.kind === 'branch').map((r) => r.name));
	return out.filter((r) => r.kind !== 'remote' || !local.has(r.name.replace(/^[^/]+\//, '')));
}

/**
 * `git log -z --format=FORMAT` as commits.
 *
 * @param {string} text
 */
function parseLog(text) {
	const fields = text.split('\0');
	const commits = [];
	for (let i = 0; i + 4 < fields.length; i += 5) {
		const [hash, parents, time, refs, subject] = fields.slice(i, i + 5);
		const labels = parseRefs(refs);
		commits.push({
			hash: hash.replace(/^\n/, ''),
			parents: parents ? parents.split(' ') : [],
			time: Number(time) * 1000,
			labels,
			subject,
			head: labels.some((l) => l.head),
		});
	}
	return commits;
}

export default class Graph extends View {
	init(_props, cx) {
		this.where = null;
		this.root = null;
		this.on = null;
		this.base = null; // the branch others are compared against: main, master
		this.branch = null;
		this.commits = [];
		this.rows = [];
		this.lanes = 1;
		this.error = null;
		this.loading = false;
		this.again = false;
		this.watched = null;
		this.load(cx);
		cx.timer.every(STATUS_MS, (cx) => this.load(cx));
	}

	load(cx) {
		const { folder, on } = focusedPlace();
		const where = JSON.stringify([folder, on]);
		if (where !== this.where) {
			this.where = where;
			this.root = null;
			this.commits = [];
			this.rows = [];
			this.error = null;
		}
		if (!folder) return;
		if (this.loading) {
			this.again = true;
			return;
		}
		this.loading = true;
		cx.spawn(async (cx) => {
			try {
				const top = await git(folder, on, ['rev-parse', '--show-toplevel', '--git-common-dir']);
				if (where !== this.where) return;
				if (top.code !== 0) {
					this.error = 'Not a git repository';
					return;
				}
				const [root, common] = top.stdout.trim().split('\n');
				const run = (args) => git(root, on, args);
				const [log, status, branch, base] = await Promise.all([
					run([
						'log',
						'-z',
						// Not --all: other tools keep private refs (checkpoints) that
						// would show as orphan commits.
						'--branches',
						'--tags',
						'--remotes',
						'--ignore-missing',
						'HEAD',
						'--date-order',
						'--decorate=full',
						`-n${LIMIT}`,
						`--format=${FORMAT}`,
					]),
					run(['status', '--porcelain=v1', '-z', '--untracked-files=normal']),
					run(['branch', '--show-current']),
					run(['symbolic-ref', '--short', 'refs/remotes/origin/HEAD']),
				]);
				if (log.code !== 0) throw new Error(log.stderr.trim().split('\n').pop());
				if (where !== this.where) return;
				let commits = parseLog(log.stdout);
				const changed = status.stdout.split('\0').filter(Boolean).length;
				const head = commits.find((c) => c.head)?.hash;
				if (changed && head)
					commits = [
						{
							hash: UNCOMMITTED,
							parents: [head],
							dashed: true,
							labels: [],
							subject: `Uncommitted changes (${changed})`,
							time: null,
						},
						...commits,
					];
				const { rows, width } = layoutLanes(commits);
				this.root = root;
				this.on = on;
				this.commits = commits;
				this.rows = rows;
				this.lanes = width;
				this.branch = branch.stdout.trim() || null;
				// origin/main, or main where there is no remote.
				const remoteBase = base.code === 0 ? base.stdout.trim() : null;
				this.base = remoteBase?.replace(/^[^/]+\//, '') ?? 'main';
				this.error = null;
				this.watch(common.startsWith('/') ? common : `${root}/${common}`, cx);
			} catch (e) {
				if (where === this.where) this.error = String(e.message ?? e);
			} finally {
				this.loading = false;
				cx.notify();
				if (this.again) {
					this.again = false;
					this.load(cx);
				}
			}
		});
	}

	// The repository's git folder: a commit, checkout or fetch from any
	// terminal moves a ref there.
	watch(dir, cx) {
		if (this.on || this.watched === dir) return;
		this.watched = dir;
		cx.spawn(async (cx) => {
			try {
				while (this.watched === dir) {
					await watchFolder(dir);
					if (this.watched === dir) cx.timer.after(SETTLE_MS, (cx) => this.load(cx));
				}
			} catch {
				this.watched = null;
			}
		});
	}

	show(i) {
		const c = this.commits[i];
		if (!c) return;
		const where = { root: this.root, on: this.on };
		if (c.hash === UNCOMMITTED) openDiff({ ...where, kind: 'worktree' });
		else openDiff({ ...where, kind: 'commit', rev: c.hash, title: c.subject });
	}

	// What the commit's branch adds over the base branch, as its pull request
	// shows it. A commit without a branch label has none to compare.
	showBranch(i) {
		const c = this.commits[i];
		const label = c?.labels.find((l) => l.kind !== 'tag' && l.name !== this.base);
		if (!label) return;
		openDiff({ root: this.root, on: this.on, kind: 'range', base: this.base, head: label.name });
	}

	// ── drawing ──

	colors(t) {
		return [
			t.ansi4,
			t.ansi2,
			t.ansi5,
			t.ansi3,
			t.ansi6,
			t.ansi1,
			t.ansi12,
			t.ansi10,
			t.ansi13,
			t.ansi11,
		];
	}

	graphWidth() {
		return PAD * 2 + this.lanes * LANE;
	}

	// The lines through one row, one stroked path per colour, and the commit's dot.
	cell(t, i) {
		const row = this.rows[i];
		const commit = this.commits[i];
		const colors = this.colors(t);
		const x = (lane) => PAD + lane * LANE + LANE / 2;
		const y = (v) => v * ROW;
		const paths = new Map();
		for (const [a, ya, b, yb, c, dashed] of row.segments) {
			const color = dashed ? t.dim : colors[c % colors.length];
			const key = `${color}${dashed ? '-' : ''}`;
			let p =
				paths.get(key)?.p ??
				(dashed ? PathBuilder.stroke(1.5).dash_array([3, 3]) : PathBuilder.stroke(1.5));
			p = p.move_to(x(a), y(ya));
			if (a === b) p = p.line_to(x(b), y(yb));
			else {
				// An S-curve between lanes, as Git Graph draws a fork or a merge.
				const mid = (y(ya) + y(yb)) / 2;
				p = p.cubic_bezier_to(x(b), y(yb), x(a), mid, x(b), mid);
			}
			paths.set(key, { p, color });
		}
		const color = commit.hash === UNCOMMITTED ? t.dim : colors[row.lane % colors.length];
		const dot = div()
			.absolute()
			.left(x(row.lane) - DOT / 2)
			.top(ROW / 2 - DOT / 2)
			.size(DOT)
			.rounded(DOT);
		return (
			div()
				.relative()
				.flex_none()
				.w(this.graphWidth())
				.h(ROW)
				.overflow_hidden()
				.children(
					[...paths.values()].map(({ p, color }) =>
						window.paint_path(p.build(), color).absolute().top(0).left(0).size_full(),
					),
				)
				// HEAD and uncommitted changes are rings, as in Git Graph.
				.child(
					commit.head || commit.hash === UNCOMMITTED
						? dot.bg(t.background).border_2().border_color(color)
						: dot.bg(color),
				)
		);
	}

	label(t, l, color) {
		const edge = l.kind === 'tag' ? t.ansi3 : color;
		return div()
			.flex_none()
			.max_w(140)
			.truncate()
			.px(SPACE.xs + 1)
			.rounded(RADIUS.control - 2)
			.border_1()
			.border_color(edge)
			.text_size(TEXT.meta)
			.when(Boolean(l.head), (e) => e.bg(color).text_color(t.background).font_semibold())
			.when(!l.head, (e) => e.text_color(l.kind === 'remote' ? t.muted : t.foreground))
			.child(l.kind === 'tag' ? `◆ ${l.name}` : l.name);
	}

	row(t, i, selected) {
		const c = this.commits[i];
		const color = this.colors(t)[this.rows[i].lane % this.colors(t).length];
		const merge = c.parents.length > 1;
		return h_flex()
			.h(ROW)
			.w_full()
			.pr(SPACE.sm)
			.gap(SPACE.sm)
			.items_center()
			.rounded(RADIUS.control)
			.text_size(TEXT.ui)
			.when(selected, (e) => e.bg(t.selected))
			.when(!selected, (e) => e.hover((s) => s.bg(t.hover)))
			.child(this.cell(t, i))
			.children(c.labels.map((l) => this.label(t, l, color)))
			.child(
				div()
					.flex_1()
					.min_w(0)
					.truncate()
					// Merges are muted, as in Git Graph: their content is in the lane.
					.text_color(c.hash === UNCOMMITTED ? t.muted : merge ? t.dim : t.foreground)
					.child(c.subject),
			)
			.when(c.time !== null, (e) =>
				e.child(div().flex_none().text_size(TEXT.meta).text_color(t.dim).child(ago(c.time))),
			);
	}

	// The row the diff pane shows, if it shows one of this repository's.
	shownIndex() {
		const s = shared('diff.target');
		if (!s || s.root !== this.root) return -1;
		if (s.kind === 'worktree') return this.commits.findIndex((c) => c.hash === UNCOMMITTED);
		if (s.kind === 'commit') return this.commits.findIndex((c) => c.hash === s.rev);
		return this.commits.findIndex((c) => c.labels.some((l) => l.name === s.head));
	}

	render(cx) {
		const t = theme();
		const { folder, on } = focusedPlace();
		if (JSON.stringify([folder, on]) !== this.where) this.load(cx);
		const shown = this.shownIndex();
		const head = bar(t, 'graph-bar')
			.child(div().flex_none().font_semibold().child('Graph'))
			.when(Boolean(this.branch), (e) => e.child(badge(t, this.branch)))
			.child(spacer())
			.child(button(t, 'graph-refresh', this.loading ? '…' : '↻', (_e, cx) => this.load(cx)));
		const body = !this.commits.length
			? div()
					.p(SPACE.md)
					.text_size(TEXT.ui)
					.text_color(t.dim)
					.child(this.error ?? (this.root ? 'No commits' : this.loading ? 'Reading…' : 'No folder'))
			: div()
					.flex_1()
					.min_h(0)
					.relative()
					.child(
						v_virtual_list(
							'graph-rows',
							this.commits.length,
							ROW,
							(i) => this.commits[i]?.hash ?? String(i),
							(range) => {
								const out = [];
								for (let i = range.start; i < range.end; i++) out.push(this.row(t, i, i === shown));
								return out;
							},
						)
							.on_item_click((key) => this.show(this.commits.findIndex((c) => c.hash === key)))
							.on_item_secondary_click((key) =>
								this.showBranch(this.commits.findIndex((c) => c.hash === key)),
							)
							.size_full()
							.px(SPACE.xs),
					)
					.child(Scrollbar.vertical('graph-rows').viewport_from_layout().absolute().inset_0());
		return card(t)
			.child(head)
			.child(body)
			.child(
				div()
					.flex_none()
					.px(SPACE.md)
					.py(SPACE.xs)
					.border_t(1)
					.border_color(t.border)
					.text_size(TEXT.meta)
					.text_color(t.dim)
					.child(`Click: the commit · Right-click a branch: vs ${this.base ?? 'main'}`),
			);
	}
}
