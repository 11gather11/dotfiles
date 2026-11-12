// issue-harness for the repository of the focused pane: what needs the person,
// the workers, the landing queue, open specs and recent landings.
//
// Every verdict (blocked, queued, ready) comes from `harness-status`, which is
// issue-harness's own status.nu; this file only draws it.
import { View, div, svg } from 'gpui-kit';
import { v_flex, h_flex, Scrollbar } from 'gpui-base';
import { spaces, panes, focused, exec, theme, notify, terminals, run } from 'herdr';

// status.nu reads GitHub and every worker's screen, about two seconds a run,
// so the panel polls gently and offers a refresh for when it matters now.
const POLL_MS = 30000;
const SPINNER = 'mods/workspace-chrome/spinner.svg';

/** The folder of the focused pane, else of the active space. */
function folder() {
	const space = spaces().find((s) => s.active),
		f = focused();
	const pane = f?.pane ? panes().find((p) => p.pane === f.pane) : null;
	return pane?.cwd || f?.cwd || space?.folder || null;
}

/** "3m", "2h", "4d" since an RFC 3339 time. */
function ago(at) {
	const s = Math.max(0, (Date.now() - Date.parse(at)) / 1000);
	if (s < 60) return 'now';
	if (s < 3600) return `${Math.floor(s / 60)}m`;
	if (s < 86400) return `${Math.floor(s / 3600)}h`;
	return `${Math.floor(s / 86400)}d`;
}

/** A stable key for an attention entry, to tell new ones from ones already shown. */
const attentionKey = (a) => `${a.kind}:${a.worker ?? a.spec}:${a.detail}`;

export default class Harness extends View {
	init(_props, cx) {
		this.snap = null;
		this.error = null;
		this.loading = false;
		this.dir = null;
		this.seen = null;
		this.refresh(cx);
		cx.timer.every(POLL_MS, (cx) => this.refresh(cx));
	}

	refresh(cx) {
		const dir = folder();
		if (dir !== this.dir) {
			// Another repository: drop what was shown, and do not announce its
			// existing attention entries as new.
			this.dir = dir;
			this.snap = null;
			this.error = null;
			this.seen = null;
		}
		if (!dir || this.loading) return;
		this.loading = true;
		cx.spawn(async (cx) => {
			try {
				// The workers in this app's terminals; a harness run from the herdr TUI
				// keeps its own there.
				const r = await exec('harness-status', ['--dir', dir, '--mux', 'hc']);
				if (this.dir !== dir) return;
				const line = r.stdout.trim().split('\n').pop();
				if (r.code !== 0 || !line) {
					this.error =
						(r.stderr || r.stdout).trim().split('\n').pop() || `harness-status exited ${r.code}`;
					return;
				}
				this.snap = JSON.parse(line);
				this.error = null;
				this.announce(this.snap.attention);
			} catch (e) {
				if (this.dir === dir) this.error = String(e);
			} finally {
				this.loading = false;
				cx.notify();
			}
		});
		cx.notify();
	}

	// A worker that newly needs the person is worth a notification even when
	// the panel is hidden; the first snapshot of a repository only sets the
	// baseline.
	announce(attention) {
		const keys = new Set(attention.map(attentionKey));
		if (this.seen) {
			for (const a of attention) {
				if (this.seen.has(attentionKey(a))) continue;
				notify({
					title: a.worker ? `${a.worker} ${a.kind}` : `spec #${a.spec} ${a.kind}`,
					body: a.detail,
					level: a.kind === 'blocked' ? 'warning' : 'info',
				});
			}
		}
		this.seen = keys;
	}

	open(url) {
		if (url) exec('open', [url]);
	}

	// Shows a worker's screen over the current tab, where it can be answered,
	// kept as a tab or closed, without leaving the harness. Workers are
	// herdr-core terminals named after the worker; one that is gone has none.
	peek(name) {
		const address = name && terminals().find((x) => x.name === name)?.address;
		if (address) run('terminal.peek', { terminal: address });
	}

	// ── pieces ──

	// An empty section is its heading alone, dimmed: a line saying "none" under
	// every one of them took more room than everything else in a quiet panel.
	section(t, title, count, body) {
		return v_flex()
			.gap(4)
			.flex_none()
			.child(
				h_flex()
					.gap(6)
					.items_center()
					.px(4)
					.child(
						div()
							.text_size(11)
							.font_semibold()
							.text_color(body === null ? t.dim : t.muted)
							.child(title.toUpperCase()),
					)
					.when(count !== null, (e) =>
						e.child(div().text_size(10).text_color(t.dim).child(String(count))),
					),
			)
			.when(body !== null, (e) => e.child(body));
	}

	empty(t, text) {
		return div().px(8).py(2).text_size(12).text_color(t.dim).child(text);
	}

	ci(t, pr) {
		if (!pr) return div();
		const color =
			{ passing: t.ansi2, failing: t.ansi1, pending: t.blocked, none: t.dim }[pr.ci] ?? t.dim;
		return h_flex()
			.id(`pr-${pr.number}`)
			.gap(4)
			.items_center()
			.flex_none()
			.px(5)
			.py(1)
			.rounded(4)
			.border_1()
			.border_color(t.border)
			.cursor_pointer()
			.hover((s) => s.bg(t.hover))
			.on_click((_e, cx) => {
				// Inside a worker row, whose own click peeks at the worker.
				cx.stop_propagation();
				this.open(pr.url);
			})
			.child(div().size(6).rounded(3).bg(color))
			.child(div().text_size(11).text_color(t.muted).child(`#${pr.number}`));
	}

	stateMark(t, state) {
		if (state === 'working' || state === 'busy')
			// A still dot, as in the sidebar and the herdr TUI.
			return div().size(7).rounded(4).flex_none().bg(t.working);
		const color = { blocked: t.blocked, stopped: t.done, none: t.dim }[state] ?? t.unknown;
		return div().size(7).rounded(4).flex_none().bg(color);
	}

	row(id, t) {
		return h_flex()
			.id(id)
			.min_h(22)
			.px(8)
			.gap(8)
			.items_center()
			.rounded(6)
			.hover((s) => s.bg(t.hover));
	}

	attention(t, list) {
		if (!list.length) return null;
		return v_flex()
			.gap(2)
			.children(
				list.map((a, i) =>
					this.row(`att-${i}`, t)
						.when(Boolean(a.worker), (e) => e.cursor_pointer().on_click(() => this.peek(a.worker)))
						.bg(a.kind === 'blocked' ? t.blocked + '22' : t.raised)
						.child(this.stateMark(t, a.kind === 'stuck' ? 'blocked' : a.kind))
						.child(
							v_flex()
								.flex_1()
								.min_w(0)
								.child(
									div()
										.text_size(12)
										.truncate()
										.child(a.worker ?? `spec #${a.spec}`),
								)
								.child(div().text_size(11).text_color(t.muted).truncate().child(a.detail)),
						),
				),
			);
	}

	workers(t, list) {
		if (!list.length) return null;
		return v_flex()
			.gap(2)
			.children(
				list.map((w) =>
					this.row(`w-${w.branch}`, t)
						.when(Boolean(w.name), (e) => e.cursor_pointer().on_click(() => this.peek(w.name)))
						.child(this.stateMark(t, w.state))
						.child(
							v_flex()
								.flex_1()
								.min_w(0)
								.child(
									div()
										.text_size(12)
										.truncate()
										.child(w.name ?? '(no agent)'),
								)
								.child(div().text_size(11).text_color(t.dim).truncate().child(w.branch)),
						)
						.child(this.ci(t, w.pr)),
				),
			);
	}

	queue(t, list) {
		if (!list.length) return null;
		return v_flex()
			.gap(2)
			.children(
				list.map((p, i) =>
					this.row(`q-${p.number}`, t)
						.child(
							div()
								.w(14)
								.flex_none()
								.text_size(11)
								.text_color(t.dim)
								.child(String(i + 1)),
						)
						.child(
							div()
								.flex_1()
								.min_w(0)
								.text_size(12)
								.truncate()
								.child(p.title ?? `#${p.number}`),
						)
						.child(this.ci(t, p.url ? p : { ...p, ci: 'none' })),
				),
			);
	}

	specs(t, list) {
		if (!list.length) return null;
		return v_flex()
			.gap(6)
			.children(
				list.map((s) => {
					const chips = [
						...s.integrated.map((n) => [n, t.ansi2, 'in']),
						...s.running.map((n) => [n, t.working, 'running']),
						...s.ready.map((r) => [r.ticket, t.accent, 'ready']),
						...s.waiting.map((w) => [
							w.number,
							t.dim,
							`waits on ${w.on.map((n) => `#${n}`).join(' ')}`,
						]),
					];
					return v_flex()
						.id(`spec-${s.spec}`)
						.gap(4)
						.px(8)
						.py(6)
						.rounded(6)
						.bg(t.raised)
						.child(
							h_flex()
								.gap(6)
								.items_center()
								.child(div().text_size(12).font_semibold().flex_none().child(`#${s.spec}`))
								.child(div().flex_1().min_w(0).text_size(12).truncate().child(s.title))
								.when(s.result === 'stuck', (e) =>
									e.child(div().text_size(11).text_color(t.blocked).child('stuck')),
								)
								.when(s.done, (e) =>
									e.child(div().text_size(11).text_color(t.ansi2).child('all in')),
								),
						)
						.child(
							h_flex()
								.flex_wrap()
								.gap(4)
								.children(
									chips.map(([n, color, label]) =>
										h_flex()
											.id(`t-${s.spec}-${n}`)
											.gap(4)
											.items_center()
											.px(5)
											.py(1)
											.rounded(4)
											.border_1()
											.border_color(t.border)
											.child(div().size(6).rounded(3).bg(color))
											.child(div().text_size(11).text_color(t.muted).child(`#${n} ${label}`)),
									),
								),
						);
				}),
			);
	}

	landed(t, list) {
		if (!list.length) return null;
		return v_flex()
			.gap(2)
			.children(
				list.map((l) =>
					this.row(`l-${l.pr}`, t)
						.when(Boolean(l.url), (e) => e.cursor_pointer().on_click(() => this.open(l.url)))
						.child(div().w(40).flex_none().text_size(11).text_color(t.dim).child(`#${l.pr}`))
						.child(
							div()
								.flex_1()
								.min_w(0)
								.text_size(12)
								.text_color(t.muted)
								.truncate()
								.child(l.title ?? ''),
						)
						.child(div().flex_none().text_size(11).text_color(t.dim).child(ago(l.at))),
				),
			);
	}

	render(cx) {
		const t = theme();
		if (folder() !== this.dir) this.refresh(cx);
		const s = this.snap;
		const header = h_flex()
			.h(34)
			.flex_none()
			.px(14)
			.gap(8)
			.items_center()
			.border_b(1)
			.border_color(t.border)
			.child(div().font_semibold().child('Harness'))
			.when(Boolean(s), (e) =>
				e.child(
					div()
						.px(5)
						.py(1)
						.rounded(4)
						.border_1()
						.border_color(t.border)
						.text_size(10)
						.text_color(t.muted)
						.child(s.name),
				),
			)
			.child(div().flex_1())
			.child(
				this.loading
					? svg(SPINNER).size(13).text_color(t.dim).spin(900)
					: div()
							.id('refresh')
							.size(24)
							.flex()
							.items_center()
							.justify_center()
							.rounded(6)
							.text_color(t.dim)
							.cursor_pointer()
							.hover((st) => st.bg(t.hover).text_color(t.foreground))
							.on_click((_e, cx) => this.refresh(cx))
							.child('↻'),
			);

		let body;
		if (!s) {
			body = this.empty(t, this.error ?? (this.dir ? 'Reading the harness…' : 'No folder'));
		} else {
			body = v_flex()
				.gap(10)
				.child(
					this.section(t, 'Needs you', s.attention.length || null, this.attention(t, s.attention)),
				)
				.child(this.section(t, 'Workers', s.workers.length, this.workers(t, s.workers)))
				.child(this.section(t, 'Queue', s.queue.length, this.queue(t, s.queue)))
				.child(this.section(t, 'Specs', s.specs.length, this.specs(t, s.specs)))
				.child(this.section(t, 'Landed', null, this.landed(t, s.landed)))
				.when(s.errors.length > 0 || Boolean(this.error), (e) =>
					e.child(
						v_flex()
							.gap(2)
							.px(8)
							.children(
								[...s.errors, ...(this.error ? [this.error] : [])].map((m) =>
									div().text_size(11).text_color(t.ansi1).child(m),
								),
							),
					),
				);
		}

		return v_flex()
			.id('harness')
			.size_full()
			.min_h(0)
			.rounded(10)
			.overflow_hidden()
			.bg(t.background)
			.border_1()
			.border_color(t.border)
			.text_color(t.foreground)
			.text_size(13)
			.child(header)
			.child(
				div()
					.flex_1()
					.min_h(0)
					.relative()
					.child(
						v_flex().id('harness-body').absolute().inset_0().overflow_y_scroll().p(8).child(body),
					)
					.child(Scrollbar.vertical('harness-body').absolute().inset_0()),
			);
	}
}
