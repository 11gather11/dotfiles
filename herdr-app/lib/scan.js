// One `git status` of a repository for every panel that shows it, as Herdr's
// own Files and Changes have shared theirs since 0.1.18. Copied into each mod
// that imports it; see markdown.js.
import { window } from 'herdr';
import { git } from './git.js';

const STATUS = ['status', '--porcelain=v1', '-z', '--no-renames', '--untracked-files=all'];

/** How often a panel reads its repository with no change seen. */
export const POLL_MS = 10000;

// Mods run in one VM, so a map on globalThis is seen by every panel; each
// still runs its own tasks, which end when its copy closes.
const scans = (globalThis[Symbol.for('dotfiles.repoStatus.v1')] ??= new Map());

/**
 * @typedef {object} Scan
 * @property {{ code: number, stdout: string, stderr: string } | null} status
 * @property {number} started ms since the epoch
 * @property {number} finished ms since the epoch; 0 while it runs
 * @property {number} delay how long to wait before reading this repository
 *   again for a change: none after a quick scan, five times its length
 *   (at most a minute) after a slow one, so a huge repository is not
 *   scanned back to back
 * @property {import('gpui-kit').Task} task
 */

/**
 * Whether the window is the one in front. Nothing in a window behind
 * another is being looked at, so a panel puts off its reads until it is.
 *
 * @returns {boolean}
 */
export function focusedWindow() {
	return window()?.active !== false;
}

/**
 * The repository's `git status` from a scan that started at or after
 * `since`, sharing one with any other panel asking at the same time and
 * reusing a recent one: a scan already running is waited for rather than
 * started again, and a finished one serves until the panel would poll anyway.
 *
 * @param {import('gpui-kit').Context} cx
 * @param {string} root the repository's top folder
 * @param {string | null} on the machine it is on (null: here)
 * @param {number} since the earliest start a scan may have, e.g. when the
 *   change it has to show was seen; 0 takes any recent scan
 * @param {() => boolean} alive whether the caller still wants the answer
 * @returns {Promise<Scan | null>} null when `alive()` turned false
 * @example
 * const scan = await repoStatus(cx, top, on, this.changedAt, () => this.context === context);
 */
export async function repoStatus(cx, root, on, since, alive) {
	const key = JSON.stringify([on, root]);
	const now = Date.now();
	// Forget repositories nobody has read for a poll's length.
	for (const [k, s] of scans) if (s.finished && now >= expires(s)) scans.delete(k);
	while (alive()) {
		let scan = scans.get(key);
		const running = scan && !scan.finished && !scan.task.is_done();
		const usable =
			scan?.finished &&
			scan.status?.code === 0 &&
			scan.started >= since &&
			Date.now() < expires(scan);
		if (!usable && !(running && scan.started >= since)) {
			scan = start(cx, root, on);
			scans.set(key, scan);
		}
		// Waited for by polling rather than by awaiting the scan's own task:
		// that task belongs to the panel that started it, and closing that
		// panel would leave this one waiting for ever.
		while (alive() && !scan.finished && !scan.task.is_done()) await cx.sleep(50);
		if (!alive()) return null;
		if (scan.finished) return scan;
		// Its panel closed before it finished: scan again from here.
		if (scans.get(key) === scan) scans.delete(key);
	}
	return null;
}

/** @param {Scan} scan @returns {number} when the scan is too old to reuse */
function expires(scan) {
	return scan.finished + Math.max(POLL_MS, scan.delay);
}

/** @returns {Scan} */
function start(cx, root, on) {
	/** @type {Scan} */
	const scan = { status: null, started: Date.now(), finished: 0, delay: 0, task: null };
	scan.task = cx.spawn(async () => {
		try {
			scan.status = await git(root, on, STATUS);
		} catch (e) {
			scan.status = { code: -1, stdout: '', stderr: String(e.message ?? e) };
		} finally {
			const took = Date.now() - scan.started;
			scan.delay = took < 500 ? 0 : Math.min(60000, 5 * took);
			scan.finished = Date.now();
		}
	});
	return scan;
}
