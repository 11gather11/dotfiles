// The GitHub issues of the repository being worked in, each marked with what
// its harness is doing about it: a worker on it, the spec it belongs to, a
// ticket waiting on another, landed. A click shows the issue in the pane
// beside the terminals (mods/issue), where it can be handed to the harness.
//
// The marks come from the snapshots harness-list shares (harness.snaps), so
// this panel reads only GitHub, and only while it is shown.
import { View, div } from 'gpui-kit';
import { v_flex, h_flex, Input, InputState } from 'gpui-base';
import { exec, theme, shared, layout } from 'herdr';
import {
	SPACE,
	TEXT,
	RADIUS,
	bar,
	spacer,
	button,
	badge,
	row,
	panel,
	segmented,
	ago,
} from './lib/ui.js';
import { focusedPlace } from './lib/focus.js';
import { git } from './lib/git.js';
import { openBeside } from './lib/pane.js';
import { resetSlot } from './lib/panels.js';

// GitHub is asked again this often while the panel shows.
const SYNC_MS = 30000;
const LIMIT = 100;
const FIELDS = 'number,title,labels,assignees,updatedAt,comments';

function find(node, id) {
	if (node?.id === id) return node;
	for (const child of node?.children ?? []) {
		const found = find(child, id);
		if (found) return found;
	}
	return null;
}

// The panel is in the layout's side stack: shown when that is open on it.
function showing() {
	const root = layout();
	return !find(root, 'panel')?.hidden && find(root, 'panel-body')?.active === 'issues';
}

/**
 * What a repository's harness is doing about an issue, from its shared
 * snapshot (see harness-list): the text of the mark and its tone.
 *
 * @param {any} snap
 * @param {number} n the issue's number
 * @returns {{ text: string, tone: 'working' | 'blocked' | 'done' | 'accent' | 'neutral' } | null}
 */
export function harnessMark(snap, n) {
	if (!snap) return null;
	const w = snap.workers?.find((x) => x.ticket === n);
	if (w) {
		const tone = { working: 'working', busy: 'working', blocked: 'blocked', stuck: 'blocked' }[
			w.state
		];
		return { text: w.pr ? `${w.name} · #${w.pr.number}` : w.name, tone: tone ?? 'done' };
	}
	for (const s of snap.specs ?? []) {
		if (s.spec === n) return { text: s.done ? 'spec · all in' : 'spec', tone: 'accent' };
		if (s.integrated.includes(n)) return { text: 'landed', tone: 'done' };
		if (s.running.includes(n)) return { text: 'running', tone: 'working' };
		if (s.ready.some((r) => r.ticket === n)) return { text: 'ready', tone: 'accent' };
		const wait = s.waiting.find((x) => x.number === n);
		if (wait) return { text: `waits ${wait.on.map((m) => `#${m}`).join(' ')}`, tone: 'neutral' };
	}
	return null;
}

export default class Issues extends View {
	init(_props, cx) {
		this.where = null;
		this.root = null; // the main checkout, which the harness is labelled with
		this.on = null;
		this.repo = null; // owner/name
		this.issues = [];
		this.error = null;
		this.loading = false;
		this.state = 'open';
		this.mine = false;
		this.query = '';
		this.input = InputState.new({ placeholder: 'Filter' });
		this.input.on('change', (_e, cx) => {
			this.query = this.input.value().trim().toLowerCase();
			cx.notify();
		});
		this.refresh(cx);
		cx.timer.every(SYNC_MS, (cx) => {
			if (showing()) this.refresh(cx);
		});
	}

	refresh(cx) {
		const { folder, on } = focusedPlace();
		const where = JSON.stringify([folder, on, this.state, this.mine]);
		if (where !== this.where) {
			const sameRepo = this.where && JSON.parse(this.where)[0] === folder;
			this.where = where;
			this.error = null;
			if (!sameRepo) {
				this.root = null;
				this.repo = null;
				this.issues = [];
			}
		}
		if (!folder || this.loading) return;
		this.loading = true;
		cx.spawn(async (cx) => {
			try {
				// A worker's worktree belongs to the main checkout's repository.
				const common = await git(folder, on, [
					'rev-parse',
					'--path-format=absolute',
					'--git-common-dir',
				]);
				if (common.code !== 0) throw new Error('Not a git repository');
				const root = common.stdout.trim().replace(/\/\.git$/, '');
				if (!this.repo || this.root !== root) {
					const r = await exec(
						'gh',
						['repo', 'view', '--json', 'nameWithOwner', '-q', '.nameWithOwner'],
						{
							cwd: root,
							on,
						},
					);
					if (r.code !== 0) throw new Error('Not a GitHub repository');
					this.repo = r.stdout.trim();
				}
				const args = [
					'issue',
					'list',
					'-R',
					this.repo,
					'--state',
					this.state,
					'--limit',
					String(LIMIT),
				];
				if (this.mine) args.push('--assignee', '@me');
				const r = await exec('gh', [...args, '--json', FIELDS], { on });
				if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim().split('\n').pop());
				if (where !== this.where) return;
				this.issues = JSON.parse(r.stdout);
				this.root = root;
				this.on = on;
				this.error = null;
			} catch (e) {
				if (where === this.where) this.error = String(e.message ?? e);
			} finally {
				this.loading = false;
				cx.notify();
			}
		});
	}

	show(issue) {
		openBeside('issue', 'issue.target', {
			repo: this.repo,
			root: this.root,
			on: this.on,
			number: issue.number,
		});
	}

	issueRow(t, issue, snap, shown) {
		const mark = harnessMark(snap, issue.number);
		const selected = shown?.repo === this.repo && shown?.number === issue.number;
		return row(t, `i-${issue.number}`, { selected, tall: true, onClick: () => this.show(issue) })
			.child(
				div().w(36).flex_none().text_size(TEXT.meta).text_color(t.dim).child(`#${issue.number}`),
			)
			.child(
				v_flex()
					.flex_1()
					.min_w(0)
					.gap(2)
					.child(div().text_color(t.foreground).child(issue.title))
					.child(
						h_flex()
							.flex_wrap()
							.gap(SPACE.xs)
							.text_size(TEXT.meta)
							.text_color(t.dim)
							.when(Boolean(mark), (e) => e.child(badge(t, mark.text, mark.tone)))
							.children(issue.labels.map((l) => this.label(t, l)))
							.child(div().child(ago(Date.parse(issue.updatedAt))))
							.when(issue.comments?.length > 0, (e) =>
								e.child(div().child(`💬 ${issue.comments.length}`)),
							),
					),
			);
	}

	// A label in its GitHub colour: a dot of it, and its name.
	label(t, l) {
		return h_flex()
			.flex_none()
			.gap(3)
			.items_center()
			.child(div().size(6).rounded(3).bg(`#${l.color}`))
			.child(l.name);
	}

	render(cx) {
		const t = theme();
		const { folder, on } = focusedPlace();
		if (JSON.stringify([folder, on, this.state, this.mine]) !== this.where && showing())
			this.refresh(cx);
		const snap = this.root ? shared('harness.snaps')?.[this.root] : null;
		const shown = shared('issue.target');
		const q = this.query;
		const list = q
			? this.issues.filter(
					(i) =>
						i.title.toLowerCase().includes(q) || String(i.number).startsWith(q.replace('#', '')),
				)
			: this.issues;
		const head = bar(t, 'issues-bar')
			.child(div().flex_none().font_semibold().child('Issues'))
			.when(Boolean(this.repo), (e) => e.child(badge(t, this.repo.split('/').pop())))
			.child(spacer())
			.child(resetSlot(t, 'issues'))
			.child(button(t, 'issues-refresh', this.loading ? '…' : '↻', (_e, cx) => this.refresh(cx)));
		const controls = h_flex()
			.gap(SPACE.sm)
			.items_center()
			.pb(SPACE.sm)
			.child(
				segmented(
					t,
					'issues-state',
					[
						{ key: 'open', label: 'Open' },
						{ key: 'closed', label: 'Closed' },
					],
					this.state,
					(key, cx) => {
						this.state = key;
						this.refresh(cx);
					},
				),
			)
			.child(
				button(
					t,
					'issues-mine',
					'Mine',
					(_e, cx) => {
						this.mine = !this.mine;
						this.refresh(cx);
					},
					{ kind: this.mine ? 'selected' : 'ghost' },
				),
			)
			.child(
				div()
					.flex_1()
					.min_w(0)
					.h(24)
					.px(SPACE.sm)
					.flex()
					.items_center()
					.rounded(RADIUS.control)
					.border_1()
					.border_color(t.border)
					.child(Input.new(this.input).h_full().text_size(TEXT.ui).text_color(t.foreground)),
			);
		const body = v_flex()
			.child(controls)
			.when(!list.length, (e) =>
				e.child(
					div()
						.p(SPACE.sm)
						.text_size(TEXT.ui)
						.text_color(t.dim)
						.child(
							this.error ??
								(this.loading
									? 'Reading…'
									: !folder
										? 'No folder'
										: q
											? 'No match'
											: `No ${this.state} issues`),
						),
				),
			)
			.children(list.map((i) => this.issueRow(t, i, snap, shown)));
		return panel(t, 'issues-body', head, body);
	}
}
