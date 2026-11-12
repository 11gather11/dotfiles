// One file, read-only: markdown rendered (its source a click away), anything
// else as highlighted code. It follows the file as it changes, so it serves
// as a live preview while the file is written elsewhere.
//
// Opened over the window as a dialog (the file tree does so on a click) or as
// a pane beside the terminals: `pane.split {mod: "viewer", props: {file}}`.
// props: `file`, an absolute path; `on`, the machine it is on (null: here).
import { View, div, svg } from 'gpui-kit';
import { v_flex, h_flex, Editor, EditorState, TextView } from 'gpui-base';
import { props, readTextFile, watchFolder, theme, settings, run, closeOverlay } from 'herdr';

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
	vue: 'html',
};
// Past this, the rest of a file is cut: the editor holds it all in memory.
const LIMIT = 400000;

const extOf = (file) => (file.includes('.') ? file.split('.').pop().toLowerCase() : 'txt');
const isMarkdown = (file) => ['md', 'markdown', 'mdx'].includes(extOf(file));

export default class Viewer extends View {
	init(_props, cx) {
		this.file = (props() ?? {}).file ?? null;
		this.on = (props() ?? {}).on ?? null;
		this.text = null;
		this.code = null;
		this.error = null;
		this.source = false;
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
		cx.spawn(async (cx) => {
			try {
				const text = await readTextFile(this.file, { on: this.on });
				if (text === null) this.error = 'This file is no longer available';
				else if (text.includes('\0')) this.error = 'Binary file · no text preview';
				else {
					this.error = null;
					this.text = text.length > LIMIT ? text.slice(0, LIMIT) + '\n… (file truncated)' : text;
					this.code?.release();
					this.code = null;
				}
			} catch {
				this.error = 'Cannot read this file (too large, or unreadable)';
			} finally {
				cx.notify();
			}
		});
	}

	// The highlighted source, made on first need and again after each reload.
	editor(t) {
		if (!this.code)
			this.code = EditorState.new({
				language: LANG[extOf(this.file)] ?? extOf(this.file),
				readonly: true,
				value: this.text,
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
		return Editor.new(this.code).flex_1().min_h(0);
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
		const markdown = isMarkdown(file) && !this.source;
		const overlay = Boolean(props()?.overlay);

		let body;
		if (!this.file) body = div().p(16).text_color(t.dim).child('No file');
		else if (this.error) body = div().p(16).text_color(t.dim).child(this.error);
		else if (this.text === null) body = div().p(16).text_color(t.dim).child('Loading…');
		else if (markdown)
			body = div()
				.id('viewer-markdown')
				.flex_1()
				.min_h(0)
				.overflow_y_scrollbar()
				.px(28)
				.py(20)
				.child(TextView.markdown('viewer-md', this.text));
		else body = this.editor(t);

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
					.when(isMarkdown(file), (el) =>
						el.child(
							this.button(t, 'viewer-source', this.source ? 'Preview' : 'Source', (_e, cx) => {
								this.source = !this.source;
								cx.notify();
							}),
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
										props: { file: this.file, on: this.on },
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
