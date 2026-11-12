// A pane's header: Herdr's own (mods/pane), with two changes. A Claude Code
// pane, and the chat pane that shows the same Claude (mods/chat), both read
// "Claude Code · what it is doing" with a Chat | Terminal switch, so the two
// views of one agent look like one thing with two faces. And a working agent
// is a still dot, as everywhere else here, not a spinner.
//
// Props from the app: { pane, terminal }. Click: focus the pane.
import { View, div, svg, image } from 'gpui-kit';
import { h_flex } from 'gpui-base';
import { SIZE, SPACE, TEXT, button, segmented, badge, dot, title } from './lib/ui.js';
import { panes, agents, props, run, theme, home, layout, setShared, shared } from 'herdr';

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

function icon(p, size, color) {
	if (!p?.icon) return null;
	return p.tint
		? svg(p.icon).size(size).flex_none().text_color(color)
		: image(p.icon).w(size).h(size).flex_none();
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
		const here = panes().filter((x) => x.tab === p.tab);
		// The Claude this header is about: the pane itself, or the one its chat shows.
		// A chat's own Claude, by the pairing harness-tabs made when it made
		// the chat; the tab's first Claude for a chat made before that.
		const paired = p.mod === 'chat' ? (shared('chat-pairs') ?? {})[p.pane] : null;
		const claude = isClaude(p)
			? p
			: p.mod === 'chat'
				? (here.find((x) => x.terminal && x.terminal === paired) ?? here.find(isClaude))
				: null;
		const agent = claude ? agents().find((a) => a.address === claude.terminal) : null;
		const program = claude?.program ?? p.program;
		const name = claude
			? 'Claude Code'
			: ((p.program?.agent || p.program?.shell) && p.program.name) ||
				p.title ||
				p.program?.name ||
				'shell';
		// What Claude Code is doing, from its title without the glyph in front.
		const doing = agent?.title?.replace(/^[^\p{L}\p{N}]+/u, '').trim();
		const detail = claude ? doing || folder(claude.cwd) : folder(p.cwd);
		const pic = icon(program, 14, t.dim);
		const st = claude?.status ?? p.status;
		const pane = p.pane;
		const bottom = paneFrame(layout())?.header?.position === 'bottom';
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
				// Chat | Terminal: the two views of one Claude. harness-tabs switches
				// the tab between them, and makes the chat the first time.
				.when(Boolean(claude), (el) =>
					el.child(
						segmented(
							t,
							`ph-view-${pane}`,
							[
								{ key: 'chat', label: 'Chat' },
								{ key: 'terminal', label: 'Terminal' },
							],
							p.mod === 'chat' ? 'chat' : 'terminal',
							// Which pane asked, so the switch is about this Claude
							// when a tab holds two.
							(want) => {
								setShared('chat-origin', { pane, want });
								run('harness-tabs.chat');
							},
						),
					),
				)
				// The pane buttons keep their room while hidden, so showing them on
				// hover does not push the switcher and the status aside: four
				// controls and the gaps between them.
				.child(
					h_flex()
						.flex_none()
						.w(4 * SIZE.control + 3 * 2)
						.gap(2)
						.justify_end()
						.when(this.hovered, (el) =>
							el
								.child(paneButton('r', 'split-right', 'pane.split', { direction: 'right', pane }))
								.child(paneButton('d', 'split-down', 'pane.split', { direction: 'down', pane }))
								.child(paneButton('z', p.zoomed ? 'unzoom' : 'zoom', 'pane.zoom', { pane }))
								.child(paneButton('x', 'close', 'pane.close', { pane })),
						),
				)
		);
	}
}
