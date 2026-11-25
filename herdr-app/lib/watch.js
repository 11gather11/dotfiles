// Following a folder for a view: one watch per view at a time, released when
// the view moves on, and a burst of changes answered once.
import { watchFolder } from 'herdr';

/**
 * Watches `dir` until `stop()`, calling `onChange` once a burst of changes
 * has settled for `settleMs`.
 *
 * The handle a view keeps is what ends the loop. A loop that checked the
 * view's current folder instead (`while (this.watched === dir)`) came back to
 * life when the view returned to that folder, so going A → B → A left two
 * loops on A, and every change after that was read twice, then four times.
 * `stop()` also cancels the pending watch, which frees one of the 64 slots
 * every mod shares.
 *
 * A folder that cannot be watched marks the handle `dead`, so the view can
 * try again on its next read; until then the view shows what it last read.
 *
 * @param {import('gpui-kit').Context} cx
 * @param {string} dir
 * @param {(cx: import('gpui-kit').Context, changed: string[]) => void} onChange
 *   `changed` holds every path reported during the burst
 * @param {number} [settleMs]
 * @returns {{ dir: string, dead: boolean, stop(): void }}
 * @example
 * this.watch = follow(cx, root, (cx) => this.refresh(cx), 300);
 * // later, on another folder:
 * this.watch.stop();
 */
export function follow(cx, dir, onChange, settleMs = 0) {
	let pending = null;
	let batch = null;
	const handle = {
		dir,
		dead: false,
		stopped: false,
		stop() {
			handle.stopped = true;
			pending?.cancel();
		},
	};
	cx.spawn(async (cx) => {
		try {
			while (!handle.stopped) {
				pending = watchFolder(dir);
				const changed = await pending;
				if (handle.stopped) return;
				// Paths arriving while a timer is set join its batch rather
				// than setting another.
				if (batch) {
					batch.push(...changed);
					continue;
				}
				batch = [...changed];
				cx.timer.after(settleMs, (cx) => {
					const paths = batch;
					batch = null;
					if (!handle.stopped) onChange(cx, paths);
				});
			}
		} catch {
			handle.dead = true;
		}
	});
	return handle;
}

/**
 * The watch a view should hold for `dir`: `current` when it already follows
 * `dir` and is still alive, else a new one, with `current` stopped. No `dir`
 * (no folder, or one on another machine, which watchFolder cannot see) stops
 * `current` and returns null.
 *
 * @param {ReturnType<typeof follow> | null} current
 * @param {import('gpui-kit').Context} cx
 * @param {string | null} dir
 * @param {(cx: import('gpui-kit').Context, changed: string[]) => void} onChange
 * @param {number} [settleMs]
 * @returns {ReturnType<typeof follow> | null}
 * @example
 * this.watch = refollow(this.watch, cx, on ? null : root, (cx) => this.refresh(cx), 300);
 */
export function refollow(current, cx, dir, onChange, settleMs = 0) {
	if (current && current.dir === dir && !current.dead) return current;
	current?.stop();
	return dir ? follow(cx, dir, onChange, settleMs) : null;
}
