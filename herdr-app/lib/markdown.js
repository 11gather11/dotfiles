// Markdown drawn as GitHub shows it, for every mod that shows some: the
// viewer's files and the chat's messages. The markdown view draws text;
// what it cannot draw (Mermaid, formulas, pictures) becomes an image made by
// md-asset (nix/modules/home-darwin/herdr-app.nix), drawn as it is ready.
//
// Lives once in herdr-app/lib and is copied into each mod that imports it,
// by herdr-app-sync: the app refuses an import from outside a mod's folder.
import { div, image } from 'gpui-kit';
import { v_flex, TextView } from 'gpui-base';
import { readTextFile, writeTextFile, exec, appHome, theme } from 'herdr';

// Where md-asset puts the images it makes, under the app's folder, as the
// only place a mod can draw an image from.
export const ASSETS = 'cache/viewer';

// GitHub's alert kinds, as the label a blockquote gets in their place: the
// markdown view draws `> [!NOTE]` as the literal text.
const ALERTS = {
	NOTE: 'ℹ️ Note',
	TIP: '💡 Tip',
	IMPORTANT: '❗ Important',
	WARNING: '⚠️ Warning',
	CAUTION: '⛔ Caution',
};

/** A file's extension, lowercase; `txt` for none. */
export const extOf = (file) => (file.includes('.') ? file.split('.').pop().toLowerCase() : 'txt');
export const isSvg = (file) => extOf(file) === 'svg';

/**
 * A 32-bit FNV-1a hash in hex, naming a rendered image after what it was made
 * from, so the same diagram is drawn once.
 *
 * @param {string} text
 * @returns {string}
 */
export function hash(text) {
	let h = 0x811c9dc5;
	for (let i = 0; i < text.length; i++) {
		h ^= text.charCodeAt(i);
		h = Math.imul(h, 0x01000193) >>> 0;
	}
	return h.toString(16).padStart(8, '0');
}

/**
 * Splits markdown into what the markdown view draws itself (`text`) and what
 * it cannot, drawn as images instead: Mermaid blocks, formulas, and pictures
 * on a line of their own. Lines inside other code blocks stay text, so a fence
 * or an image shown as an example is left alone.
 *
 * @param {string} md
 * @returns {({kind: 'text', text: string} | {kind: 'mermaid', code: string} | {kind: 'math', tex: string} | {kind: 'image', src: string, alt: string, remote: boolean})[]}
 * @example
 * segments("a\n```mermaid\ngraph LR\n```\nb") // => [text "a", mermaid "graph LR", text "b"]
 */
export function segments(md) {
	const out = [];
	let buf = [];
	let fence = null; // the fence of the code block we are in, if any
	const flush = () => {
		if (buf.length) out.push({ kind: 'text', text: alerts(buf.join('\n')) });
		buf = [];
	};
	const lines = md.split('\n');
	for (let i = 0; i < lines.length; i++) {
		const l = lines[i];
		const open = /^\s*(`{3,}|~{3,})\s*([\w-]*)/.exec(l);
		if (fence) {
			if (l.trim().startsWith(fence)) fence = null;
			buf.push(l);
			continue;
		}
		if (open && (open[2] === 'mermaid' || open[2] === 'math')) {
			const body = [];
			for (i++; i < lines.length && !lines[i].trim().startsWith(open[1]); i++) body.push(lines[i]);
			flush();
			out.push(
				open[2] === 'mermaid'
					? { kind: 'mermaid', code: body.join('\n') }
					: { kind: 'math', tex: body.join('\n') },
			);
			continue;
		}
		// A display formula: `$$ … $$` on one line, or `$$` lines around it.
		const oneLine = /^\s*\$\$(.+)\$\$\s*$/.exec(l);
		if (oneLine || l.trim() === '$$') {
			const body = [];
			if (oneLine) body.push(oneLine[1]);
			else for (i++; i < lines.length && lines[i].trim() !== '$$'; i++) body.push(lines[i]);
			flush();
			out.push({ kind: 'math', tex: body.join('\n').trim() });
			continue;
		}
		if (open) {
			fence = open[1];
			buf.push(l);
			continue;
		}
		// A picture on a line of its own, linked or not: `![alt](src)` or
		// `[![alt](src)](href)`, beside the document or at an http(s) URL.
		const img = /^\s*\[?!\[([^\]]*)\]\(<?([^)\s>]+)>?(?:\s+"[^"]*")?\)(?:\]\([^)]*\))?\s*$/.exec(l);
		const remote = img && /^https?:\/\//i.test(img[2]);
		if (img && (remote || !/^[a-z][a-z0-9+.-]*:/i.test(img[2]))) {
			flush();
			out.push({ kind: 'image', src: img[2], alt: img[1], remote });
			continue;
		}
		buf.push(l);
	}
	flush();
	return out;
}

/**
 * Rewrites GitHub's alert marker (`> [!WARNING]`) as a bold label, so the
 * blockquote says what kind of alert it is.
 *
 * @param {string} text
 * @returns {string}
 */
function alerts(text) {
	return text.replace(
		/^(\s*>\s*)\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$/gim,
		(_m, quote, kind) => `${quote}**${ALERTS[kind.toUpperCase()]}**`,
	);
}

/**
 * What the markdown view would show as source on a line of text, put right:
 * emoji shortcodes (`:tada:`) become the emoji, and an inline formula
 * (`$x^2$`) becomes inline code, as an image cannot sit inside a line of the
 * view. Code blocks and code spans are left as they are.
 *
 * @param {string} text a text part of the document
 * @param {Record<string, string>|null} emoji alias => emoji
 * @returns {string}
 * @example
 * inline("Done :tada: when $x > 0$, not `:tada:`", { tada: "🎉" }) // => "Done 🎉 when `x > 0`, not `:tada:`"
 */
export function inline(text, emoji) {
	let fence = null;
	return text
		.split('\n')
		.map((line) => {
			const open = /^\s*(`{3,}|~{3,})/.exec(line);
			if (fence) {
				if (line.trim().startsWith(fence)) fence = null;
				return line;
			}
			if (open) {
				fence = open[1];
				return line;
			}
			// Even pieces lie outside code spans, odd ones inside.
			return line
				.split(/(`+[^`]*`+)/)
				.map((piece, i) =>
					i % 2
						? piece
						: piece
								// GitHub's rule: no space just inside the dollars, no digit after.
								.replace(/\$(?=\S)([^$\n]*?\S)\$(?!\d)/g, (_m, tex) => `\`${tex}\``)
								.replace(/:([a-z0-9_+-]+):/g, (m, alias) => emoji?.[alias] ?? m),
				)
				.join('');
		})
		.join('\n');
}

/** `rel` resolved against the folder `dir`, with `.` and `..` folded in. */
function resolve(dir, rel) {
	const parts = (rel.startsWith('/') ? rel : `${dir}/${rel}`).split('/');
	const out = [];
	for (const p of parts) {
		if (p === '..') out.pop();
		else if (p && p !== '.') out.push(p);
	}
	return `/${out.join('/')}`;
}

// Shared by every document in this mod copy: the shortcodes, read once, and
// the images made, by what they were made from, so a diagram that two
// messages (or two reads of a file) carry is made once.
let emoji = null;
let emojiRead = null;
const assets = new Map();
const making = new Map(); // key => the image being made for it

/** Reads the shortcode table (linked by herdr-app.nix) once per mod copy. */
function loadEmoji(cx) {
	emojiRead ??= readTextFile(`${appHome()}/emoji.json`)
		.then((text) => {
			if (text) emoji = JSON.parse(text);
		})
		.catch(() => null);
	cx.spawn(async (cx) => {
		await emojiRead;
		cx.notify();
	});
}

/**
 * One markdown document: its parts and the images they need. Made in `init`
 * or an event, never in render; `set` replaces its text, and `view` draws it.
 *
 * @example
 * this.md = new Markdown('readme');
 * this.md.set(text, '/path/to/its/folder', cx);
 * // in render:
 * this.md.view(t, width)
 */
export class Markdown {
	/**
	 * @param {string} id unique among the views of this mod, for element ids
	 */
	constructor(id) {
		this.id = id;
		this.text = null;
		this.parts = [];
	}

	/**
	 * Takes the document's text; `dir` is the folder its relative pictures are
	 * in. Unchanged text is not split again.
	 */
	set(text, dir, cx) {
		if (emoji === null) loadEmoji(cx);
		if (text === this.text) return;
		this.text = text;
		this.parts = segments(text);
		const wanted = this.parts.filter((p) => p.kind !== 'text');
		if (!wanted.length) return;
		// Keyed before anything is made, so a part whose image exists from an
		// earlier read shows it at once rather than after the ones before it.
		const where = (part) => (part.remote ? part.src : resolve(dir ?? '/', part.src));
		for (const part of wanted) {
			part.where = part.kind === 'image' ? where(part) : null;
			part.key =
				part.kind === 'mermaid'
					? `m:${part.code}`
					: part.kind === 'math'
						? `x:${part.tex}`
						: `i:${part.where}`;
		}
		cx.spawn(async (cx) => {
			await exec('mkdir', ['-p', `${appHome()}/${ASSETS}`]).catch(() => null);
			for (const part of wanted) {
				if (assets.has(part.key)) continue;
				// One making per image, shared by every view that wants it; its
				// result is recorded by the making itself, so a view closed while
				// it ran leaves no image stuck at "Drawing…" for the next.
				if (!making.has(part.key))
					making.set(
						part.key,
						make(part).then((a) => {
							assets.set(part.key, a);
							making.delete(part.key);
						}),
					);
				await making.get(part.key);
				cx.notify();
			}
		});
	}

	/** The document, as wide as `width` allows (images scale down to it). */
	view(t, width) {
		return v_flex()
			.gap(4)
			.children(this.parts.map((p, i) => part(t, p, `${this.id}-${i}`, width)));
	}
}

/** Makes the image for one part with md-asset; its record for `assets`. */
async function make(part) {
	try {
		const fg = theme().foreground;
		const name = hash(part.key);
		const dir = `${appHome()}/${ASSETS}`;
		// Text a block is drawn from goes to a file md-asset reads, so no shell
		// quoting stands between the two.
		const source = async (ext, text) => {
			const f = `${dir}/${name}.${ext}`;
			if ((await readTextFile(f)) === null) await writeTextFile(f, text, null);
			return f;
		};
		let args, file;
		if (part.kind === 'mermaid') {
			file = `${name}.png`;
			args = ['mermaid', await source('mmd', part.code), `${dir}/${file}`];
		} else if (part.kind === 'math') {
			file = `${name}.png`;
			args = ['math', await source('tex', part.tex), `${dir}/${file}`, fg];
		} else if (part.remote) {
			file = `${name}.png`;
			args = ['url', part.src, `${dir}/${file}`, fg];
		} else {
			file = `${name}.${isSvg(part.where) ? 'png' : extOf(part.where)}`;
			args = isSvg(part.where)
				? ['svg', part.where, `${dir}/${file}`, fg]
				: ['image', part.where, `${dir}/${file}`];
		}
		const r = await exec('md-asset', args, { timeout: 60000 });
		// Its size in pixels, and the pixels it drew per point.
		const [w, h, scale] = r.stdout.trim().split(' ').map(Number);
		if (r.code !== 0 || !w || !h) throw new Error(r.stderr.trim().split('\n').pop() || 'no image');
		return { state: 'ready', path: `${ASSETS}/${file}`, w: w / (scale || 1), h: h / (scale || 1) };
	} catch (e) {
		return { state: 'error', error: String(e.message ?? e) };
	}
}

// One part: the markdown view's own drawing for text, an image for the rest
// once it is made, its source until then.
function part(t, p, id, width) {
	if (p.kind === 'text') return TextView.markdown(id, inline(p.text, emoji)).selectable(true);
	const a = assets.get(p.key);
	if (a?.state === 'ready') {
		// Never wider than the view: scaled down, never up.
		const k = Math.min(1, Math.max(120, width ?? 800) / a.w);
		return div()
			.py(8)
			.child(
				image(a.path)
					.w(a.w * k)
					.h(a.h * k),
			);
	}
	const note = a?.state === 'error' ? `Could not draw this: ${a.error}` : 'Drawing…';
	return v_flex()
		.gap(4)
		.py(8)
		.child(
			div()
				.text_size(11)
				.text_color(a?.state === 'error' ? t.ansi1 : t.dim)
				.child(note),
		)
		.child(
			TextView.markdown(
				`${id}-src`,
				p.kind === 'mermaid'
					? '```mermaid\n' + p.code + '\n```'
					: p.kind === 'math'
						? '```math\n' + p.tex + '\n```'
						: `![${p.alt}](${p.src})`,
			),
		);
}
