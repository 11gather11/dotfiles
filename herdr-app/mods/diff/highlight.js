// A line of code cut into coloured pieces, for the diff pane. The editor
// highlights a whole file but cannot tint a line's background, and a diff is
// read by its tints first; so the diff's lines are drawn by hand and coloured
// here, a line at a time. That is a guess, not a parse: a string or comment
// spanning lines is coloured on its first line only, which a diff, cut into
// hunks anyway, rarely shows.

// Comment markers by file extension; a language not here has its strings and
// numbers coloured, no keywords.
const SLASH =
	'js ts tsx jsx mjs cjs mts cts rs go c h cc cpp hpp java kt kts swift scala dart cs zig css scss less jsonc proto'.split(
		' ',
	);
const HASH =
	'py sh bash zsh fish nu nix rb pl yaml yml toml conf ini mk cmake r ex exs tf dockerfile'.split(
		' ',
	);
const DASH = 'lua sql hs elm'.split(' ');
const PLAIN = 'md markdown mdx txt json csv lock'.split(' ');

const KEYWORDS = new Set(
	(
		'if else elif for while do loop return break continue switch case default match when ' +
		'function fn func def lambda class struct enum trait impl interface type module mod ' +
		'import export from as use pub package require include let const var mut static final ' +
		'new delete this self super extends implements in of is not and or try catch except ' +
		'finally raise throw throws async await yield with where then fi esac done local ' +
		'inherit rec assert true false null nil None True False undefined void public private ' +
		'protected readonly override abstract unsafe move ref dyn crate end begin defer go ' +
		'select chan range typeof instanceof satisfies keyof declare namespace'
	).split(' '),
);

const STRING = /"(?:\\.|[^"\\])*"?|'(?:\\.|[^'\\])*'?|`(?:\\.|[^`\\])*`?/y;
const NUMBER = /\d[\w.]*/y;
const WORD = /[A-Za-z_$][\w$]*/y;
const SPACE = /\s+/y;

/**
 * What a file's extension says about colouring it.
 *
 * @param {string} path
 * @returns {{ comment: string | null, keywords: boolean, plain: boolean }}
 */
export function languageOf(path) {
	const name = path.split('/').pop().toLowerCase();
	const ext = name.includes('.') ? name.split('.').pop() : name;
	if (PLAIN.includes(ext)) return { comment: null, keywords: false, plain: true };
	if (SLASH.includes(ext)) return { comment: '//', keywords: true, plain: false };
	if (HASH.includes(ext)) return { comment: '#', keywords: true, plain: false };
	if (DASH.includes(ext)) return { comment: '--', keywords: true, plain: false };
	return { comment: null, keywords: false, plain: false };
}

/**
 * Cuts a line into pieces, each with the syntax colour it takes (null: the
 * text colour). Whitespace joins the piece before it, so no piece is spaces
 * alone, which a row of pieces would drop.
 *
 * @param {string} line the line, tabs already expanded
 * @param {{ comment: string | null, keywords: boolean, plain: boolean }} lang
 * @returns {[string, string | null][]}
 * @example
 * tokens('let x = 1; // one', languageOf('a.js'))
 * // => [['let ', 'keyword'], ['x = ', null], ['1', 'number'], ['; ', null], ['// one', 'comment']]
 */
export function tokens(line, lang) {
	if (lang.plain) return [[line, null]];
	const out = [];
	const push = (text, kind) => {
		const last = out[out.length - 1];
		// Pieces of one colour, and whitespace after any piece, join.
		if (last && (last[1] === kind || /^\s+$/.test(text))) last[0] += text;
		else out.push([text, kind]);
	};
	// A C-style block comment's inner lines (" * …") read as comment.
	if (lang.comment === '//' && /^\s*(\*|\/\*)/.test(line)) return [[line, 'comment']];
	let i = 0;
	while (i < line.length) {
		if (lang.comment && line.startsWith(lang.comment, i)) {
			push(line.slice(i), 'comment');
			break;
		}
		const at = (re) => {
			re.lastIndex = i;
			const m = re.exec(line);
			return m ? m[0] : null;
		};
		let m;
		if ((m = at(SPACE))) push(m, null);
		else if ((m = at(STRING))) push(m, 'string');
		else if ((m = at(NUMBER))) push(m, 'number');
		else if ((m = at(WORD))) {
			const next = line.slice(i + m.length).trimStart()[0];
			const kind = !lang.keywords
				? null
				: KEYWORDS.has(m)
					? 'keyword'
					: next === '('
						? 'function'
						: /^[A-Z][a-z]/.test(m)
							? 'type'
							: null;
			push(m, kind);
		} else {
			m = line[i];
			push(m, null);
		}
		i += m.length;
	}
	return out;
}

/**
 * The part of a changed line that differs from the line it replaced: what is
 * left once their common start and end are taken off. Null when there is
 * nothing in common worth pointing at, where the whole line is the change.
 *
 * @param {string} a the removed line
 * @param {string} b the added line
 * @returns {[[number, number], [number, number]] | null} [start, end) in a, then in b
 * @example
 * changedSpan('let x = 1;', 'let x = 2;') // => [[8, 9], [8, 9]]
 */
export function changedSpan(a, b) {
	let start = 0;
	while (start < a.length && start < b.length && a[start] === b[start]) start++;
	let end = 0;
	while (
		end < a.length - start &&
		end < b.length - start &&
		a[a.length - 1 - end] === b[b.length - 1 - end]
	)
		end++;
	const same = start + end;
	// Under a third in common: the lines are different lines, not an edit.
	if (same < Math.max(a.length, b.length) / 3) return null;
	return [
		[start, a.length - end],
		[start, b.length - end],
	];
}

/**
 * Splits pieces at a span, marking the pieces inside it.
 *
 * @param {[string, string | null][]} pieces
 * @param {[number, number] | null} span
 * @returns {{ text: string, kind: string | null, em: boolean }[]}
 */
export function marked(pieces, span) {
	// An empty span (a line that only lost or gained text elsewhere) marks nothing.
	if (span && span[0] >= span[1]) span = null;
	const out = [];
	let at = 0;
	for (const [text, kind] of pieces) {
		const from = at;
		at += text.length;
		if (!span || at <= span[0] || from >= span[1]) {
			out.push({ text, kind, em: false });
			continue;
		}
		const a = Math.max(span[0], from) - from;
		const b = Math.min(span[1], at) - from;
		if (a > 0) out.push({ text: text.slice(0, a), kind, em: false });
		out.push({ text: text.slice(a, b), kind, em: true });
		if (b < text.length) out.push({ text: text.slice(b), kind, em: false });
	}
	return out;
}
