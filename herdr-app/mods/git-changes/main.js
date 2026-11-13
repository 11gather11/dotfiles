// The uncommitted changes of the repository being worked in, as a list:
// staged, unstaged and untracked files, each with its added and removed line
// counts. A click shows the file's diff in the diff pane beside the
// terminals, where there is room to read it. Read-only: nothing here stages
// or commits.
//
// In place of Herdr's `changes` panel, which drew the diff inside the panel
// itself, too narrow for most lines, and in one colour.
import { View, div } from 'gpui-kit';
import { v_flex } from 'gpui-base';
import { shared, theme, watchFolder, nextCommand } from 'herdr';
import {
	SPACE,
	TEXT,
	bar,
	spacer,
	button,
	badge,
	row,
	heading,
	panel,
	counts,
	changeMark,
	pathLabel,
} from './lib/ui.js';
import { focusedPlace } from './lib/focus.js';
import { git, openDiff } from './lib/git.js';
import { resetSlot } from './lib/panels.js';

// The watch catches edits; this catches what it cannot (another machine).
const FALLBACK_MS = 10000;
const SETTLE_MS = 300;
const MAX_FILES = 1000;

/**
 * `git diff --numstat -z` as path => { add, del, binary }.
 *
 * @param {string} out
 */
function numstat(out) {
	const stats = {};
	for (const entry of out.split('\0')) {
		const [a, d, ...rest] = entry.split('\t');
		if (!rest.length) continue;
		stats[rest.join('\t')] = { add: Number(a) || 0, del: Number(d) || 0, binary: a === '-' };
	}
	return stats;
}

export default class GitChanges extends View {
	init(_props, cx) {
		this.where = null; // JSON of [folder, machine] read last
		this.root = null;
		this.on = null;
		this.branch = null;
		this.sections = []; // [{ name, files: [{ path, status, add, del }] }]
		this.error = null;
		this.loading = false;
		this.again = false;
		this.watched = null;
		this.refresh(cx);
		cx.timer.every(FALLBACK_MS, (cx) => this.refresh(cx));
		// "git-changes.diff" (keys.json): every change in the diff pane.
		cx.spawn(async () => {
			for (;;) if ((await nextCommand()) === 'diff' && this.root) this.show(null);
		});
	}

	place() {
		return focusedPlace();
	}

	refresh(cx) {
		const { folder, on } = this.place();
		const where = JSON.stringify([folder, on]);
		if (where !== this.where) {
			this.where = where;
			this.root = null;
			this.sections = [];
			this.error = null;
		}
		if (!folder) return;
		// One read at a time; a change during it reads once more after.
		if (this.loading) {
			this.again = true;
			return;
		}
		this.loading = true;
		cx.spawn(async (cx) => {
			try {
				const top = await git(folder, on, ['rev-parse', '--show-toplevel']);
				if (where !== this.where) return;
				if (top.code !== 0) {
					this.error = 'Not a git repository';
					return;
				}
				const root = top.stdout.trim();
				const [status, staged, unstaged, branch] = await Promise.all([
					git(root, on, [
						'status',
						'--porcelain=v1',
						'-z',
						'--no-renames',
						'--untracked-files=all',
					]),
					git(root, on, ['diff', '--cached', '--numstat', '-z', '--no-renames']),
					git(root, on, ['diff', '--numstat', '-z', '--no-renames']),
					git(root, on, ['branch', '--show-current']),
				]);
				if (status.code !== 0) throw new Error(status.stderr.trim());
				if (where !== this.where) return;
				const inIndex = numstat(staged.stdout);
				const inTree = numstat(unstaged.stdout);
				const lists = { Staged: [], Changes: [], Untracked: [] };
				for (const entry of status.stdout.split('\0').filter(Boolean).slice(0, MAX_FILES)) {
					// XY: the index's state, then the working tree's.
					const [x, y] = [entry[0], entry[1]];
					const path = entry.slice(3);
					if (x === '?') {
						lists.Untracked.push({ path, status: 'A', add: 0, del: 0 });
						continue;
					}
					if (x !== ' ') lists.Staged.push({ path, status: x, ...inIndex[path] });
					if (y !== ' ') lists.Changes.push({ path, status: y, ...inTree[path] });
				}
				this.root = root;
				this.on = on;
				this.branch = branch.stdout.trim() || null;
				this.sections = Object.entries(lists)
					.filter(([, files]) => files.length)
					.map(([name, files]) => ({ name, files }));
				this.error = null;
				this.watch(root, cx);
			} catch (e) {
				if (where === this.where) this.error = String(e.message ?? e);
			} finally {
				this.loading = false;
				cx.notify();
				if (this.again) {
					this.again = false;
					this.refresh(cx);
				}
			}
		});
	}

	watch(root, cx) {
		if (this.on || this.watched === root) return;
		this.watched = root;
		cx.spawn(async (cx) => {
			try {
				while (this.watched === root) {
					await watchFolder(root);
					if (this.watched === root) cx.timer.after(SETTLE_MS, (cx) => this.refresh(cx));
				}
			} catch {
				this.watched = null;
			}
		});
	}

	show(path) {
		openDiff({ root: this.root, on: this.on, kind: 'worktree' }, path);
	}

	fileRow(t, section, f, shown) {
		const selected =
			shown?.kind === 'worktree' && shown.root === this.root && shown.file === f.path;
		return row(t, `c-${section}-${f.path}`, { selected, onClick: () => this.show(f.path) })
			.child(changeMark(t, f.status))
			.child(pathLabel(t, f.path))
			.child(counts(t, f.add, f.del));
	}

	render(cx) {
		const t = theme();
		const { folder, on } = this.place();
		if (JSON.stringify([folder, on]) !== this.where) this.refresh(cx);
		const shown = shared('diff.target');
		const files = this.sections.flatMap((s) => s.files);
		const add = files.reduce((n, f) => n + (f.add ?? 0), 0);
		const del = files.reduce((n, f) => n + (f.del ?? 0), 0);
		const head = bar(t, 'changes-bar')
			.child(div().flex_none().font_semibold().child('Changes'))
			.when(Boolean(this.branch), (e) => e.child(badge(t, this.branch)))
			.child(spacer())
			.child(counts(t, add, del))
			.when(files.length > 0, (e) =>
				// Every change in one diff, file after file.
				e.child(button(t, 'changes-all', 'Diff', () => this.show(null))),
			)
			.child(resetSlot(t, 'changes'));
		const body = !this.sections.length
			? div()
					.p(SPACE.sm)
					.text_size(TEXT.ui)
					.text_color(t.dim)
					.child(
						this.error ??
							(this.loading && !this.root
								? 'Reading…'
								: this.root
									? 'No uncommitted changes'
									: 'No folder'),
					)
			: v_flex()
					.gap(SPACE.sm)
					.children(
						this.sections.map((s) =>
							v_flex()
								.child(heading(t, s.name, s.files.length))
								.children(s.files.map((f) => this.fileRow(t, s.name, f, shown))),
						),
					);
		return panel(t, 'git-changes-body', head, body);
	}
}
