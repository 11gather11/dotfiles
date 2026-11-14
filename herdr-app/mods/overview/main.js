// Every running harness at once, as pictures drawn one way: cards joined by
// curved arrows.
//
// Flow: a band per repository, its work flowing left to right through Ready,
// Working, PR · CI, Queue and Landed, a worker joined to its pull request and
// that to its place in the queue. Specs: a spec's tickets, each right of what
// it waits on (specs.js). A card opens what it stands for: a worker's screen,
// a branch's diff, an issue, a landed pull request.
//
// Flow is drawn from the snapshots harness-list shares (harness.snaps), so it
// asks nothing of GitHub; Specs reads a spec's graph when it is picked.
// Opened over the window (mod.json's overlay): cmd-shift-o, or a click on the
// sidebar's Harness heading.
import { View, div, PathBuilder } from 'gpui-kit';
import { v_flex, h_flex } from 'gpui-base';
import { shared, theme, settings, terminals, run, exec, props, closeOverlay } from 'herdr';
import {
	SPACE,
	TEXT,
	RADIUS,
	bar,
	title,
	button,
	dot,
	sheet,
	scroller,
	ago,
	segmented,
	row,
	badge,
	programIcon,
} from './lib/ui.js';
import { runningHarnesses } from './lib/harness.js';
import { openDiff } from './lib/git.js';
import { openBeside } from './lib/pane.js';
import { specsOf, readSpec, layoutSpec, stateOf } from './specs.js';

// A card, and the room between cards, in both pictures.
const NODE_H = 46;
const ROW_GAP = 14;
const COL_GAP = 56;
// Flow: its columns, the repository's label before them, landings shown.
const COLUMNS = ['Ready', 'Working', 'PR · CI', 'Queue', 'Landed'];
const LABEL_W = 150;
const LANDED_SHOWN = 4;
// Specs: a ticket's width and the list of specs beside the picture.
const NODE_W = 230;
const LIST_W = 240;

/**
 * A worker's state as a badge: what it says and its tone.
 *
 * @param {any} w a worker of the snapshot
 * @param {boolean} needs it waits on the person
 */
function workerBadge(w, needs) {
	if (needs) return ['needs you', 'blocked'];
	if (w.state === 'working' || w.state === 'busy') return ['working', 'working'];
	if (w.state === 'blocked' || w.state === 'stuck') return [w.state, 'blocked'];
	return [w.state ?? 'idle', 'neutral'];
}

/**
 * A repository's band: the rows its cards sit on. A worker and what came of
 * it share a row (its PR, the PR's place in the queue); a queued PR no
 * worker holds has a row of its own. Ready tickets and landings stack in
 * their own columns.
 *
 * @param {any} snap a harness-status snapshot
 */
export function bandOf(snap) {
	const queue = snap.queue ?? [];
	const used = new Set();
	const rows = (snap.workers ?? []).map((w) => {
		const q = w.pr ? queue.findIndex((p) => p.number === w.pr.number) : -1;
		if (q >= 0) used.add(q);
		return { worker: w, pr: w.pr ?? null, q };
	});
	queue.forEach((p, q) => {
		if (!used.has(q)) rows.push({ worker: null, pr: p, q });
	});
	const ready = [];
	for (const s of snap.specs ?? []) {
		for (const r of s.ready ?? [])
			ready.push({ n: r.ticket, title: r.title, note: `spec #${s.spec}`, waits: false });
		for (const w of s.waiting ?? [])
			ready.push({
				n: w.number,
				title: null,
				note: `after ${w.on.map((m) => `#${m}`).join(' ')}`,
				waits: true,
			});
	}
	const landed = (snap.landed ?? []).slice(0, LANDED_SHOWN);
	const needs = new Set((snap.attention ?? []).map((a) => a.worker).filter(Boolean));
	return {
		rows,
		ready,
		landed,
		needs,
		height: Math.max(rows.length, ready.length, landed.length, 1),
	};
}

export default class Overview extends View {
	init() {
		this.width = 1200;
		this.view = 'flow'; // or 'specs'
		this.specs = null; // [{ repo, n }], once looked for
		this.picked = null; // `${repo}#${n}`
		this.graphs = new Map(); // `${repo}#${n}` => { data } | { error } | { loading: true }
	}

	// The specs every running harness has started, looked for once the tab
	// is first shown; the first is shown.
	findSpecs(cx) {
		this.specs = [];
		cx.spawn(async (cx) => {
			const repos = [...runningHarnesses().keys()].sort();
			const found = await Promise.all(
				repos.map(async (repo) => (await specsOf(repo)).map((n) => ({ repo, n }))),
			);
			this.specs = found.flat();
			if (this.specs.length) this.pick(this.specs[0], cx);
			cx.notify();
		});
	}

	pick({ repo, n }, cx) {
		const key = `${repo}#${n}`;
		this.picked = key;
		if (!this.graphs.has(key) || this.graphs.get(key).error) this.readGraph(repo, n, cx);
		cx.notify();
	}

	readGraph(repo, n, cx) {
		const key = `${repo}#${n}`;
		this.graphs.set(key, { loading: true });
		cx.spawn(async (cx) => {
			try {
				this.graphs.set(key, { data: await readSpec(repo, n) });
			} catch (e) {
				this.graphs.set(key, { error: String(e.message ?? e) });
			}
			cx.notify();
		});
	}

	close() {
		const overlay = props()?.overlay;
		if (overlay) closeOverlay(overlay);
	}

	// Leaves the overview for what a card stands for.
	act(fn) {
		this.close();
		fn();
	}

	// ── the parts both pictures are drawn with ──

	/**
	 * A card: a bold head and a badge on top, a dimmed line under them.
	 * `ring` outlines it in a colour (what needs looking at); `quiet` draws it
	 * flat and dim (waiting, or done).
	 */
	node(t, id, x, y, w, o) {
		return v_flex()
			.id(id)
			.absolute()
			.left(x)
			.top(y)
			.w(w)
			.h(NODE_H)
			.px(SPACE.sm)
			.justify_center()
			.gap(2)
			.rounded(RADIUS.control)
			.bg(o.quiet ? t.background : t.raised)
			.border_1()
			.border_color(o.ring ?? t.border)
			.when(Boolean(o.onClick), (e) =>
				e
					.cursor_pointer()
					.hover((s) => s.border_color(t.accent))
					.on_click(() => this.act(o.onClick)),
			)
			.child(
				h_flex()
					.gap(SPACE.sm)
					.items_center()
					.when(Boolean(o.dot), (e) => e.child(o.dot))
					.child(
						div()
							.flex_none()
							.font_semibold()
							.text_size(TEXT.ui)
							.text_color(o.quiet ? t.dim : t.foreground)
							.child(o.head),
					)
					.child(div().flex_1())
					.when(Boolean(o.badge), (e) => e.child(badge(t, o.badge[0], o.badge[1]))),
			)
			.child(
				div()
					.truncate()
					.text_size(TEXT.meta)
					.text_color(o.quiet ? t.dim : t.muted)
					.child(o.sub ?? ''),
			);
	}

	/**
	 * Curved arrows from the right edge of one card to the left edge of
	 * another, each ending in a head; one path per colour, painted under the
	 * cards.
	 *
	 * @param {[number, number, number, number, string][]} arrows x0, y0, x1, y1, colour
	 */
	arrows(arrows) {
		const paths = new Map();
		for (const [x0, y0, x1, y1, color] of arrows) {
			const e = paths.get(color) ?? { line: PathBuilder.stroke(1.5), head: PathBuilder.fill() };
			const mid = (x0 + x1) / 2;
			e.line = e.line.move_to(x0, y0).cubic_bezier_to(x1 - 5, y1, mid, y0, mid, y1);
			e.head = e.head.add_polygon(
				[
					[x1, y1],
					[x1 - 6, y1 - 4],
					[x1 - 6, y1 + 4],
				],
				true,
			);
			paths.set(color, e);
		}
		return [...paths.entries()].flatMap(([color, e]) => [
			window.paint_path(e.line.build(), color).absolute().top(0).left(0).size_full(),
			window.paint_path(e.head.build(), color).absolute().top(0).left(0).size_full(),
		]);
	}

	// ── flow ──

	colW() {
		return Math.max(170, (this.width - LABEL_W) / COLUMNS.length);
	}

	cardW() {
		return this.colW() - COL_GAP;
	}

	flowX(col) {
		return LABEL_W + col * this.colW();
	}

	flowY(row) {
		return SPACE.md + row * (NODE_H + ROW_GAP);
	}

	band(t, repo, snap, address) {
		const b = bandOf(snap);
		const w = this.cardW();
		const cards = [];
		const arrows = [];
		const mid = (row) => this.flowY(row) + NODE_H / 2;
		b.ready.forEach((r, i) =>
			cards.push(
				this.node(t, `${repo}-r-${r.n}`, this.flowX(0), this.flowY(i), w, {
					head: `#${r.n}`,
					badge: r.waits ? ['waiting', 'neutral'] : ['ready', 'accent'],
					sub: r.title ?? r.note,
					quiet: r.waits,
				}),
			),
		);
		b.rows.forEach((r, i) => {
			const wk = r.worker;
			const p = r.pr;
			if (wk) {
				const needs = b.needs.has(wk.name);
				const terminal = terminals().find((x) => x.name === wk.name);
				const term = terminal?.address;
				cards.push(
					this.node(t, `${repo}-w-${wk.name}`, this.flowX(1), this.flowY(i), w, {
						// Which AI the worker is: Claude or Codex.
						dot: programIcon(t, terminal?.program, 14),
						head: wk.name,
						badge: workerBadge(wk, needs),
						sub: wk.ticket ? `#${wk.ticket} · ${wk.branch}` : wk.branch,
						ring: needs ? t.blocked : null,
						onClick: term ? () => run('terminal.peek', { terminal: term }) : undefined,
					}),
				);
			}
			if (p) {
				const ci = {
					passing: ['CI passing', 'done'],
					failing: ['CI failing', 'blocked'],
					pending: ['CI running', 'working'],
				}[p.ci] ?? [p.draft ? 'draft' : 'no CI', 'neutral'];
				const branch = p.branch ?? wk?.branch;
				cards.push(
					this.node(t, `${repo}-p-${p.number}`, this.flowX(2), this.flowY(i), w, {
						head: `#${p.number}`,
						badge: ci,
						sub: p.title ?? '',
						ring: p.ci === 'failing' ? t.ansi1 : null,
						onClick: branch
							? () =>
									openDiff({
										root: repo,
										on: null,
										kind: 'range',
										base: 'origin/HEAD',
										head: branch,
									})
							: undefined,
					}),
				);
				if (wk) arrows.push([this.flowX(1) + w, mid(i), this.flowX(2) - 2, mid(i), t.dim]);
			}
			if (r.q >= 0) {
				cards.push(
					this.node(t, `${repo}-q-${r.q}`, this.flowX(3), this.flowY(i), w, {
						head: `#${p.number}`,
						badge: [`${r.q + 1} in line`, 'accent'],
						sub: r.q === 0 ? 'lands next' : `after ${r.q} more`,
					}),
				);
				const color = { failing: t.ansi1, passing: t.ansi2 }[p.ci] ?? t.dim;
				arrows.push([this.flowX(2) + w, mid(i), this.flowX(3) - 2, mid(i), color]);
			}
		});
		b.landed.forEach((l, i) =>
			cards.push(
				this.node(t, `${repo}-l-${l.pr}`, this.flowX(4), this.flowY(i), w, {
					head: `#${l.pr}`,
					badge: [`landed ${ago(Date.parse(l.at))}`, 'done'],
					sub: l.title ?? '',
					quiet: true,
					onClick: l.url ? () => exec('open', [l.url]) : undefined,
				}),
			),
		);
		const needs = (snap.attention ?? []).length;
		const working = b.rows.some((r) => r.worker?.state === 'working' || r.worker?.state === 'busy');
		return div()
			.relative()
			.w_full()
			.h(SPACE.md * 2 + b.height * (NODE_H + ROW_GAP) - ROW_GAP)
			.border_b(1)
			.border_color(t.border)
			.children(this.arrows(arrows))
			.child(
				// The repository: a click goes to its harness.
				v_flex()
					.id(`${repo}-label`)
					.absolute()
					.left(0)
					.top(this.flowY(0))
					.w(LABEL_W - SPACE.md)
					.h(NODE_H)
					.justify_center()
					.gap(2)
					.cursor_pointer()
					.on_click(() => this.act(() => run('agent.focus', { terminal: address })))
					.child(
						h_flex()
							.gap(SPACE.sm)
							.items_center()
							.child(dot(t, needs ? 'blocked' : working ? 'working' : 'idle'))
							.child(
								div()
									.font_semibold()
									.truncate()
									.child(snap.name ?? repo.split('/').pop()),
							),
					)
					.child(
						div()
							.pl(SPACE.md + 3)
							.text_size(TEXT.meta)
							.text_color(needs ? t.blocked : t.dim)
							.child(
								needs
									? `${needs} needs you`
									: snap.at
										? `read ${ago(Date.parse(snap.at))} ago`
										: '',
							),
					),
			)
			.children(cards);
	}

	flowView(t, repos, snaps, running) {
		const columns = h_flex()
			.pl(LABEL_W)
			.pb(SPACE.xs)
			.border_b(1)
			.border_color(t.border)
			.children(
				COLUMNS.map((c) =>
					div()
						.w(this.colW())
						.text_size(TEXT.meta)
						.font_semibold()
						.text_color(t.dim)
						.child(c.toUpperCase()),
				),
			);
		const bands = repos.map((repo) =>
			snaps[repo]
				? this.band(t, repo, snaps[repo], running.get(repo))
				: div()
						.h(NODE_H)
						.pl(SPACE.sm)
						.text_color(t.dim)
						.child(`${repo.split('/').pop()} · reading…`),
		);
		const body = v_flex()
			.on_size_change((size, cx) => {
				const width = size.width / (settings().zoom || 1);
				if (Math.abs(width - this.width) < 1) return;
				this.width = width;
				cx.notify();
			})
			.child(columns)
			.when(!repos.length, (e) =>
				e.child(
					div()
						.p(SPACE.lg)
						.text_color(t.dim)
						.child('No harness runs. Start one from the Harness panel.'),
				),
			)
			.children(bands);
		return scroller('overview-body', body, { px: SPACE.lg, py: SPACE.md });
	}

	// ── specs ──

	specsView(t, snaps) {
		const list = v_flex()
			.w(LIST_W)
			.h_full()
			.flex_none()
			.p(SPACE.sm)
			.border_r(1)
			.border_color(t.border)
			.when(this.specs !== null && !this.specs.length, (e) =>
				e.child(
					div()
						.p(SPACE.sm)
						.text_size(TEXT.ui)
						.text_color(t.dim)
						.child('No spec started by a running harness'),
				),
			)
			.children(
				(this.specs ?? []).map((sp) => {
					const key = `${sp.repo}#${sp.n}`;
					const g = this.graphs.get(key)?.data;
					return row(t, `spec-${key}`, {
						selected: key === this.picked,
						tall: true,
						onClick: (_e, cx) => this.pick(sp, cx),
					})
						.child(
							div()
								.flex_none()
								.text_size(TEXT.meta)
								.text_color(t.dim)
								.child(sp.repo.split('/').pop()),
						)
						.child(
							div()
								.flex_1()
								.min_w(0)
								.child(g ? `#${sp.n} ${g.title}` : `#${sp.n}`),
						);
				}),
			);
		const entry = this.picked ? this.graphs.get(this.picked) : null;
		const [repo] = this.picked ? this.picked.split('#') : [null];
		let pictured;
		if (!entry)
			pictured = div()
				.p(SPACE.lg)
				.text_color(t.dim)
				.child(this.specs === null ? '' : 'Pick a spec');
		else if (entry.loading)
			pictured = div().p(SPACE.lg).text_color(t.dim).child('Reading the spec…');
		else if (entry.error) pictured = div().p(SPACE.lg).text_color(t.ansi1).child(entry.error);
		else pictured = this.specPicture(t, repo, entry.data, snaps[repo]);
		// Stretched to the dialog's height: an h_flex centres its children,
		// which left the scrolling picture no height of its own.
		return h_flex()
			.flex_1()
			.min_h(0)
			.w_full()
			.items_start()
			.child(list)
			.child(
				v_flex()
					.flex_1()
					.min_w(0)
					.min_h(0)
					.h_full()
					.child(scroller('overview-spec', pictured, { px: SPACE.lg, py: SPACE.lg })),
			);
	}

	specX(col) {
		return col * (NODE_W + COL_GAP);
	}

	specY(row) {
		return row * (NODE_H + ROW_GAP);
	}

	specPicture(t, repo, g, snap) {
		const live = snap?.specs?.find((x) => x.spec === g.spec);
		const state = {
			integrated: new Set(live?.integrated ?? []),
			working: new Set([
				...(live?.running ?? []),
				...(snap?.workers ?? []).map((w) => w.ticket).filter(Boolean),
			]),
		};
		const by = new Map(g.tickets.map((x) => [x.number, x]));
		const { at, cols, rows } = layoutSpec(g.tickets);
		const tone = {
			landed: ['landed', 'done', null],
			working: ['working', 'working', t.working],
			ready: ['ready', 'accent', t.accent],
			waiting: ['waiting', 'neutral', null],
			person: ['for you', 'neutral', t.ansi5],
		};
		const arrows = [];
		for (const x of g.tickets) {
			const to = at.get(x.number);
			for (const b of x.blockers) {
				const from = at.get(b);
				if (!from) continue;
				const done = stateOf(by.get(b), by, state) === 'landed';
				arrows.push([
					this.specX(from.col) + NODE_W,
					this.specY(from.row) + NODE_H / 2,
					this.specX(to.col) - 2,
					this.specY(to.row) + NODE_H / 2,
					done ? t.ansi2 : t.dim,
				]);
			}
		}
		const nodes = g.tickets.map((x) => {
			const p = at.get(x.number);
			const st = stateOf(x, by, state);
			const [text, mark, ring] = tone[st];
			return this.node(t, `ticket-${x.number}`, this.specX(p.col), this.specY(p.row), NODE_W, {
				head: `#${x.number}`,
				badge: [text, mark],
				sub: x.title,
				ring,
				quiet: st === 'waiting',
				onClick: () =>
					openBeside('issue', 'issue.target', {
						repo: g.repo,
						root: repo,
						on: null,
						number: x.number,
					}),
			});
		});
		const outside = [...new Set(g.tickets.flatMap((x) => x.blockers).filter((b) => !by.has(b)))];
		return v_flex()
			.gap(SPACE.md)
			.child(
				h_flex()
					.gap(SPACE.sm)
					.items_center()
					.child(
						div()
							.text_size(TEXT.body + 2)
							.font_semibold()
							.child(`#${g.spec} ${g.title}`),
					)
					.when(g.closed, (e) => e.child(badge(t, 'closed', 'done'))),
			)
			.when(outside.length > 0, (e) =>
				e.child(
					div()
						.text_size(TEXT.meta)
						.text_color(t.dim)
						.child(
							`Also waits on issues outside the spec: ${outside.map((n) => `#${n}`).join(' ')}`,
						),
				),
			)
			.child(
				div()
					.relative()
					.flex_none()
					.w(Math.max(1, cols) * (NODE_W + COL_GAP))
					.h(Math.max(1, rows) * (NODE_H + ROW_GAP))
					.children(this.arrows(arrows))
					.children(nodes),
			);
	}

	render() {
		const t = theme();
		const running = runningHarnesses();
		const snaps = shared('harness.snaps') ?? {};
		const repos = [...running.keys()].sort();
		const head = bar(t, 'overview-bar')
			.child(
				title(t, 'Overview', `${repos.length} ${repos.length === 1 ? 'harness' : 'harnesses'}`),
			)
			.child(
				segmented(
					t,
					'overview-view',
					[
						{ key: 'flow', label: 'Flow' },
						{ key: 'specs', label: 'Specs' },
					],
					this.view,
					(key, cx) => {
						this.view = key;
						if (key === 'specs' && this.specs === null) this.findSpecs(cx);
						cx.notify();
					},
				),
			)
			.child(button(t, 'overview-close', '✕', () => this.close()));
		return sheet(t)
			.child(head)
			.child(
				this.view === 'specs' ? this.specsView(t, snaps) : this.flowView(t, repos, snaps, running),
			);
	}
}
