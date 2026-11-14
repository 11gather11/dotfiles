// A spec's tickets and what blocks what, read from GitHub as issue-harness's
// spec.nu reads them, and laid out as a picture: a column per depth, each
// ticket right of everything it waits on.
import { exec, home } from 'herdr';

// spec.nu's graph_query, with the repository's name for the issue pane.
const QUERY = `query($owner: String!, $repo: String!, $n: Int!) {
  repository(owner: $owner, name: $repo) {
    nameWithOwner
    issue(number: $n) {
      number title state
      subIssues(first: 100) { nodes {
        number title state body
        labels(first: 20) { nodes { name } }
        blockedBy(first: 50) { nodes { number state } }
      } }
    }
  }
}`;
// A ticket only a person can do (spec.nu's human_label): no worker takes it.
const HUMAN = 'ready-for-human';

/**
 * The specs a repository's harness has started: the spec-<n>.json files in
 * its state folder (issue-harness's state-dir), newest number first.
 *
 * @param {string} repo the main checkout's folder
 * @returns {Promise<number[]>}
 */
export async function specsOf(repo) {
	const dir = `${home()}/.local/state/harness/${repo.split('/').pop()}`;
	const r = await exec('ls', [dir]).catch(() => null);
	if (!r || r.code !== 0) return [];
	return r.stdout
		.split('\n')
		.map((f) => /^spec-(\d+)\.json$/.exec(f)?.[1])
		.filter(Boolean)
		.map(Number)
		.sort((a, b) => b - a);
}

/**
 * Issues named under a "Blocked by" heading of a body, where GitHub's own
 * blocked-by links were not set (spec.nu's blockers-in-body, without the
 * look-up of each one's state).
 *
 * @param {string} body
 * @returns {number[]}
 */
function blockersInBody(body) {
	const section = (body ?? '').split('\n## ').find((s) => s.toLowerCase().startsWith('blocked by'));
	return [...new Set([...(section ?? '').matchAll(/#(\d+)/g)].map((m) => Number(m[1])))];
}

/**
 * A spec's graph: its tickets, each with the tickets of the spec it waits on.
 *
 * @param {string} repo the main checkout's folder
 * @param {number} n the spec's issue
 */
export async function readSpec(repo, n) {
	const r = await exec(
		'gh',
		[
			'api',
			'graphql',
			'-F',
			'owner={owner}',
			'-F',
			'repo={repo}',
			'-F',
			`n=${n}`,
			'-f',
			`query=${QUERY}`,
		],
		{ cwd: repo },
	);
	if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim().split('\n').pop());
	const data = JSON.parse(r.stdout).data.repository;
	const issue = data.issue;
	if (!issue) throw new Error(`#${n} is not an issue here`);
	const tickets = issue.subIssues.nodes.map((t) => ({
		number: t.number,
		title: t.title,
		closed: t.state === 'CLOSED',
		human: t.labels.nodes.some((l) => l.name === HUMAN),
		blockers: t.blockedBy.nodes.length
			? t.blockedBy.nodes.map((b) => b.number)
			: blockersInBody(t.body),
	}));
	return {
		repo: data.nameWithOwner,
		spec: issue.number,
		title: issue.title,
		closed: issue.state === 'CLOSED',
		tickets,
	};
}

/**
 * Where each ticket goes: its column is one past the deepest of the spec's
 * tickets it waits on (blockers outside the spec do not count), its row its
 * place in that column by number. A cycle, which spec.nu reports as stuck,
 * is cut where it closes.
 *
 * @param {{ number: number, blockers: number[] }[]} tickets
 * @returns {{ at: Map<number, { col: number, row: number }>, cols: number, rows: number }}
 * @example
 * layoutSpec([{ number: 1, blockers: [] }, { number: 2, blockers: [1] }])
 * // => at: 1 → col 0, 2 → col 1
 */
export function layoutSpec(tickets) {
	const by = new Map(tickets.map((t) => [t.number, t]));
	const depth = new Map();
	const visiting = new Set();
	const depthOf = (n) => {
		if (depth.has(n)) return depth.get(n);
		if (visiting.has(n)) return 0;
		visiting.add(n);
		const inside = by.get(n).blockers.filter((b) => by.has(b));
		const d = inside.length ? 1 + Math.max(...inside.map(depthOf)) : 0;
		visiting.delete(n);
		depth.set(n, d);
		return d;
	};
	for (const t of tickets) depthOf(t.number);
	const columns = [];
	for (const t of [...tickets].sort((a, b) => a.number - b.number)) {
		const d = depth.get(t.number);
		(columns[d] ??= []).push(t.number);
	}
	const at = new Map();
	columns.forEach((col, c) => col.forEach((n, r) => at.set(n, { col: c, row: r })));
	return { at, cols: columns.length, rows: Math.max(0, ...columns.map((c) => c.length)) };
}

/**
 * A ticket's state in the picture: landed (closed, or merged into the
 * spec's branch), working (a worker has it), person (no worker takes it),
 * ready (everything it waits on is in) or waiting.
 *
 * @param {{ number: number, closed: boolean, human: boolean, blockers: number[] }} t
 * @param {Map<number, any>} by every ticket of the spec, by number
 * @param {{ integrated: Set<number>, working: Set<number> }} live from the harness's snapshot
 */
export function stateOf(t, by, live) {
	const done = (n) => live.integrated.has(n) || by.get(n)?.closed;
	if (t.closed || live.integrated.has(t.number)) return 'landed';
	if (live.working.has(t.number)) return 'working';
	if (t.human) return 'person';
	// A blocker outside the spec is not known closed here: counted as in.
	return t.blockers.every((b) => !by.has(b) || done(b)) ? 'ready' : 'waiting';
}
