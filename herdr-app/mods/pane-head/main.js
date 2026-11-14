// A pane's header: Herdr's own (mods/pane), with two changes. A Claude Code
// pane reads "Claude Code · what it is doing", from its title, rather than
// the program's name alone. And a working agent is a still dot, as
// everywhere else here, not a spinner.
//
// A Claude pane that is not a harness also offers to become its
// repository's harness (lib/harness.js).
//
// Props from the app: { pane, terminal }. Click: focus the pane.
import { View, div, svg } from 'gpui-kit';
import { h_flex } from 'gpui-base';
import { SIZE, SPACE, TEXT, button, badge, dot, title, programIcon } from './lib/ui.js';
import { panes, agents, props, run, theme, home, layout, terminals, notify } from 'herdr';
import { makeHarness } from './lib/harness.js';

// Match the first visible tab frame, including the active child of a stack.
function paneFrame(node) {
	if (!node || node.hidden) return null;
	if (node.content?.tab && node.content.pane) return node.content.pane;
	let children = node.children ?? [];
	if (node.type === 'stack') {
		const visible = children.filter((child) => !child.hidden);
		children = [visible.find((child) => child.id === node.active) ?? visible[0]];
	}
	for (const child of children) {
		const frame = paneFrame(child);
		if (frame) return frame;
	}
	return null;
}

function folder(cwd) {
	if (!cwd) return '';
	const h = home();
	return cwd === h ? '~' : cwd.startsWith(h + '/') ? '~' + cwd.slice(h.length) : cwd;
}

const isClaude = (p) =>
	Boolean(p?.terminal) && (p.app === 'claude-code' || p.program?.key === 'claude');

export default class PaneHead extends View {
	init() {
		this.hovered = false;
	}

	me() {
		return panes().find((p) => p.pane === props()?.pane);
	}

	render() {
		const t = theme();
		const p = this.me();
		if (!p) return div();
		const claude = isClaude(p) ? p : null;
		const agent = claude ? agents().find((a) => a.address === claude.terminal) : null;
		const program = claude?.program ?? p.program;
		const name = claude
			? 'Claude Code'
			: ((p.program?.agent || p.program?.shell) && p.program.name) ||
				// A mod pane is titled by its mod's name: "issue" reads as "Issue".
				(p.mod ? p.mod[0].toUpperCase() + p.mod.slice(1) : p.title) ||
				p.program?.name ||
				'shell';
		// What Claude Code is doing, from its title without the glyph in front.
		const doing = agent?.title?.replace(/^[^\p{L}\p{N}]+/u, '').trim();
		const detail = claude ? doing || folder(claude.cwd) : folder(p.cwd);
		const pic = programIcon(t, program, 14);
		const st = claude?.status ?? p.status;
		const pane = p.pane;
		const bottom = paneFrame(layout())?.header?.position === 'bottom';
		// A Claude not yet any repository's harness can be made one.
		const harness = claude
			? terminals().find((x) => x.address === claude.terminal)?.labels?.harness
			: null;
		const canMake = Boolean(claude) && !harness;
		const controls = canMake ? 5 : 4;
		const paneButton = (id, name, command, args) =>
			button(t, `ph-${id}-${pane}`, svg(`mods/pane/${name}.svg`).size(14), () =>
				run(command, args),
			);
		return (
			h_flex()
				.id(`pane-head-${pane}`)
				.size_full()
				.px(SPACE.md)
				.gap(SPACE.sm)
				.items_center()
				.bg(t.background)
				.when(bottom, (el) => el.border_t(1))
				.when(!bottom, (el) => el.border_b(1))
				.border_color(t.border)
				.text_size(TEXT.ui)
				.on_hover((hovered, cx) => {
					this.hovered = hovered;
					cx.notify();
				})
				.on_click(() => run('pane.focus', { pane }))
				.when(Boolean(pic), (el) => el.child(pic))
				.child(title(t, name, detail))
				.when(st === 'blocked', (el) => el.child(badge(t, 'Needs you', 'blocked')))
				.when(st === 'working' || st === 'done', (el) => el.child(dot(t, st)))
				// The pane buttons keep their room while hidden, so showing them on
				// hover does not push the title and the status aside: four
				// controls (five with Make harness) and the gaps between them.
				.child(
					h_flex()
						.flex_none()
						.w(controls * SIZE.control + (controls - 1) * 2)
						.gap(2)
						.justify_end()
						.when(this.hovered, (el) =>
							el
								.when(canMake, (el) =>
									el.child(
										button(
											t,
											`ph-h-${pane}`,
											svg('mods/harness/harness.svg').size(14),
											async () => {
												const said = await makeHarness(claude.terminal, claude.cwd);
												if (said !== 'made')
													notify({ title: 'Not made the harness', body: said, level: 'warning' });
											},
											{ title: 'Make this Claude its repository’s harness' },
										),
									),
								)
								.child(paneButton('r', 'split-right', 'pane.split', { direction: 'right', pane }))
								.child(paneButton('d', 'split-down', 'pane.split', { direction: 'down', pane }))
								.child(paneButton('z', p.zoomed ? 'unzoom' : 'zoom', 'pane.zoom', { pane }))
								.child(paneButton('x', 'close', 'pane.close', { pane })),
						),
				)
		);
	}
}
