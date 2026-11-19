// The right-click menu of an entry in the files-icons panel: what VS Code's
// explorer offers for it — reveal it in Finder, open it in its default app,
// copy its path. Opened as a popup with props { root, path, dir, on }: the panel's
// folder, the entry's path under it, whether it is a folder, and the machine.
// ↑/↓ move, Enter runs, Esc closes, as in Herdr's own menu mod.
import { View, div, svg } from 'gpui-kit';
import { v_flex, h_flex } from 'gpui-base';
import { props, closeOverlay, theme, exec, notify } from 'herdr';
import { SIZE, SPACE, TEXT, RADIUS } from './lib/ui.js';

/**
 * The menu's entries for one file or folder. An item is [label, icon, action];
 * null draws a separator.
 *
 * Finder and the default apps are this Mac's, so on a remote machine only the
 * copies are offered: the path names a file there, not here.
 *
 * @param {{ root: string, path: string, dir: boolean, on: string | null }} p
 * @returns {([string, string, (cx: import('gpui-kit').Context) => void] | null)[]}
 */
function items(p) {
	// `herdr-app check` renders the mod with no props.
	if (!p?.path) return [];
	const full = `${p.root}/${p.path}`;
	const name = p.path.split('/').pop();
	const local = !p.on;
	return [
		...(local
			? [
					['Reveal in Finder', 'folder', () => open(['-R', full])],
					...(p.dir ? [] : [['Open with Default App', 'square', () => open([full])]]),
					null,
				]
			: []),
		['Copy Path', 'files', (cx) => copy(cx, full, 'Path')],
		['Copy Relative Path', 'files', (cx) => copy(cx, p.path, 'Relative path')],
		['Copy Name', 'files', (cx) => copy(cx, name, 'Name')],
	];
}

function open(args) {
	exec('open', args).then((r) => {
		if (r.code !== 0)
			notify({ title: 'Could not open', body: r.stderr.trim(), level: 'error', timeout: 4000 });
	});
}

function copy(cx, text, what) {
	cx.write_to_clipboard(text);
	notify({ title: `${what} copied`, body: text, level: 'success', timeout: 1500 });
}

export default class FileMenu extends View {
	init(_props, cx) {
		this.at = 0;
		this.handle = cx.focus_handle();
		this.handle.focus();
	}

	choose(item, cx) {
		closeOverlay(props().overlay);
		item[2](cx);
	}

	render(_cx) {
		const t = theme();
		const list = items(props());
		const actions = list.filter(Boolean);
		if (!actions.length) return div();
		return v_flex()
			.id('file-menu')
			.track_focus(this.handle)
			.w_full()
			.min_h(0)
			.p(5)
			.bg(t.popover)
			.text_size(TEXT.body)
			.on_key_down((e, cx) => {
				if (e.key === 'down') this.at = (this.at + 1) % actions.length;
				else if (e.key === 'up') this.at = (this.at + actions.length - 1) % actions.length;
				else if (e.key === 'enter') this.choose(actions[this.at], cx);
				else if (e.key === 'escape') closeOverlay(props().overlay);
				else return;
				cx.notify();
			})
			.children(
				list.map((it, i) =>
					it === null
						? div().mx(7).my(SPACE.xs).h(1).bg(t.border)
						: h_flex()
								.id(`fm-${i}`)
								.h(SIZE.row + 4)
								.px(SPACE.sm)
								.gap(SPACE.sm)
								.rounded(RADIUS.control)
								.items_center()
								.cursor_pointer()
								.text_color(t.foreground)
								.when(actions.indexOf(it) === this.at, (el) => el.bg(t.selected))
								.hover((s) => s.bg(t.hover))
								.on_click((_e, cx) => this.choose(it, cx))
								.child(
									svg(`mods/workspace-chrome/${it[1]}.svg`)
										.size(14)
										.flex_none()
										.text_color(t.muted),
								)
								.child(div().flex_1().child(it[0])),
				),
			);
	}
}
