// Where the person is working: the folder the panels (files, harness,
// finder) follow. Copied into each mod that imports it; see markdown.js.
import { spaces, panes, focused } from 'herdr';

/**
 * The focused pane's folder. A mod pane (a viewer beside a terminal) has none of its
 * own and takes its tab's terminal's, as it shows that terminal's work; the
 * space's folder is the last resort, as it is only where the space's first
 * terminal started and stays so after that terminal is gone.
 *
 * @returns {string | null}
 */
export function focusedFolder() {
	const f = focused();
	const pane = f?.pane ? panes().find((p) => p.pane === f.pane) : null;
	if (pane?.cwd) return pane.cwd;
	if (f?.cwd) return f.cwd;
	const tab = pane?.tab ?? f?.tab;
	const terminal = panes().find((p) => p.tab === tab && p.cwd);
	return terminal?.cwd || spaces().find((s) => s.active)?.folder || null;
}
