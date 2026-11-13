// One GitHub issue, beside the terminals: its body and comments as the
// markdown viewer draws them, its labels and linked pull requests, and two
// ways out: GitHub, for anything to change on it, and the harness, to have
// it worked on. Read-only otherwise.
//
// What it shows comes from shared('issue.target'), set by the Issues panel
// (lib/pane.js).
import { View, div } from 'gpui-kit';
import { v_flex, h_flex } from 'gpui-base';
import { shared, theme, exec, notify, settings } from 'herdr';
import { SPACE, TEXT, bar, title, button, badge, chip, sheet, scroller, ago } from './lib/ui.js';
import { Markdown } from './lib/markdown.js';
import { handToHarness, runningHarnesses } from './lib/harness.js';

const FIELDS =
	'number,title,state,body,author,createdAt,labels,assignees,comments,url,closedByPullRequestsReferences';
// The text's side padding (px(SPACE.lg) on the body) and the scrollbar beside
// it, for the width the text and its images may take.
const PAD = SPACE.lg * 2 + SPACE.sm;

const sameIssue = (a, b) => Boolean(a && b) && a.repo === b.repo && a.number === b.number;

export default class Issue extends View {
	init(_props, cx) {
		this.target = null;
		this.seq = null;
		this.issue = null;
		this.posts = []; // [{ who, at, md }]: the body, then each comment
		this.error = null;
		this.loading = false;
		this.handing = null; // what handing it to the harness said
		this.width = 700;
		this.take(cx);
	}

	take(cx) {
		const next = shared('issue.target');
		if (!next || next.seq === this.seq) return;
		this.seq = next.seq;
		if (sameIssue(next, this.target)) return;
		this.target = next;
		this.issue = null;
		this.posts = [];
		this.handing = null;
		this.load(cx);
	}

	load(cx) {
		const target = this.target;
		if (!target || this.loading) return;
		this.loading = true;
		cx.spawn(async (cx) => {
			try {
				const r = await exec(
					'gh',
					['issue', 'view', String(target.number), '-R', target.repo, '--json', FIELDS],
					{ on: target.on },
				);
				if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim().split('\n').pop());
				if (target !== this.target) return;
				const issue = JSON.parse(r.stdout);
				// Made here, not in render, which may not create host state.
				const post = (id, who, at, text) => {
					const md = new Markdown(`issue-${id}`);
					md.set(text || '_No description._', target.root, cx);
					return { who, at, md };
				};
				this.posts = [
					post('body', issue.author?.login, issue.createdAt, issue.body),
					...issue.comments.map((c, i) => post(`c${i}`, c.author?.login, c.createdAt, c.body)),
				];
				this.issue = issue;
				this.error = null;
			} catch (e) {
				if (target === this.target) this.error = String(e.message ?? e);
			} finally {
				this.loading = false;
				cx.notify();
			}
		});
	}

	hand(cx) {
		const { root, number } = this.target;
		this.handing = '…';
		cx.notify();
		cx.spawn(async (cx) => {
			const said = await handToHarness(root, `#${number}`);
			this.handing =
				said === 'sent'
					? 'Sent to the harness'
					: said === 'started'
						? 'Harness started on it'
						: said;
			if (said !== 'sent' && said !== 'started')
				notify({ title: `#${number} not handed over`, body: said, level: 'warning' });
			cx.notify();
		});
	}

	post(t, p, i) {
		return v_flex()
			.gap(SPACE.sm)
			.pb(SPACE.lg)
			.when(i > 0, (e) => e.pt(SPACE.md).border_t(1).border_color(t.border))
			.child(
				h_flex()
					.gap(SPACE.sm)
					.text_size(TEXT.meta)
					.text_color(t.dim)
					.child(
						div()
							.font_semibold()
							.text_color(t.muted)
							.child(p.who ?? 'ghost'),
					)
					.child(div().child(p.at ? ago(Date.parse(p.at)) : '')),
			)
			.child(p.md.view(t, this.width - PAD));
	}

	render(cx) {
		this.take(cx);
		const t = theme();
		const target = this.target;
		const issue = this.issue;
		const running = target ? runningHarnesses().has(target.root) : false;
		// The bar holds what it is and what can be done with it; the title,
		// often long, reads in full at the top of the body.
		const head = bar(t, 'issue-bar')
			.child(title(t, target ? `#${target.number}` : 'Issue', issue ? '' : (target?.repo ?? '')))
			.when(Boolean(issue), (e) =>
				e.child(badge(t, issue.state.toLowerCase(), issue.state === 'OPEN' ? 'working' : 'done')),
			)
			.when(Boolean(issue && issue.state === 'OPEN'), (e) =>
				e.child(
					// Typed into the harness's input, or a harness started with it.
					button(t, 'issue-hand', running ? 'Hand to harness' : 'Start harness on it', (_e, cx) =>
						this.hand(cx),
					),
				),
			)
			.when(Boolean(issue), (e) =>
				e.child(button(t, 'issue-github', 'GitHub', () => exec('open', [issue.url]))),
			)
			.child(button(t, 'issue-refresh', this.loading ? '…' : '↻', (_e, cx) => this.load(cx)));

		const empty = (text) => div().p(SPACE.lg).text_color(t.dim).child(text);
		let body;
		if (!target) body = empty('Pick an issue in Issues');
		else if (this.error) body = empty(this.error);
		else if (!issue) body = empty('Reading…');
		else {
			const prs = issue.closedByPullRequestsReferences ?? [];
			const content = v_flex()
				.gap(SPACE.md)
				.child(
					div()
						.text_size(TEXT.body + 3)
						.font_semibold()
						.text_color(t.foreground)
						.child(issue.title),
				)
				.when(Boolean(this.handing), (e) =>
					e.child(div().text_size(TEXT.ui).text_color(t.muted).child(this.handing)),
				)
				.when(issue.labels.length > 0 || prs.length > 0, (e) =>
					e.child(
						h_flex()
							.flex_wrap()
							.gap(SPACE.xs)
							.children(issue.labels.map((l) => chip(t, `l-${l.name}`, `#${l.color}`, l.name)))
							.children(
								prs.map((p) =>
									chip(t, `pr-${p.number}`, t.accent, `PR #${p.number}`, () =>
										exec('open', [p.url]),
									),
								),
							),
					),
				)
				.children(this.posts.map((p, i) => this.post(t, p, i)));
			body = scroller('issue-body', content, { px: SPACE.lg, py: SPACE.md });
		}
		return sheet(t)
			.child(head)
			.child(
				// Measured here, around the scrolling body, not on its content:
				// the content is as wide as the text was laid out, so measuring it
				// kept a first guess too wide for the pane.
				v_flex()
					.flex_1()
					.min_h(0)
					.on_size_change((size, cx) => {
						const width = size.width / (settings().zoom || 1);
						if (Math.abs(width - this.width) < 1) return;
						this.width = width;
						cx.notify();
					})
					.child(body),
			);
	}
}
