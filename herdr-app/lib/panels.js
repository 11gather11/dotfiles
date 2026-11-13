// The side panel's width, kept per panel: the tab bar (harness-tabs) sets
// the panel to a panel's width as it is shown and records a drag; each
// panel's bar offers to put it back (resetSlot). Shared state, as both sides
// read and write it. Copied into each mod that imports it; see markdown.js.
import { div, svg } from 'gpui-kit';
import { layout, shared, setShared, run } from 'herdr';
import { SIZE, button } from './ui.js';

/** A panel's width before any drag: the graph wants room for its lanes, labels and subjects. */
const FIRST = { graph: 520, issues: 420 };
const DEFAULT = 320;

/**
 * @param {string} id the panel's id in the layout's panel-body stack
 * @returns {number}
 */
export const firstWidth = (id) => FIRST[id] ?? DEFAULT;

/** @returns {Record<string, number>} panel => the width it was dragged to */
export const savedWidths = () => /** @type {any} */ (shared('panel.widths')) ?? {};

/**
 * The width a panel opens at: the one it was dragged to, else its first.
 *
 * @param {string} id
 */
export const widthOf = (id) => savedWidths()[id] ?? firstWidth(id);

/**
 * Records a width the panel was dragged to.
 *
 * @param {string} id
 * @param {number} px
 */
export function saveWidth(id, px) {
	setShared('panel.widths', { ...savedWidths(), [id]: px });
}

function find(node, id) {
	if (node?.id === id) return node;
	for (const child of node?.children ?? []) {
		const found = find(child, id);
		if (found) return found;
	}
	return null;
}

/** The side panel's width now, in layout px; null when it is hidden. */
export function panelPx() {
	const panel = find(layout(), 'panel');
	return panel && !panel.hidden ? (panel.size?.px ?? null) : null;
}

/**
 * Sets the panel to `px`, telling the tab bar the change is not a drag to
 * record while it lands (shared('panel.resizing')).
 *
 * @param {number} px
 */
export function resizePanel(px) {
	setShared('panel.resizing', { want: px, until: Date.now() + 1000 });
	run('layout.resize', { id: 'panel', px });
}

/**
 * Puts a panel back to its first width and forgets the one it was dragged to.
 *
 * @param {string} id
 */
export function resetWidth(id) {
	const rest = { ...savedWidths() };
	delete rest[id];
	setShared('panel.widths', rest);
	resizePanel(firstWidth(id));
}

/**
 * The reset control for a panel's bar: a button while the panel is off its
 * first width, and its room kept empty otherwise, so the bar does not shift
 * as it comes and goes.
 *
 * @param {Record<string, string>} t
 * @param {string} id the panel's id
 */
export function resetSlot(t, id) {
	const px = panelPx();
	const off = px !== null && Math.abs(px - firstWidth(id)) >= 1;
	return div()
		.flex_none()
		.w(SIZE.control)
		.when(off, (e) =>
			e.child(
				button(
					t,
					`${id}-width`,
					svg('mods/workspace-chrome/panel-right.svg').size(14),
					() => resetWidth(id),
					{
						title: `Back to ${firstWidth(id)}px`,
					},
				),
			),
		);
}
