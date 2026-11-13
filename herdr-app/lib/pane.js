// Opening a mod pane beside the terminals and telling it what to show.
// Copied into each mod that imports it; see markdown.js.
import { panes, focused, setShared, run } from 'herdr';

/**
 * Shows `value` in the `mod` pane beside the current tab's terminals,
 * opening one when the tab has none. The value goes through shared state
 * under `key`, as a pane already open takes no new props; the pane reads it
 * and takes each new `seq` once, so a second click on the same thing still
 * brings it back.
 *
 * @param {string} mod the pane's mod: diff, issue
 * @param {string} key the shared key the pane reads
 * @param {object} value
 * @example
 * openBeside('issue', 'issue.target', { repo: 'owner/name', number: 12 })
 */
export function openBeside(mod, key, value) {
	setShared(key, { ...value, seq: Date.now() });
	const tab = focused()?.tab;
	const here = panes().filter((p) => p.tab === tab);
	if (here.some((p) => p.mod === mod)) return;
	// Beside a terminal: the focus may be in a panel, which has no pane.
	const beside = here.find((p) => p.focused && p.terminal) ?? here.find((p) => p.terminal);
	if (!beside) return;
	run('pane.split', { direction: 'right', pane: beside.pane, mod });
}
