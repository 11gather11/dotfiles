// One file, read-only: markdown rendered (its source a click away), anything
// else as highlighted code. It follows the file as it changes, so it serves
// as a live preview while the file is written elsewhere.
//
// Opened over the window as a dialog (the file tree and the finder do so) or
// as a pane beside the terminals: `pane.split {mod: "viewer", props: {file}}`.
// props: `file`, an absolute path; `on`, the machine it is on (null: here);
// `line`, a line to open at, from a search.
import { View, div, svg, image } from 'gpui-kit';
import {
	v_flex,
	h_flex,
	Editor,
	EditorState,
	TextView,
	Scrollbar,
	v_virtual_list,
	VirtualListScrollHandle,
} from 'gpui-base';
import {
	props,
	readTextFile,
	writeTextFile,
	watchFolder,
	exec,
	appHome,
	theme,
	settings,
	run,
	closeOverlay,
} from 'herdr';

// Extensions the editor knows under another language's name.
const LANG = {
	ts: 'js',
	tsx: 'js',
	mts: 'js',
	cts: 'js',
	jsx: 'js',
	mjs: 'js',
	toml: 'yaml',
	jsonc: 'json',
	svelte: 'html',
	svg: 'html',
	vue: 'html',
};
// Past this, the rest of a file is cut: the editor holds it all in memory.
const LIMIT = 400000;

const extOf = (file) => (file.includes('.') ? file.split('.').pop().toLowerCase() : 'txt');
const isMarkdown = (file) => ['md', 'markdown', 'mdx'].includes(extOf(file));
// Files shown as a picture. An SVG is text too, so it also has a code view;
// the others are only pictures.
const PICTURES = ['svg', 'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'tif', 'tiff'];
const isPicture = (file) => PICTURES.includes(extOf(file));
const isSvg = (file) => extOf(file) === 'svg';
// Padding around a picture (p(24) in render), for the room it may take.
const PICTURE_PAD = 48;
// The longest side an SVG file is drawn at for the picture view: as large as
// the view gets, so it is only ever scaled down.
const SVG_SIZE = 1600;
// The line list's row height, the size its virtual list is told.
const LINE_H = 20;
// Where md-asset puts the images it makes, under the app's folder, as the
// only place a mod can draw an image from.
const ASSETS = 'cache/viewer';
// The rendered markdown's side padding (px(28) in render), for the width an
// image may take.
const MD_PAD = 56;

// GitHub's alert kinds, as the label a blockquote gets in their place: the
// markdown view draws `> [!NOTE]` as the literal text.
const ALERTS = {
	NOTE: 'ℹ️ Note',
	TIP: '💡 Tip',
	IMPORTANT: '❗ Important',
	WARNING: '⚠️ Warning',
	CAUTION: '⛔ Caution',
};

/**
 * A 32-bit FNV-1a hash in hex, naming a rendered image after what it was made
 * from, so the same diagram is drawn once.
 *
 * @param {string} text
 * @returns {string}
 */
function hash(text) {
	let h = 0x811c9dc5;
	for (let i = 0; i < text.length; i++) {
		h ^= text.charCodeAt(i);
		h = Math.imul(h, 0x01000193) >>> 0;
	}
	return h.toString(16).padStart(8, '0');
}

/**
 * Splits markdown into what the markdown view draws itself (`text`) and what
 * it cannot, drawn as images instead: Mermaid blocks, and pictures on a line
 * of their own that live beside the document. Lines inside other code blocks
 * stay text, so a fence or an image shown as an example is left alone.
 *
 * @param {string} md
 * @returns {({kind: 'text', text: string} | {kind: 'mermaid', code: string} | {kind: 'image', src: string, alt: string})[]}
 * @example
 * segments("a\n```mermaid\ngraph LR\n```\nb") // => [text "a", mermaid "graph LR", text "b"]
 */
function segments(md) {
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
function inline(text, emoji) {
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

export default class Viewer extends View {
	init(_props, cx) {
		this.file = (props() ?? {}).file ?? null;
		this.on = (props() ?? {}).on ?? null;
		this.line = (props() ?? {}).line ?? null;
		this.text = null;
		this.lines = [];
		this.code = null;
		this.error = null;
		// What the body shows: `rendered` markdown, `highlight`ed code, or the
		// plain `lines` a search opens at. The editor can't be scrolled to a
		// line from a script, so a line is shown in a list that can.
		this.mode = this.line
			? 'lines'
			: isPicture(this.file ?? '')
				? 'picture'
				: isMarkdown(this.file ?? '')
					? 'rendered'
					: 'highlight';
		// The copy of a picture file the app can draw, with its size.
		this.picture = null;
		// The markdown's parts (see segments) and the images made for them.
		this.parts = [];
		this.assets = new Map();
		this.emoji = null;
		// Linked by nix/modules/home-darwin/herdr-app.nix; without it the
		// shortcodes stay as written.
		cx.spawn(async (cx) => {
			const text = await readTextFile(`${appHome()}/emoji.json`).catch(() => null);
			if (text) {
				this.emoji = JSON.parse(text);
				cx.notify();
			}
		});
		this.scroll = VirtualListScrollHandle.new();
		this.reveal = Boolean(this.line);
		this.load(cx);
		this.follow(cx);
	}

	// Re-reads the file whenever something in its folder changes, until this
	// view goes (the loop ends at its next use of a cx after that). Only here:
	// watchFolder cannot watch another machine's folders.
	follow(cx) {
		if (!this.file || this.on) return;
		const folder = this.file.slice(0, this.file.lastIndexOf('/')) || '/';
		cx.spawn(async (cx) => {
			try {
				for (;;) {
					const changed = await watchFolder(folder);
					if (changed.includes(this.file)) this.load(cx);
				}
			} catch {
				// A folder that cannot be watched leaves the view as first read.
			}
		});
	}

	load(cx) {
		if (!this.file) return;
		if (isPicture(this.file)) this.loadPicture(cx);
		// A picture other than an SVG has no text to show.
		if (isPicture(this.file) && !isSvg(this.file)) return;
		cx.spawn(async (cx) => {
			try {
				const text = await readTextFile(this.file, { on: this.on });
				if (text === null) this.error = 'This file is no longer available';
				else if (text.includes('\0')) this.error = 'Binary file · no text preview';
				else {
					this.error = null;
					this.text = text.length > LIMIT ? text.slice(0, LIMIT) + '\n… (file truncated)' : text;
					this.lines = this.text.split('\n');
					// Made here, not in render, which may not create host state;
					// a reload replaces the text of the one already made.
					if (this.code) this.code.set_value(this.text);
					else this.code = this.highlighted(this.text);
					if (isMarkdown(this.file)) {
						this.parts = segments(this.text);
						this.makeAssets(cx);
					}
				}
			} catch {
				this.error = 'Cannot read this file (too large, or unreadable)';
			} finally {
				cx.notify();
			}
		});
	}

	// Copies the picture to where the app can draw it (see md-asset), named
	// after the file and its modification time so an edited picture is copied
	// again rather than shown from the cache.
	loadPicture(cx) {
		cx.spawn(async (cx) => {
			try {
				const st = await exec('stat', ['-f', '%m', this.file]);
				if (st.code !== 0) throw new Error('This file is no longer available');
				const svg = isSvg(this.file);
				// An SVG is drawn as a PNG large enough to fill the view (see
				// md-asset), in the theme's text color where it asks for one.
				const name = `${hash(`${this.file}@${st.stdout.trim()}`)}.${svg ? 'png' : extOf(this.file)}`;
				const out = `${appHome()}/${ASSETS}/${name}`;
				await exec('mkdir', ['-p', `${appHome()}/${ASSETS}`]);
				const r = await exec(
					'md-asset',
					svg
						? ['svg', this.file, out, theme().foreground, String(SVG_SIZE)]
						: ['image', this.file, out],
				);
				const [w, h] = r.stdout.trim().split(' ').map(Number);
				if (r.code !== 0 || !w || !h)
					throw new Error(r.stderr.trim().split('\n').pop() || 'Cannot show this picture');
				this.picture = { path: `${ASSETS}/${name}`, w, h };
				this.error = null;
			} catch (e) {
				this.error = String(e.message ?? e);
			} finally {
				cx.notify();
			}
		});
	}

	// The picture, as large as the room allows but never enlarged, which
	// blurs it. An SVG arrives drawn at SVG_SIZE, so it still fills the view.
	pictureView(t) {
		const room = this.room ?? { width: 800, height: 600 };
		const p = this.picture;
		const fit = p
			? Math.min((room.width - PICTURE_PAD) / p.w, (room.height - PICTURE_PAD) / p.h)
			: 1;
		const k = Math.min(1, fit);
		return div()
			.id('viewer-picture')
			.flex_1()
			.min_h(0)
			.p(24)
			.flex()
			.items_center()
			.justify_center()
			.on_size_change((size, cx) => {
				const zoom = settings().zoom || 1;
				this.room = { width: size.width / zoom, height: size.height / zoom };
				cx.notify();
			})
			.child(
				p
					? image(p.path)
							.w(p.w * k)
							.h(p.h * k)
					: div().text_color(t.dim).child('Loading…'),
			);
	}

	// Makes the image for each Mermaid block, formula and picture not made yet,
	// one after another, redrawing as each is ready. A part keyed by what it
	// was made from keeps its image across reloads of the file.
	makeAssets(cx) {
		const dir = this.file.slice(0, this.file.lastIndexOf('/'));
		const wanted = this.parts.filter((p) => p.kind !== 'text');
		// Keyed before anything is made, so a part whose image exists from an
		// earlier read shows it at once rather than after the ones before it.
		const where = (part) => (part.remote ? part.src : resolve(dir, part.src));
		for (const part of wanted)
			part.key =
				part.kind === 'mermaid'
					? `m:${part.code}`
					: part.kind === 'math'
						? `x:${part.tex}`
						: `i:${where(part)}`;
		cx.spawn(async (cx) => {
			await exec('mkdir', ['-p', `${appHome()}/${ASSETS}`]).catch(() => null);
			for (const part of wanted) {
				const key = part.key;
				if (this.assets.has(key)) continue;
				this.assets.set(key, { state: 'pending' });
				cx.notify();
				try {
					const fg = theme().foreground;
					const name = hash(key);
					// Text a block is drawn from goes to a file md-asset reads,
					// so no shell quoting stands between the two.
					const source = async (ext, text) => {
						const f = `${appHome()}/${ASSETS}/${name}.${ext}`;
						if ((await readTextFile(f)) === null) await writeTextFile(f, text, null);
						return f;
					};
					let args, file;
					if (part.kind === 'mermaid') {
						file = `${name}.png`;
						args = ['mermaid', await source('mmd', part.code), `${appHome()}/${ASSETS}/${file}`];
					} else if (part.kind === 'math') {
						file = `${name}.png`;
						args = ['math', await source('tex', part.tex), `${appHome()}/${ASSETS}/${file}`, fg];
					} else if (part.remote) {
						file = `${name}.png`;
						args = ['url', part.src, `${appHome()}/${ASSETS}/${file}`, fg];
					} else {
						const src = where(part);
						file = `${name}.${isSvg(src) ? 'png' : extOf(src)}`;
						args = isSvg(src)
							? ['svg', src, `${appHome()}/${ASSETS}/${file}`, fg]
							: ['image', src, `${appHome()}/${ASSETS}/${file}`];
					}
					const r = await exec('md-asset', args, { timeout: 60000 });
					// Its size in pixels, and the pixels it drew per point.
					const [w, h, scale] = r.stdout.trim().split(' ').map(Number);
					if (r.code !== 0 || !w || !h)
						throw new Error(r.stderr.trim().split('\n').pop() || 'no image');
					this.assets.set(key, {
						state: 'ready',
						path: `${ASSETS}/${file}`,
						w: w / (scale || 1),
						h: h / (scale || 1),
					});
				} catch (e) {
					this.assets.set(key, { state: 'error', error: String(e.message ?? e) });
				}
				cx.notify();
			}
		});
	}

	// One part of the rendered markdown: the markdown view's own drawing for
	// text, an image for the rest once it is made, its source until then.
	part(t, p, i) {
		if (p.kind === 'text') return TextView.markdown(`viewer-md-${i}`, inline(p.text, this.emoji));
		const a = this.assets.get(p.key);
		if (a?.state === 'ready') {
			// Never wider than the view: scaled down, never up.
			const room = Math.max(120, (this.width ?? 800) - MD_PAD);
			const k = Math.min(1, room / a.w);
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
					`viewer-src-${i}`,
					p.kind === 'mermaid'
						? '```mermaid\n' + p.code + '\n```'
						: p.kind === 'math'
							? '```math\n' + p.tex + '\n```'
							: `![${p.alt}](${p.src})`,
				),
			);
	}

	// The editor's state for the highlighted view, in the theme's colors.
	highlighted(text) {
		const t = theme();
		return EditorState.new({
			language: LANG[extOf(this.file)] ?? extOf(this.file),
			readonly: true,
			value: text,
			font_family: settings().font_family,
			font_size: 12,
			syntax: {
				keyword: t.ansi5,
				string: t.ansi2,
				comment: t.dim,
				function: t.ansi4,
				type: t.ansi3,
				number: t.ansi1,
				constant: t.ansi6,
			},
		});
	}

	// The file as numbered lines, the searched-for one marked and brought to
	// the middle on the first frame that has it.
	linesView(t) {
		if (this.reveal) {
			this.scroll.scroll_to_item(Math.max(0, this.line - 1), 'center');
			this.reveal = false;
		}
		return div()
			.flex_1()
			.min_h(0)
			.relative()
			.font_family(settings().font_family ?? 'JetBrains Mono')
			.text_size(12)
			.child(
				v_virtual_list(
					'viewer-lines',
					this.lines.length,
					LINE_H,
					(i) => String(i),
					(range) =>
						this.lines.slice(range.start, range.end).map((text, k) => {
							const n = range.start + k + 1;
							const hit = n === this.line;
							return h_flex()
								.h(LINE_H)
								.w_full()
								.px(8)
								.gap(12)
								.when(hit, (e) => e.bg(t.selection))
								.child(
									div()
										.w(44)
										.flex_none()
										.text_right()
										.text_color(hit ? t.foreground : t.dim)
										.child(String(n)),
								)
								.child(
									div()
										.flex_1()
										.min_w(0)
										.truncate()
										.child(text.replace(/\t/g, '    ') || ' '),
								);
						}),
				)
					.track_scroll(this.scroll)
					.size_full(),
			)
			.child(Scrollbar.vertical('viewer-lines').absolute().inset_0());
	}

	close() {
		const overlay = props()?.overlay;
		if (overlay) closeOverlay(overlay);
	}

	button(t, id, label, action) {
		return div()
			.id(id)
			.h(24)
			.px(8)
			.flex()
			.items_center()
			.rounded(6)
			.text_size(11.5)
			.text_color(t.muted)
			.cursor_pointer()
			.hover((s) => s.bg(t.hover).text_color(t.foreground))
			.on_mouse_down('left', (_e, cx) => cx.stop_propagation())
			.on_click(action)
			.child(label);
	}

	render() {
		const t = theme();
		const file = this.file ?? '';
		const name = file.split('/').pop();
		const folder = file.slice(0, file.lastIndexOf('/')).replace(/^\/Users\/[^/]+/, '~');
		const overlay = Boolean(props()?.overlay);
		// The views this file has, as header buttons, when there is a choice.
		const modes = [
			...(isMarkdown(file) ? [['rendered', 'Preview']] : []),
			...(isPicture(file) ? [['picture', 'Image']] : []),
			...(!isPicture(file) || isSvg(file)
				? [['highlight', isMarkdown(file) ? 'Source' : 'Code']]
				: []),
			...(this.line ? [['lines', `Line ${this.line}`]] : []),
		];

		let body;
		if (!this.file) body = div().p(16).text_color(t.dim).child('No file');
		else if (this.error) body = div().p(16).text_color(t.dim).child(this.error);
		else if (this.mode === 'picture') body = this.pictureView(t);
		else if (this.text === null) body = div().p(16).text_color(t.dim).child('Loading…');
		else if (this.mode === 'lines') body = this.linesView(t);
		else if (this.mode === 'rendered')
			body = div()
				.id('viewer-markdown')
				.flex_1()
				.min_h(0)
				.overflow_y_scrollbar()
				.px(28)
				.py(20)
				.on_size_change((size, cx) => {
					this.width = size.width / (settings().zoom || 1);
					cx.notify();
				})
				.child(
					v_flex()
						.gap(4)
						.children(this.parts.map((p, i) => this.part(t, p, i))),
				);
		else body = Editor.new(this.code).flex_1().min_h(0);

		return v_flex()
			.size_full()
			.min_h(0)
			.bg(t.background)
			.text_color(t.foreground)
			.text_size(13)
			.child(
				h_flex()
					.h(34)
					.flex_none()
					.px(12)
					.gap(8)
					.items_center()
					.border_b(1)
					.border_color(t.border)
					.child(div().flex_none().font_semibold().child(name))
					.child(div().flex_1().min_w(0).truncate().text_size(11.5).text_color(t.dim).child(folder))
					.when(modes.length > 1, (el) =>
						el.children(
							modes.map(([mode, label]) =>
								this.button(t, `viewer-${mode}`, label, (_e, cx) => {
									this.mode = mode;
									this.reveal = mode === 'lines';
									cx.notify();
								}).when(this.mode === mode, (b) => b.bg(t.selected).text_color(t.foreground)),
							),
						),
					)
					.when(overlay, (el) =>
						el
							.child(
								// Keeps it beside the terminals instead, for reading
								// along while working.
								this.button(t, 'viewer-pane', 'Pane', () => {
									run('pane.split', {
										direction: 'right',
										mod: 'viewer',
										props: { file: this.file, on: this.on, line: this.line },
									});
									this.close();
								}),
							)
							.child(
								this.button(t, 'viewer-close', svg('mods/pane/close.svg').size(12), () =>
									this.close(),
								),
							),
					),
			)
			.child(body);
	}
}
