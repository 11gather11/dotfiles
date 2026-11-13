// The window's parts, drawn one way everywhere: every bar, row, button and
// badge of the mods here comes from this file, so their heights line up
// across panels and a change of look is made once. Copied into each mod that
// imports it; see markdown.js.
//
// Colours are the theme's (`theme()`), passed in as `t`.
import { div, svg } from 'gpui-kit';
import { h_flex, v_flex, Scrollbar } from 'gpui-base';

/** Heights (px). A bar heads a pane or panel; the layout's tab bar has it too. */
export const SIZE = { bar: 36, row: 26, control: 24, badge: 20, dot: 7 };
/** The only gaps and paddings used (px). */
export const SPACE = { xs: 4, sm: 8, md: 12, lg: 16 };
/** The only text sizes: notes and counts, controls, reading text. */
export const TEXT = { meta: 11, ui: 12, body: 13 };
/** Corner radii: controls and rows, cards and bubbles. */
export const RADIUS = { control: 6, card: 10 };

// A press on a control is the control's: the pane under it (focus, drag) does
// not also get it.
const stop = (_e, cx) => cx.stop_propagation();

/**
 * The bar that heads a pane or a panel: one line, SIZE.bar high, a rule
 * under it. Children go left to right; put `spacer()` before what sits right.
 *
 * @param {Record<string, string>} t theme
 * @param {string} id
 */
export function bar(t, id) {
	return h_flex()
		.id(id)
		.h(SIZE.bar)
		.flex_none()
		.px(SPACE.md)
		.gap(SPACE.sm)
		.items_center()
		.border_b(1)
		.border_color(t.border)
		.text_size(TEXT.ui);
}

/** Takes the room left in a bar or row, pushing what follows to the right. */
export function spacer() {
	return div().flex_1().min_w(0);
}

/**
 * A bar's title: its name, and what it is about, dimmed and cut to fit.
 *
 * @param {Record<string, string>} t
 * @param {string} name
 * @param {string} [detail]
 */
export function title(t, name, detail) {
	return h_flex()
		.flex_1()
		.min_w(0)
		.gap(SPACE.sm)
		.items_center()
		.child(div().flex_none().font_semibold().text_color(t.foreground).child(name))
		.when(Boolean(detail), (e) =>
			e.child(div().min_w(0).truncate().text_color(t.dim).child(detail)),
		);
}

/**
 * A button. `ghost` (the default) has no frame until hovered; `selected` is
 * the one chosen of several; `primary` is the one action a view is for.
 * `label` is text, or an element (an icon); `icon` is an SVG path put before
 * the text.
 *
 * @param {Record<string, string>} t
 * @param {string} id
 * @param {string | object} label
 * @param {(e: any, cx: any) => void} onClick
 * @param {{ kind?: 'ghost' | 'selected' | 'primary', icon?: string, title?: string }} [opts]
 */
export function button(t, id, label, onClick, opts = {}) {
	const kind = opts.kind ?? 'ghost';
	return h_flex()
		.id(id)
		.h(SIZE.control)
		.flex_none()
		.px(typeof label === 'string' ? SPACE.sm : SPACE.xs)
		.gap(SPACE.xs + 1)
		.items_center()
		.justify_center()
		.rounded(RADIUS.control)
		.text_size(TEXT.ui)
		.cursor_pointer()
		.when(kind === 'ghost', (e) =>
			e.text_color(t.muted).hover((s) => s.bg(t.hover).text_color(t.foreground)),
		)
		.when(kind === 'selected', (e) => e.bg(t.selected).text_color(t.foreground))
		.when(kind === 'primary', (e) =>
			e
				.bg(t.solid)
				.text_color(t.solid_foreground)
				.hover((s) => s.opacity(0.85)),
		)
		.on_mouse_down('left', stop)
		.on_click((e, cx) => {
			cx.stop_propagation();
			onClick(e, cx);
		})
		.when(Boolean(opts.icon), (e) => e.child(svg(opts.icon).size(14).flex_none()))
		.child(label);
}

/**
 * One of several, as buttons side by side in a frame: Chat | Terminal.
 *
 * @param {Record<string, string>} t
 * @param {string} id
 * @param {{ key: string, label: string }[]} options
 * @param {string} active the chosen option's key
 * @param {(key: string, cx: any) => void} onPick called for the others only
 */
export function segmented(t, id, options, active, onPick) {
	return h_flex()
		.id(id)
		.flex_none()
		.h(SIZE.control + 4)
		.p(2)
		.gap(2)
		.items_center()
		.rounded(RADIUS.control + 2)
		.border_1()
		.border_color(t.border)
		.children(
			options.map((o) =>
				h_flex()
					.id(`${id}-${o.key}`)
					.h(SIZE.control - 2)
					.px(SPACE.md - 2)
					.items_center()
					.rounded(RADIUS.control)
					.text_size(TEXT.ui)
					.cursor_pointer()
					.when(o.key === active, (e) => e.bg(t.selected).text_color(t.foreground))
					.when(o.key !== active, (e) =>
						e.text_color(t.dim).hover((s) => s.text_color(t.foreground)),
					)
					.on_mouse_down('left', stop)
					.on_click((_e, cx) => {
						cx.stop_propagation();
						if (o.key !== active) onPick(o.key, cx);
					})
					.child(o.label),
			),
		);
}

/**
 * A short label beside a title: a count, a repository, "Needs you".
 * `neutral` is grey; the others take the status colours.
 *
 * @param {Record<string, string>} t
 * @param {string} text
 * @param {'neutral' | 'blocked' | 'working' | 'done' | 'accent'} [tone]
 */
export function badge(t, text, tone = 'neutral') {
	const color = tone === 'neutral' ? t.muted : t[tone];
	return h_flex()
		.flex_none()
		.h(SIZE.badge)
		.px(SPACE.sm - 2)
		.items_center()
		.rounded(RADIUS.control - 1)
		.bg(tone === 'neutral' ? t.hover : `${t[tone]}26`)
		.text_size(TEXT.meta)
		.when(tone !== 'neutral', (e) => e.font_semibold())
		.text_color(color)
		.child(text);
}

/**
 * An agent's status: a still dot in its colour, a ring when idle. Never
 * animated: a spinner pulls the eye from wherever the person is reading.
 *
 * @param {Record<string, string>} t
 * @param {string | null} status working | blocked | done | idle
 */
export function dot(t, status) {
	const d = div().size(SIZE.dot).flex_none().rounded(SIZE.dot);
	if (!status || status === 'idle') return d.border_1().border_color(t.idle ?? t.dim);
	return d.bg(t[status] ?? t.unknown ?? t.dim);
}

/**
 * A line in a list: SIZE.row high, hover and selection backgrounds, one
 * click. Children go left to right.
 *
 * @param {Record<string, string>} t
 * @param {string} id
 * @param {{ selected?: boolean, onClick?: (e: any, cx: any) => void, onRightClick?: (e: any, cx: any) => void }} [opts]
 */
export function row(t, id, opts = {}) {
	return h_flex()
		.id(id)
		.h(SIZE.row)
		.flex_none()
		.px(SPACE.sm)
		.gap(SPACE.sm)
		.items_center()
		.rounded(RADIUS.control)
		.text_size(TEXT.ui)
		.when(Boolean(opts.selected), (e) => e.bg(t.selected))
		.when(!opts.selected, (e) => e.hover((s) => s.bg(t.hover)))
		.when(Boolean(opts.onClick), (e) => e.cursor_pointer().on_click(opts.onClick))
		.when(Boolean(opts.onRightClick), (e) => e.on_mouse_down('right', opts.onRightClick));
}

/**
 * A list's heading: its name in capitals and a count, dimmed.
 *
 * @param {Record<string, string>} t
 * @param {string} name
 * @param {number | null} [count]
 */
export function heading(t, name, count) {
	return h_flex()
		.h(SIZE.row)
		.flex_none()
		.px(SPACE.sm)
		.gap(SPACE.xs + 2)
		.items_center()
		.text_size(TEXT.meta)
		.font_semibold()
		.text_color(t.dim)
		.child(name.toUpperCase())
		.when(count !== null && count !== undefined, (e) =>
			e.child(div().font_normal().child(String(count))),
		);
}

/**
 * A badge with a coloured dot in front: a pull request and its CI, a ticket
 * and its state. Clickable when given `onClick`.
 *
 * @param {Record<string, string>} t
 * @param {string} id
 * @param {string} color the dot's
 * @param {string} text
 * @param {(e: any, cx: any) => void} [onClick]
 */
export function chip(t, id, color, text, onClick) {
	return h_flex()
		.id(id)
		.flex_none()
		.h(SIZE.badge)
		.px(SPACE.sm - 2)
		.gap(SPACE.xs + 1)
		.items_center()
		.rounded(RADIUS.control - 1)
		.bg(t.hover)
		.text_size(TEXT.meta)
		.text_color(t.muted)
		.child(div().size(6).flex_none().rounded(3).bg(color))
		.child(text)
		.when(Boolean(onClick), (e) =>
			e
				.cursor_pointer()
				.hover((s) => s.text_color(t.foreground))
				.on_mouse_down('left', stop)
				.on_click((ev, cx) => {
					cx.stop_propagation();
					onClick(ev, cx);
				}),
		);
}

/**
 * The card a side panel is drawn in: rounded, bordered, its children
 * stacked. Every panel of the layout's right stack (Changes, Harness,
 * Graph) is one; `panel` fills it the usual way.
 *
 * @param {Record<string, string>} t
 */
export function card(t) {
	return v_flex()
		.size_full()
		.min_h(0)
		.rounded(RADIUS.card)
		.overflow_hidden()
		.bg(t.background)
		.border_1()
		.border_color(t.border)
		.text_color(t.foreground)
		.text_size(TEXT.body);
}

/**
 * A side panel: its bar on top and a body that scrolls under it, in a card.
 *
 * @param {Record<string, string>} t
 * @param {string} id the scrolling body's id, which the scrollbar follows
 * @param {object} head the bar (see `bar`)
 * @param {object} body
 * @example
 * panel(t, 'changes', bar(t, 'changes-bar').child('Changes'), list)
 */
export function panel(t, id, head, body) {
	return card(t)
		.child(head)
		.child(
			div()
				.flex_1()
				.min_h(0)
				.relative()
				.child(v_flex().id(id).absolute().inset_0().overflow_y_scroll().p(SPACE.sm).child(body))
				.child(Scrollbar.vertical(id).absolute().inset_0()),
		);
}

/**
 * Lines added and removed, "+12 −3", each left out at zero.
 *
 * @param {Record<string, string>} t
 * @param {number} [add]
 * @param {number} [del]
 */
export function counts(t, add, del) {
	return h_flex()
		.flex_none()
		.gap(SPACE.xs + 2)
		.text_size(TEXT.meta)
		.when(add > 0, (e) => e.child(div().text_color(t.ansi2).child(`+${add}`)))
		.when(del > 0, (e) => e.child(div().text_color(t.ansi1).child(`−${del}`)));
}

/**
 * A file's change as git letters it (M, A, D, R, U), in its colour.
 *
 * @param {Record<string, string>} t
 * @param {string} status
 */
export function changeMark(t, status) {
	const color = { A: t.ansi2, D: t.ansi1, U: t.ansi1, R: t.ansi4 }[status] ?? t.blocked;
	return div().w(12).flex_none().text_size(TEXT.meta).text_color(color).child(status);
}

/**
 * A path as a list shows it: the file's name, then its folder dimmed and cut
 * to fit. `from` is where a renamed file was.
 *
 * @param {Record<string, string>} t
 * @param {string} path
 * @param {{ from?: string | null, strong?: boolean }} [opts] strong: the name in bold
 */
export function pathLabel(t, path, opts = {}) {
	const parts = path.split('/');
	const name = parts.pop();
	const folder = opts.from ? `← ${opts.from}` : parts.join('/');
	return h_flex()
		.flex_1()
		.min_w(0)
		.gap(SPACE.sm)
		.items_center()
		.child(
			div()
				.flex_none()
				.max_w(220)
				.truncate()
				.text_color(t.foreground)
				.when(Boolean(opts.strong), (e) => e.font_semibold())
				.child(name),
		)
		.child(div().flex_1().min_w(0).truncate().text_size(TEXT.meta).text_color(t.dim).child(folder));
}

/**
 * How long ago, as a list's date column says it: "now", "5m", "3h", "2d",
 * then "4w" and "8mo".
 *
 * @param {number} ms the time, in milliseconds since the epoch
 * @returns {string}
 * @example
 * ago(Date.now() - 7200000) // => "2h"
 */
export function ago(ms) {
	const s = Math.max(0, (Date.now() - ms) / 1000);
	if (s < 60) return 'now';
	if (s < 3600) return `${Math.floor(s / 60)}m`;
	if (s < 86400) return `${Math.floor(s / 3600)}h`;
	if (s < 86400 * 14) return `${Math.floor(s / 86400)}d`;
	if (s < 86400 * 60) return `${Math.floor(s / 604800)}w`;
	return `${Math.floor(s / 2592000)}mo`;
}
