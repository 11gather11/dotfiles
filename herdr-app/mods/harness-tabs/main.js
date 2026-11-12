import { View, div, svg, image } from 'gpui-kit';
import { h_flex, ScrollHandle } from 'gpui-base';
import { SIZE, SPACE, TEXT, RADIUS, button as uiButton } from './lib/ui.js';
import {
	spaces,
	panes,
	run,
	openOverlay,
	theme,
	window,
	shared,
	layout,
	settings,
	nextCommand,
	focused,
	setShared,
} from 'herdr';

// Herdr's own tab bar, with two changes. The side panel's buttons are the
// children of the layout's `panel-body` stack, not Files and Changes written
// into the code: a panel is added by putting its block in that stack. And a
// tab nobody named shows its agent's title rather than its program's name
// (see titleOf), so two Claude tabs say what each is about.
//
// Label and icon of the panels known here; another child shows its id.
const PANELS = {
	files: { label: 'Files', icon: 'mods/files/file.svg' },
	changes: { label: 'Changes', icon: 'mods/changes/changes.svg' },
	harness: { label: 'Harness', icon: 'mods/harness/harness.svg' },
};
/**
 * An agent pane's title without the status glyph Claude Code puts in front
 * ("✳ Fix login"), or null when it has none worth showing.
 *
 * @param {import('herdr').PaneInfo|undefined} pane
 * @returns {string|null}
 * @example
 * titleOf({ title: "✳ Fix login" }) // => "Fix login"
 */
function titleOf(pane) {
	const title = (pane?.title ?? '').replace(/^[^\p{L}\p{N}]+/u, '').trim();
	// Before its first title the terminal shows its program's own name.
	return title && title !== pane.program?.name && title.toLowerCase() !== 'claude' ? title : null;
}

// Settings → Look turns these two on and off through `workspace.panels`;
// panels Herdr does not ship are not in that list and always show.
const SHIPPED = ['files', 'changes'];

function find(node, id) {
	if (node?.id === id) return node;
	for (const child of node?.children ?? []) {
		const found = find(child, id);
		if (found) return found;
	}
	return null;
}

export default class Tabs extends View {
	init(_props, cx) {
		this.pressed = null;
		this.scroll = ScrollHandle.new();
		this.panels = JSON.parse(localStorage.getItem('panels') ?? '{}');
		// Chat pane => the terminal of the Claude it shows (see chatPanes).
		this.pairs = JSON.parse(localStorage.getItem('chat-pairs') ?? '{}');
		// The pane headers read it too, to name each chat's own Claude.
		setShared('chat-pairs', this.pairs);
		// "harness-tabs.<panel id>" in keys.json opens that panel, or closes it
		// when it is the one shown.
		cx.spawn(async (cx) => {
			for (;;) {
				const id = await nextCommand();
				if (id === 'chat') this.chat(cx);
				else {
					const root = layout();
					this.toggle(find(root, 'panel'), find(root, 'panel-body'), id);
				}
				cx.notify();
			}
		});
	}

	/**
	 * The shown tab's Claude and its chat pane (mods/chat), if any. The chat
	 * pane belongs to the agent pane it was opened beside.
	 */
	/**
	 * The Claude pane the switch is about and its chat pane (mods/chat), in
	 * the shown tab. `origin` is the pane it was asked from (a pane header
	 * says which, through shared 'chat-origin'), else the focused one: with
	 * two Claudes in a tab, each keeps its own chat. Which chat shows which
	 * Claude is remembered when the chat is made.
	 */
	chatPanes(origin) {
		const tab = spaces()
			.find((s) => s.active)
			?.tabs.find((c) => c.active)?.id;
		const here = panes().filter((p) => p.tab === tab);
		const isClaude = (p) => p.terminal && (p.app === 'claude-code' || p.program?.key === 'claude');
		const from = here.find((p) => p.pane === origin);
		const chats = here.filter((p) => p.mod === 'chat');
		if (from?.mod === 'chat')
			return {
				chat: from,
				agent:
					here.find((p) => p.terminal && p.terminal === this.pairs[from.pane]) ??
					here.find(isClaude),
			};
		const agent = from && isClaude(from) ? from : here.find(isClaude);
		// Its own chat, else one made before chats were remembered.
		const chat =
			chats.find((c) => this.pairs[c.pane] === agent?.terminal) ??
			chats.find((c) => !(c.pane in this.pairs));
		return { agent, chat };
	}

	// "harness-tabs.chat": the Claude's conversation, or back to its
	// terminal. Both stay in the tab and the one shown is zoomed, so the
	// terminal keeps running (and keeps its place) behind the chat. The first
	// time, the chat pane is split off beside the terminal.
	chat(cx) {
		// A pane header names its pane; a chat names its Claude's terminal.
		// { pane } from a pane header, { terminal } from a chat, with the view
		// wanted ('chat' or 'terminal'); from a key, nothing: the other view.
		const asked = shared('chat-origin') ?? {};
		const origin =
			(asked.terminal ? panes().find((p) => p.terminal === asked.terminal)?.pane : asked.pane) ??
			focused()?.pane ??
			null;
		if (shared('chat-origin')) setShared('chat-origin', null);
		const { agent, chat } = this.chatPanes(origin);
		if (!chat) {
			if (!agent) return;
			const before = new Set(panes().map((p) => p.pane));
			run('pane.split', {
				pane: agent.pane,
				direction: 'right',
				mod: 'chat',
				props: { terminal: agent.terminal },
			});
			// The new pane is listed once the split has landed.
			cx.timer.after(150, () => {
				const made = panes().find((p) => p.mod === 'chat' && !before.has(p.pane));
				if (!made) return;
				this.pairs[made.pane] = agent.terminal;
				localStorage.setItem('chat-pairs', JSON.stringify(this.pairs));
				setShared('chat-pairs', this.pairs);
				run('pane.zoom', { pane: made.pane });
				run('pane.focus', { pane: made.pane });
			});
			return;
		}
		const to =
			asked.want === 'terminal' ? agent : asked.want === 'chat' ? chat : chat.zoomed ? agent : chat;
		if (!to) {
			run('pane.zoom', { pane: chat.pane });
			return;
		}
		const zoomed = panes().find((p) => p.tab === chat.tab && p.zoomed);
		if (zoomed && zoomed.pane !== to.pane) run('pane.zoom', { pane: zoomed.pane });
		if (!to.zoomed) run('pane.zoom', { pane: to.pane });
		run('pane.focus', { pane: to.pane });
	}

	toggle(panel, body, id) {
		if (!panel || !body?.children?.some((c) => c.id === id)) return;
		if (!panel.hidden && body.active === id) run('layout.hide', { id: 'panel' });
		else {
			run('layout.select', { stack: 'panel-body', child: id });
			run('layout.show', { id: 'panel' });
		}
	}

	// The side panel is remembered per space: switching shows that space's choice
	// (closed if it never had one), and opening or closing it records it.
	syncPanel(space, panel, body, enabled) {
		if (!space || !panel) return;
		const now = panel.hidden ? null : (body?.active ?? null);
		if (space.id !== this.space) {
			const first = this.space === undefined;
			this.space = space.id;
			this.pending = null;
			if (!(first && !(space.id in this.panels))) {
				const stored = this.panels[space.id] ?? null,
					want = enabled.includes(stored) ? stored : null;
				if (want !== now) {
					this.pending = { want, until: Date.now() + 1000 };
					if (want) {
						run('layout.select', { stack: 'panel-body', child: want });
						run('layout.show', { id: 'panel' });
					} else run('layout.hide', { id: 'panel' });
					return;
				}
			}
		}
		// Until the restore lands (or something else won), the old state isn't a choice.
		if (this.pending) {
			if (this.pending.want !== now && Date.now() < this.pending.until) return;
			this.pending = null;
		}
		if (this.panels[space.id] === now) return;
		this.panels[space.id] = now;
		localStorage.setItem('panels', JSON.stringify(this.panels));
	}

	render() {
		const t = theme();
		const space = spaces().find((p) => p.active);
		const shown = space?.tabs ?? [];
		const active = shown.findIndex((tab) => tab.active);
		const selected = shown[active]?.id;
		if (selected !== this.selected || active !== this.selectedIndex) {
			this.selected = selected;
			this.selectedIndex = active;
			if (active >= 0) this.scroll.scroll_to_item(active);
		}
		const stop = (_e, cx) => cx.stop_propagation();
		const button = (id, label, action) => uiButton(t, id, label, action);
		const item = (c, i) => {
			const agent = panes().find((p) => p.tab === c.id && p.program?.agent);
			const program = agent?.program ?? panes().find((p) => p.tab === c.id)?.program;
			// A tab nobody named shows what its agent says it is doing (the
			// terminal title Claude Code keeps current), else its program. A tab
			// the + menu opened carries its program's name ("Claude Code"),
			// which says no more than the icon, so it counts as unnamed. Shown,
			// not written as the tab's name: a name typed by hand still wins, and
			// the title is followed as it changes.
			const unnamed = !c.named || c.name === program?.name;
			const name = unnamed ? (titleOf(agent) ?? program?.name ?? 'Terminal') : c.name;
			return (
				h_flex()
					.id(`tab-${c.id}`)
					.h(SIZE.row)
					.px(SPACE.md - 2)
					.gap(SPACE.xs + 2)
					.rounded(RADIUS.control)
					.items_center()
					.flex_none()
					.text_size(TEXT.ui)
					// A rename or status dot on this or an earlier tab can push the active one out.
					.when(i <= active, (el) =>
						el.on_size_change((_size, cx) => {
							this.scroll.scroll_to_item(active);
							cx.notify();
						}),
					)
					.border(1)
					.border_color(c.active ? t.border : t.chrome)
					.bg(c.active ? t.raised : t.chrome)
					.text_color(c.active ? t.foreground : t.muted)
					.hover((s) => s.bg(t.hover))
					.on_mouse_down('left', (e, cx) => {
						cx.stop_propagation();
						this.pressed = i;
						if (e.click_count === 2) run('tab.rename', { id: c.id });
					})
					.on_mouse_up('left', () => {
						const from = this.pressed;
						this.pressed = null;
						if (from !== null && from !== i)
							run('tab.move', {
								id: shown[from].id,
								index: space.tabs.findIndex((x) => x.id === c.id) + 1,
							});
						else run('tab.select', { id: c.id });
					})
					.on_mouse_down('right', (_e, cx) => {
						cx.stop_propagation();
						openOverlay({
							mod: 'menu',
							kind: 'popup',
							width: 200,
							props: { tab: 'tab', target: { id: c.id, space: space.id } },
						});
					})
					.when(Boolean(program?.icon), (el) =>
						el.child(
							program.tint
								? svg(program.icon).size(14).text_color(t.muted)
								: image(program.icon).size(14),
						),
					)
					.child(
						div()
							.max_w(170)
							.truncate()
							// Z marks a zoomed tab, except one with a chat: its Chat and
							// Terminal views are shown by zooming, so there it is the rule.
							.child(
								c.zoomed && !panes().some((p) => p.tab === c.id && p.mod === 'chat')
									? `${name} Z`
									: name,
							),
					)
					.when(c.status === 'working', (el) =>
						el.child(
							// A still dot, as in the herdr TUI: working needs nothing from you.
							div().size(6).flex_none().rounded(3).bg(t.working),
						),
					)
					.when(c.status === 'blocked' || c.status === 'done', (el) =>
						el.child(div().size(6).rounded(3).bg(t[c.status])),
					)
					.when(c.active, (el) =>
						el.child(
							div()
								.id(`close-${c.id}`)
								.text_color(t.dim)
								.on_mouse_down('left', stop)
								.on_click((_e, cx) => {
									cx.stop_propagation();
									run('tab.close', { id: c.id });
								})
								.child(svg('mods/pane/close.svg').size(12)),
						),
					)
			);
		};
		const root = layout(),
			sidebar = find(root, 'sidebar'),
			w = window();
		// Old saved rails and a dragged-narrow sidebar can be smaller than the window buttons.
		const lightsPadding =
			w?.platform === 'macos' && w.titlebar === 'none' && !w.fullscreen && root?.traffic_lights
				? Math.max(
						10,
						(root.traffic_lights[0] + 64) / settings().zoom -
							(sidebar?.hidden ? 0 : (sidebar?.size?.px ?? 0)),
					)
				: 10;
		const panel = find(root, 'panel'),
			body = find(root, 'panel-body');
		const shipped = shared('workspace.panels') ?? SHIPPED;
		const enabled = (body?.children ?? [])
			.map((c) => c.id)
			.filter((id) => !SHIPPED.includes(id) || shipped.includes(id));
		this.syncPanel(space, panel, body, enabled);
		const panelButton = (id, label, icon) => {
			const on = panel && !panel.hidden && body?.active === id;
			return uiButton(t, `panel-${id}`, label, () => this.toggle(panel, body, id), {
				kind: on ? 'selected' : 'ghost',
				icon,
			});
		};
		return h_flex()
			.size_full()
			.min_w(0)
			.px(SPACE.sm)
			.pl(lightsPadding)
			.gap(SPACE.xs)
			.items_center()
			.bg(t.chrome)
			.border_b(1)
			.border_color(t.border)
			.on_mouse_up('left', () => {
				this.pressed = null;
			})
			.on_scroll_wheel((e) => {
				if (Math.abs(e.delta.y) >= 1) run(e.delta.y > 0 ? 'tab.prev' : 'tab.next');
			})
			.child(
				h_flex()
					.id('tab-scroll')
					.flex_1()
					.min_w(0)
					.h_full()
					.items_center()
					.gap(SPACE.xs)
					.overflow_x_scrollbar()
					.track_scroll(this.scroll)
					.on_size_change((_size, cx) => {
						if (active >= 0) {
							this.scroll.scroll_to_item(active);
							cx.notify();
						}
					})
					.children(shown.map(item)),
			)
			.child(
				button('tab-new', '+', () =>
					openOverlay({ mod: 'new-menu', kind: 'popup', width: 250, height: 512 }),
				),
			)
			.children(enabled.map((id) => panelButton(id, PANELS[id]?.label ?? id, PANELS[id]?.icon)))
			.when(w?.buttons, (el) =>
				el
					.child(
						button(
							'minimize',
							w.platform === 'windows' ? svg('mods/tabs/win-min.svg').size(16) : '−',
							() => run('window.minimize'),
						),
					)
					.child(
						button(
							'maximize',
							w.platform === 'windows'
								? svg(`mods/tabs/${w.maximized ? 'win-restore' : 'win-max'}.svg`).size(16)
								: '□',
							() => run('window.maximize'),
						),
					)
					.child(
						button(
							'close-window',
							w.platform === 'windows'
								? svg('mods/tabs/win-close.svg').size(16)
								: svg('mods/pane/close.svg').size(13),
							() => run('window.close'),
						),
					),
			);
	}
}
