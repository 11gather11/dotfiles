// Every agent on one line each, most urgent first: what it is doing (its
// terminal's title), the space it is in, and its status as the herdr TUI marks
// it. Click to go to it.
//
// Written in place of Herdr's `agents` mod, which groups agents under a
// header per space: with the spaces sidebar already showing each space's
// status, those headers spent half the height repeating it.
import { View, div } from 'gpui-kit';
import { v_flex, h_flex } from 'gpui-base';
import { agents, run, theme, setAgentOrder, exec } from 'herdr';
import { SIZE, SPACE, TEXT, RADIUS, dot } from './lib/ui.js';

// How often to look for a conversation a terminal lost; see init.
const RESUME_MS = 5000;

// Higher first: what needs you, then what finished unseen, then what runs.
const RANK = { blocked: 3, done: 2, working: 1, idle: 0 };

/**
 * The agents in display order: pinned ones on top, then by urgency, then the
 * most recently changed.
 *
 * @param {import('herdr').AgentInfo[]} list
 * @returns {import('herdr').AgentInfo[]}
 */
function ordered(list) {
	return [...list].sort(
		(x, y) =>
			Number(y.pinned) - Number(x.pinned) ||
			(RANK[y.status] ?? 0) - (RANK[x.status] ?? 0) ||
			y.seq - x.seq,
	);
}

/**
 * What a row calls an agent: its terminal's title without the status glyph
 * Claude Code puts in front ("✳ Port WebGL…"), else its tab's or program's
 * name.
 *
 * @param {import('herdr').AgentInfo} a
 * @returns {string}
 * @example
 * label({ title: "✳ Fix login", tab_name: "1" }) // => "Fix login"
 */
function label(a) {
	const title = (a.title ?? '').replace(/^[^\p{L}\p{N}]+/u, '').trim();
	return title || a.tab_name || a.program?.name || a.address;
}

export default class AgentsCompact extends View {
	// Starts Claude again in terminals that lost it to a stopped core or a
	// restart (claude-resume, herdr-app.nix). Here because this panel is up
	// whenever the window is: from the start, which covers a restart, and
	// while the core is stopped and started under it.
	init(_props, cx) {
		const resume = () => exec('claude-resume', []).catch(() => null);
		resume();
		cx.timer.every(RESUME_MS, resume);
	}

	// The status mark, the same as everywhere (lib/ui.js): a still dot, a ring
	// when idle.
	mark(t, status) {
		return dot(t, status);
	}

	render() {
		const t = theme();
		const list = ordered(agents());
		setAgentOrder(list.map((a) => a.address));
		return v_flex()
			.id('agents-compact')
			.size_full()
			.min_h(0)
			.text_size(TEXT.ui)
			.child(
				h_flex()
					.h(SIZE.row)
					.flex_none()
					.px(16)
					.gap(SPACE.sm)
					.items_center()
					.child(div().text_size(TEXT.meta).text_color(t.dim).child('Agents'))
					.when(list.length > 0, (el) =>
						el.child(div().text_size(TEXT.meta).text_color(t.dim).child(String(list.length))),
					),
			)
			.child(
				v_flex()
					.id('agents-compact-list')
					.flex_1()
					.min_h(0)
					.px(8)
					.overflow_y_scroll()
					.when(list.length === 0, (el) =>
						el.child(div().px(8).text_color(t.dim).child('No agents')),
					)
					.children(
						list.map((a) =>
							h_flex()
								.id(`agent-${a.address}`)
								.h(SIZE.row)
								.flex_none()
								.px(8)
								.gap(SPACE.sm)
								.items_center()
								.rounded(RADIUS.control)
								.when(a.focused, (el) => el.bg(t.selected))
								.when(!a.focused, (el) => el.hover((s) => s.bg(t.hover)))
								.on_click(() => run('agent.focus', { terminal: a.address }))
								.child(
									div()
										.flex_1()
										.min_w(0)
										.truncate()
										.text_color(a.status === 'idle' ? t.muted : t.foreground)
										.child(label(a)),
								)
								.child(
									div()
										.flex_none()
										.max_w(80)
										.truncate()
										.text_size(TEXT.meta)
										.text_color(t.dim)
										.child(a.space_name),
								)
								.child(this.mark(t, a.status)),
						),
					),
			);
	}
}
