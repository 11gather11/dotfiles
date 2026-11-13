// Reading a repository for the panels that show it (changes, the diff pane),
// and opening the diff pane on something. Copied into each mod that imports
// it; see markdown.js.
import { exec, panes, focused, setShared, run } from 'herdr';

/**
 * Flags for every read: write nothing under .git (no index refresh or lock,
 * no fsmonitor cookie). A panel watches the repository's folder, and a read
 * that touched it would set off the next refresh, and that the next.
 */
export const READ = [
	'--no-optional-locks',
	'-c',
	'core.fsmonitor=false',
	'-c',
	'diff.autoRefreshIndex=false',
];

/**
 * Runs git read-only in a repository.
 *
 * @param {string} root the repository's folder
 * @param {string | null} on the machine it is on (null: here)
 * @param {string[]} args
 * @returns {Promise<{ code: number, stdout: string, stderr: string }>}
 * @example
 * await git('/repo', null, ['status', '--porcelain=v1'])
 */
export function git(root, on, args) {
	return exec('git', [...READ, ...args], { cwd: root, on });
}

/**
 * What the diff pane shows. `worktree`: uncommitted changes, staged or not,
 * and untracked files. `commit`: one commit against its first parent.
 * `range`: what `head` adds since it left `base` (base...head), as a pull
 * request shows it.
 *
 * @typedef {{ root: string, on: string | null, kind: 'worktree' }
 *   | { root: string, on: string | null, kind: 'commit', rev: string, title?: string }
 *   | { root: string, on: string | null, kind: 'range', base: string, head: string }} DiffTarget
 */

/**
 * Shows `target` in the diff pane beside the current tab's terminals,
 * opening one when the tab has none, with `file` brought to the top. The
 * target goes through shared state, as a pane already open takes no new
 * props; `seq` makes a second click on the same file scroll to it again.
 *
 * @param {DiffTarget} target
 * @param {string} [file] a path in the repository to scroll to
 */
export function openDiff(target, file) {
	setShared('diff.target', { ...target, file: file ?? null, seq: Date.now() });
	const tab = focused()?.tab;
	const here = panes().filter((p) => p.tab === tab);
	if (here.some((p) => p.mod === 'diff')) return;
	// Beside a terminal: the focus may be in a panel, which has no pane.
	const beside = here.find((p) => p.focused && p.terminal) ?? here.find((p) => p.terminal);
	if (!beside) return;
	run('pane.split', { direction: 'right', pane: beside.pane, mod: 'diff' });
}
