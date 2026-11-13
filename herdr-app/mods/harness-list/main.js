// Every running harness, one line each, in the sidebar: which repositories
// have one, and whether any of their workers needs the person. The Harness
// panel shows one repository in full; this is what stays in view whichever
// repository is in front. Click a line to go to that harness, with the panel
// open on it.
//
// A running harness is a terminal labelled harness=<repository> (the
// `harness` command in herdr-app.nix) with Claude in front. Each line's
// numbers come from `harness-status`, as the panel's do.
import { View, div } from 'gpui-kit';
import { v_flex, h_flex } from 'gpui-base';
import { exec, run, theme, notify, shared, setShared } from 'herdr';
import { SIZE, SPACE, TEXT, dot, row } from './lib/ui.js';
import { focusedFolder } from './lib/focus.js';
import { runningHarnesses } from './lib/harness.js';

// harness-status takes about two seconds a repository (GitHub, every
// worker's screen), so each is read this often; which harnesses run is a
// look at terminals(), cheap enough to take every few seconds.
const POLL_MS = 30000;
const LOOK_MS = 3000;
// Under the rows, so the agents list below does not touch the last one.
const PAD = SPACE.xs;

/** A stable key for an attention entry, to tell new ones from ones already shown. */
const attentionKey = (a) => `${a.kind}:${a.worker ?? a.spec}:${a.detail}`;

/**
 * A harness's line status, the most pressing of its workers': one blocked
 * or stuck, then one stopped with something to look at, then one working.
 *
 * @param {any} snap a harness-status snapshot
 * @returns {'blocked' | 'done' | 'working' | 'idle'}
 */
function statusOf(snap) {
	const kinds = new Set(snap.attention.map((a) => a.kind));
	if (kinds.has('blocked') || kinds.has('stuck')) return 'blocked';
	if (snap.attention.length) return 'done';
	if (snap.workers.some((w) => w.state === 'working' || w.state === 'busy')) return 'working';
	return 'idle';
}

export default class HarnessList extends View {
	init(_props, cx) {
		this.harnesses = new Map(); // repository => terminal address
		this.snaps = new Map(); // repository => its last snapshot
		this.seen = new Map(); // repository => attention keys already announced
		this.reading = new Set();
		this.look(cx);
		cx.timer.every(LOOK_MS, (cx) => this.look(cx));
		cx.timer.every(POLL_MS, (cx) => this.harnesses.forEach((_a, repo) => this.read(repo, cx)));
	}

	// Picks up harnesses started or ended since the last look; a new one is
	// read at once rather than at the next poll.
	look(cx) {
		const now = runningHarnesses();
		const same =
			now.size === this.harnesses.size &&
			[...now].every(([repo, address]) => this.harnesses.get(repo) === address);
		if (same) return;
		for (const repo of now.keys()) if (!this.snaps.has(repo)) this.read(repo, cx);
		for (const repo of this.snaps.keys()) if (!now.has(repo)) this.snaps.delete(repo);
		this.harnesses = now;
		this.fit();
		cx.notify();
	}

	read(repo, cx) {
		if (this.reading.has(repo)) return;
		this.reading.add(repo);
		cx.spawn(async (cx) => {
			try {
				const r = await exec('harness-status', ['--dir', repo, '--mux', 'hc']);
				const line = r.stdout.trim().split('\n').pop();
				if (r.code !== 0 || !line || !this.harnesses.has(repo)) return;
				const snap = JSON.parse(line);
				this.announce(repo, snap.attention);
				this.snaps.set(repo, snap);
				// What the Issues panel marks each issue with: who works on it, which
				// spec it is in, whether it landed.
				setShared('harness.snaps', {
					...(shared('harness.snaps') ?? {}),
					[repo]: { workers: snap.workers, specs: snap.specs, queue: snap.queue, at: snap.at },
				});
			} catch {
				// Keeps the line's last numbers; the next poll asks again.
			} finally {
				this.reading.delete(repo);
				cx.notify();
			}
		});
	}

	// A worker that newly needs the person is worth a notification whichever
	// repository is in front; a harness's first snapshot only sets the
	// baseline. Here rather than in the panel, which reads one repository.
	announce(repo, attention) {
		const seen = this.seen.get(repo);
		if (seen) {
			for (const a of attention) {
				if (seen.has(attentionKey(a))) continue;
				notify({
					title: a.worker ? `${a.worker} ${a.kind}` : `spec #${a.spec} ${a.kind}`,
					body: a.detail,
					level: a.kind === 'blocked' ? 'warning' : 'info',
				});
			}
		}
		this.seen.set(repo, new Set(attention.map(attentionKey)));
	}

	// The block is as tall as its lines, and hidden with none, so the agents
	// list starts right under it. Run on a change of harnesses, not in render.
	fit() {
		const n = this.harnesses.size;
		if (n === this.fitted) return;
		this.fitted = n;
		if (!n) {
			run('layout.hide', { id: 'harnesses' });
			return;
		}
		run('layout.resize', { id: 'harnesses', px: SIZE.row * (n + 1) + PAD });
		run('layout.show', { id: 'harnesses' });
	}

	// To the harness's terminal, which brings its repository in front, so the
	// panel, following the focused folder, shows it.
	go(address) {
		run('agent.focus', { terminal: address });
		run('layout.select', { stack: 'panel-body', child: 'harness' });
		run('layout.show', { id: 'panel' });
	}

	// "1 needs you" when a worker does, else the workers and their PRs;
	// nothing for a harness without workers, the quiet case.
	tail(t, snap) {
		if (!snap) return div().flex_none().text_size(TEXT.meta).text_color(t.dim).child('…');
		const needs = snap.attention.length;
		const n = snap.workers.length;
		const prs = snap.workers.filter((w) => w.pr).length;
		const text = needs
			? `${needs} needs you`
			: n
				? [`${n} ${n === 1 ? 'worker' : 'workers'}`, prs ? `${prs} PR` : '']
						.filter(Boolean)
						.join(' · ')
				: '';
		return div()
			.flex_none()
			.text_size(TEXT.meta)
			.text_color(needs ? t.foreground : t.dim)
			.child(text);
	}

	render() {
		const t = theme();
		const here = focusedFolder() ?? '';
		const repos = [...this.harnesses.keys()].sort();
		return v_flex()
			.id('harness-list')
			.size_full()
			.min_h(0)
			.px(SPACE.sm)
			.child(
				// Written as the Spaces and Agents headings around it are.
				h_flex()
					.h(SIZE.row)
					.flex_none()
					.px(SPACE.sm)
					.gap(SPACE.sm)
					.items_center()
					.text_size(TEXT.meta)
					.text_color(t.dim)
					.child('Harness')
					.child(String(repos.length)),
			)
			.children(
				repos.map((repo) => {
					const snap = this.snaps.get(repo);
					// A worker's worktree sits beside the checkout as <repo>.<branch>.
					const selected =
						here === repo || here.startsWith(`${repo}.`) || here.startsWith(`${repo}/`);
					return (
						row(t, `h-${repo}`, { selected, onClick: () => this.go(this.harnesses.get(repo)) })
							.child(
								div()
									.flex_1()
									.min_w(0)
									.truncate()
									.text_color(t.foreground)
									.child(snap?.name ?? repo.split('/').pop()),
							)
							.child(this.tail(t, snap))
							// At the end, where the Spaces and Agents rows have theirs.
							.child(dot(t, snap ? statusOf(snap) : null))
					);
				}),
			);
	}
}
