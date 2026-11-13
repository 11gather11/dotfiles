// A repository's issue-harness, as the panels reach it: the terminal it runs
// in, starting one, and handing it work. Copied into each mod that imports
// it; see markdown.js.
import { terminals, spaces, panes, run, exec } from 'herdr';

/**
 * The running harnesses: repository => its terminal's address. A harness is
 * a terminal the `harness` command (herdr-app.nix) labelled
 * harness=<repository>, with Claude in front still.
 *
 * @returns {Map<string, string>}
 */
export function runningHarnesses() {
	const out = new Map();
	for (const x of terminals()) {
		const repo = x.labels?.harness;
		if (repo && x.program?.key === 'claude') out.set(repo, x.address);
	}
	return out;
}

/**
 * Starts a harness in the repository's own space: the one with a terminal in
 * the main checkout, the active one first. A worker's space (its folder a
 * worktree beside the checkout, `<repo>.<branch>`) never counts, and without
 * such a space it gets a new one. Through a login shell, as spawn.nu starts
 * workers: the core's environment is the one it started with, and the
 * shell's profile is what puts claude and harness on PATH whatever that was.
 *
 * @param {string} repo the main checkout's folder
 * @param {string} [request] the opening request to /issue-harness, e.g. "#123"
 */
export function startHarness(repo, request) {
	// `harness` takes its words after it as the request (see herdr-app.nix).
	const words = request ? ` ${request.replace(/[^\w#.,: -]/g, '')}` : '';
	const argv = ['/bin/sh', '-c', `exec "$SHELL" -l -c "exec harness${words}"`];
	const inRepo = new Set(
		panes()
			.filter((p) => p.cwd === repo)
			.map((p) => p.tab),
	);
	const home = spaces()
		.filter((s) => !s.machine && !s.folder.startsWith(`${repo}.`))
		.filter((s) => s.tabs.some((tab) => inRepo.has(tab.id)))
		.sort((a, b) => Number(b.active) - Number(a.active))[0];
	if (home) run('tab.new', { name: 'harness', space: home.id, folder: repo, argv });
	else run('space.new', { folder: repo, tab: 'harness', argv });
}

/**
 * Hands the harness a request, starting one with it when none runs. The
 * request is typed into the harness's input as the person would; Claude
 * takes it after the turn it is in.
 *
 * @param {string} repo the main checkout's folder
 * @param {string} request e.g. "#123"
 * @returns {Promise<'sent' | 'started' | string>} what happened, or why it failed
 */
export async function handToHarness(repo, request) {
	const address = runningHarnesses().get(repo);
	if (!address) {
		startHarness(repo, request);
		return 'started';
	}
	const r = await exec('hc', ['send', address, `/issue-harness ${request}`]);
	return r.code === 0 ? 'sent' : (r.stderr || r.stdout).trim() || `hc send exited ${r.code}`;
}
