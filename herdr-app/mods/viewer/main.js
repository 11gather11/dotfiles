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
import { SIZE, SPACE, TEXT, RADIUS, button as uiButton } from './lib/ui.js';
import { Markdown, ASSETS, hash, extOf, isSvg } from './lib/markdown.js';

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

const isMarkdown = (file) => ['md', 'markdown', 'mdx'].includes(extOf(file));
// Files shown as a picture. An SVG is text too, so it also has a code view;
// the others are only pictures.
const PICTURES = ['svg', 'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'tif', 'tiff'];
const isPicture = (file) => PICTURES.includes(extOf(file));
// Padding around a picture (p(24) in render), for the room it may take.
const PICTURE_PAD = 48;
// The longest side an SVG file is drawn at for the picture view: as large as
// the view gets, so it is only ever scaled down.
const SVG_SIZE = 1600;
// The line list's row height, the size its virtual list is told.
const LINE_H = 20;
// The rendered markdown's side padding (px(28) in render), for the width an
// image may take.
const MD_PAD = 56;

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
		// The rendered document (lib/markdown.js), made here as render may not.
		this.md = new Markdown('viewer-md');
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
					if (isMarkdown(this.file))
						this.md.set(this.text, this.file.slice(0, this.file.lastIndexOf('/')), cx);
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
			.text_size(TEXT.ui)
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
								.gap(SPACE.md)
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
		return uiButton(t, id, label, action);
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
				.child(this.md.view(t, (this.width ?? 800) - MD_PAD));
		else body = Editor.new(this.code).flex_1().min_h(0);

		return v_flex()
			.size_full()
			.min_h(0)
			.bg(t.background)
			.text_color(t.foreground)
			.text_size(TEXT.body)
			.child(
				h_flex()
					.h(SIZE.bar)
					.flex_none()
					.px(12)
					.gap(SPACE.sm)
					.items_center()
					.border_b(1)
					.border_color(t.border)
					.child(div().flex_none().font_semibold().child(name))
					.child(
						div().flex_1().min_w(0).truncate().text_size(TEXT.meta).text_color(t.dim).child(folder),
					)
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
