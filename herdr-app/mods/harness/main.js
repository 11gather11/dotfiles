// issue-harness for the repository of the focused pane: what needs the person,
// the workers, the landing queue, open specs and recent landings.
//
// Every verdict (blocked, queued, ready) comes from `harness-status`, which is
// issue-harness's own status.nu; this file only draws it.
import { View, div } from 'gpui-kit';
import { v_flex, h_flex, Scrollbar } from 'gpui-base';
import {
	SPACE,
	TEXT,
	RADIUS,
	bar,
	spacer,
	button,
	badge,
	chip,
	dot,
	row,
	heading,
} from './lib/ui.js';
import { spaces, panes, exec, hc, theme, notify, terminals, run } from 'herdr';
import { focusedFolder } from './lib/focus.js';

// status.nu reads GitHub and every worker's screen, about two seconds a run,
// so the panel polls gently and offers a refresh for when it matters now.
const POLL_MS = 30000;

// The repository shown is the one being worked in (lib/focus.js).
const folder = focusedFolder;

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
		// The last snapshot of each repository, shown on coming back to it.
		this.cache = new Map();
		this.reading = new Set(); // repositories being read now
		this.harnesses = new Map(); // repository => its running harness's terminal
		this.dir = null;
		this.seen = null;
		this.refresh(cx);
		cx.timer.every(POLL_MS, (cx) => this.refresh(cx));
	}

	// Reads the repository's harness again. Safe from render: it only starts
	// the read, and the read redraws when it lands.
	refresh(cx) {
		const dir = folder();
		if (dir !== this.dir) {
			// Another repository: show what it showed last at once, and read it
			// again behind that; its attention entries seen then stay seen.
			this.dir = dir;
			this.snap = this.cache.get(dir)?.snap ?? null;
			this.seen = this.cache.get(dir)?.seen ?? null;
			this.error = null;
		}
		// One read per repository at a time; a read for another repository
		// still running does not hold this one up.
		if (!dir || this.reading.has(dir)) return;
		this.reading.add(dir);
		cx.spawn(async (cx) => {
			try {
				// The workers in this app's terminals; a harness run from the herdr TUI
				// keeps its own there.
				const r = await exec('harness-status', ['--dir', dir, '--mux', 'hc']);
				const line = r.stdout.trim().split('\n').pop();
				if (r.code !== 0 || !line) {
					if (this.dir === dir)
						this.error =
							(r.stderr || r.stdout).trim().split('\n').pop() || `harness-status exited ${r.code}`;
					return;
				}
				const snap = JSON.parse(line);
				await this.findHarness(snap.repo);
				if (this.dir !== dir) {
					this.cache.set(dir, { snap, seen: this.cache.get(dir)?.seen ?? null });
					return;
				}
				this.snap = snap;
				this.error = null;
				this.announce(snap.attention);
				this.cache.set(dir, { snap, seen: this.seen });
			} catch (e) {
				if (this.dir === dir) this.error = String(e);
			} finally {
				this.reading.delete(dir);
				cx.notify();
			}
		});
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

	// The harness's own Claude in this repository: the terminal the
	// `harness` command (herdr-app.nix) labelled harness=<repository>, with
	// Claude in front still. Read with each refresh (see findHarness).
	harnessTerminal(repo) {
		return this.harnesses.get(repo) ?? null;
	}

	async findHarness(repo) {
		const r = await hc(['ls', '--json', '--label', `harness=${repo}`]).catch(() => null);
		const list = r?.code === 0 ? JSON.parse(r.stdout) : [];
		const live = (Array.isArray(list) ? list : (list.terminals ?? [])).find(
			(x) => x.agent === 'claude-code',
		);
		if (live) this.harnesses.set(repo, { address: live.address });
		else this.harnesses.delete(repo);
	}

	// Goes to the harness when one runs, else starts one in the repository's
	// own space: the one with a terminal in the main checkout, the active one
	// first. A worker's space (its folder a worktree beside the checkout,
	// `<repo>.<branch>`) never counts, though the panel shows the repository
	// from there too, and without such a space it gets a new one. Through a
	// login shell, as spawn.nu starts workers: the core's environment is the
	// one it started with, and the shell's profile is what puts claude and
	// harness on PATH whatever that was.
	startOrOpen(repo, cx) {
		const running = this.harnessTerminal(repo);
		if (running) {
			run('agent.focus', { terminal: running.address });
			return;
		}
		const argv = ['/bin/sh', '-c', 'exec "$SHELL" -l -c "exec harness"'];
		const inRepo = new Set(
			panes()
				.filter((p) => p.cwd === repo)
				.map((p) => p.tab),
		);
		const home = spaces()
			.filter((s) => !s.machine && !s.folder.startsWith(`${repo}.`))
			.filter((s) => s.tabs.some((tab) => inRepo.has(tab.id)))
			.sort((a, b) => Number(b.active) - Number(a.active))[0];
		if (home) run('tab.new', { name: 'harness', space: home.id, folder: repo, argv });
		else run('space.new', { folder: repo, tab: 'harness', argv });
		// Open replaces Start once the new harness has labelled its terminal.
		cx.timer.after(4000, (cx) => this.refresh(cx));
	}

	// ── pieces ──

	// An empty section is its heading alone, dimmed: a line saying "none" under
	// every one of them took more room than everything else in a quiet panel.
	section(t, name, count, body) {
		return v_flex()
			.flex_none()
			.child(heading(t, name, count))
			.when(body !== null, (e) => e.child(body));
	}

	empty(t, text) {
		return div().px(SPACE.sm).py(SPACE.xs).text_size(TEXT.ui).text_color(t.dim).child(text);
	}

	// A pull request and its CI, which opens the PR.
	ci(t, pr) {
		if (!pr) return div();
		const color =
			{ passing: t.ansi2, failing: t.ansi1, pending: t.blocked, none: t.dim }[pr.ci] ?? t.dim;
		return chip(t, `pr-${pr.number}`, color, `#${pr.number}`, () => this.open(pr.url));
	}

	// A worker's state as an agent status, for the dot.
	status(state) {
		if (state === 'working' || state === 'busy') return 'working';
		return { blocked: 'blocked', stuck: 'blocked', stopped: 'done' }[state] ?? null;
	}

	// One line: the dot, a name, what it is about (dimmed), and what follows.
	line(t, id, state, name, detail, onClick) {
		return row(t, id, { onClick })
			.child(dot(t, this.status(state)))
			.child(div().flex_none().max_w(140).truncate().text_color(t.foreground).child(name))
			.child(
				div()
					.flex_1()
					.min_w(0)
					.truncate()
					.text_color(t.dim)
					.child(detail ?? ''),
			);
	}

	attention(t, list) {
		if (!list.length) return null;
		return v_flex().children(
			list.map((a, i) =>
				this.line(
					t,
					`att-${i}`,
					a.kind,
					a.worker ?? `spec #${a.spec}`,
					a.detail,
					a.worker ? () => this.peek(a.worker) : undefined,
				),
			),
		);
	}

	workers(t, list) {
		if (!list.length) return null;
		return v_flex().children(
			list.map((w) =>
				this.line(
					t,
					`w-${w.branch}`,
					w.state,
					w.name ?? '(no agent)',
					w.branch,
					w.name ? () => this.peek(w.name) : undefined,
				).child(this.ci(t, w.pr)),
			),
		);
	}

	queue(t, list) {
		if (!list.length) return null;
		return v_flex().children(
			list.map((p, i) =>
				row(t, `q-${p.number}`)
					.child(
						div()
							.w(14)
							.flex_none()
							.text_size(TEXT.meta)
							.text_color(t.dim)
							.child(String(i + 1)),
					)
					.child(
						div()
							.flex_1()
							.min_w(0)
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
			.gap(SPACE.xs)
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
						.gap(SPACE.xs + 2)
						.p(SPACE.sm)
						.rounded(RADIUS.control)
						.bg(t.raised)
						.child(
							h_flex()
								.gap(SPACE.sm)
								.items_center()
								.child(div().flex_none().font_semibold().child(`#${s.spec}`))
								.child(div().flex_1().min_w(0).truncate().child(s.title))
								.when(s.result === 'stuck', (e) => e.child(badge(t, 'stuck', 'blocked')))
								.when(s.done, (e) => e.child(badge(t, 'all in', 'done'))),
						)
						.child(
							h_flex()
								.flex_wrap()
								.gap(SPACE.xs)
								.children(
									chips.map(([n, color, label]) =>
										chip(t, `t-${s.spec}-${n}`, color, `#${n} ${label}`),
									),
								),
						);
				}),
			);
	}

	landed(t, list) {
		if (!list.length) return null;
		return v_flex().children(
			list.map((l) =>
				row(t, `l-${l.pr}`, { onClick: l.url ? () => this.open(l.url) : undefined })
					.child(div().w(40).flex_none().text_size(TEXT.meta).text_color(t.dim).child(`#${l.pr}`))
					.child(
						div()
							.flex_1()
							.min_w(0)
							.truncate()
							.text_color(t.muted)
							.child(l.title ?? ''),
					)
					.child(div().flex_none().text_size(TEXT.meta).text_color(t.dim).child(ago(l.at))),
			),
		);
	}

	render(cx) {
		const t = theme();
		if (folder() !== this.dir) this.refresh(cx);
		const s = this.snap;
		const running = s ? Boolean(this.harnessTerminal(s.repo)) : false;
		const header = bar(t, 'harness-bar')
			.child(div().flex_none().font_semibold().child('Harness'))
			.when(Boolean(s), (e) => e.child(badge(t, s.name)))
			.child(spacer())
			.when(Boolean(s), (e) =>
				e.child(
					// Start when no harness runs here, Open to go to the one that
					// does. Drawn as every other button: a solid one, always in view
					// at the panel's head, outshone what the panel is for.
					button(t, 'start-harness', running ? 'Open' : 'Start', (_e, cx) =>
						this.startOrOpen(s.repo, cx),
					),
				),
			)
			.child(
				// Not a spinner while reading: the label says so, without motion.
				button(t, 'refresh', this.reading.has(this.dir) ? '…' : '↻', (_e, cx) => this.refresh(cx)),
			);

		let body;
		if (!s) {
			body = this.empty(t, this.error ?? (this.dir ? 'Reading the harness…' : 'No folder'));
		} else {
			body = v_flex()
				.gap(SPACE.md)
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
