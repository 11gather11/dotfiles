import * as k from 'karabiner.ts';
import * as utils from './utils.ts';

const IDENTIFIERS = {
	discord: await utils.extractIdentifierOptional('Discord'),
	chatgpt: await utils.extractIdentifierOptional('ChatGPT'),
	claude: await utils.extractIdentifierOptional('Claude'),
} as const;

// アプリが見つかった場合のみbundle_identifiersに追加
const chatAppBundleIds = [IDENTIFIERS.discord, IDENTIFIERS.chatgpt, IDENTIFIERS.claude].filter(
	(id): id is string => id != null,
);

k.writeToProfile(
	'Default profile',
	[
		// Caps Lock -> Control (simple modification で設定)

		k.rule('Tap Ctrl -> japanese_eisuu + ESC').manipulators([
			k
				.map({ key_code: 'left_control', modifiers: { optional: ['any'] } })
				.to({ key_code: 'left_control', lazy: true })
				.toIfAlone([{ key_code: 'japanese_eisuu' }, { key_code: 'escape' }]),
		]),

		k
			.rule('Tap ESC -> japanese_eisuu + esc')
			.manipulators([
				k.map({ key_code: 'escape' }).to([{ key_code: 'japanese_eisuu' }, { key_code: 'escape' }]),
			]),

		k.rule('Quit application by holding command-q').manipulators([
			k
				.map({
					key_code: 'q',
					modifiers: { mandatory: ['command'], optional: ['caps_lock'] },
				})
				.toIfHeldDown({
					key_code: 'q',
					modifiers: ['command'],
					repeat: false,
				}),
		]),

		// Discord/ChatGPT/Claudeがインストールされている場合のみルールを追加
		...(chatAppBundleIds.length > 0
			? [
					k
						.rule(
							'Swap Enter & Shift+Enter and CMD+Enter -> Enter on Discord/ChatGPT/Claude',
							k.ifApp(chatAppBundleIds),
						)
						.manipulators([
							k
								.map({
									key_code: 'return_or_enter',
									modifiers: { mandatory: ['shift'] },
								})
								.to({ key_code: 'return_or_enter' }),

							k
								.map({
									key_code: 'return_or_enter',
									modifiers: { mandatory: ['command'] },
								})
								.to({ key_code: 'return_or_enter' }),

							k
								.map({ key_code: 'return_or_enter' })
								.to({ key_code: 'return_or_enter', modifiers: ['shift'] }),
						]),
				]
			: []),

		k.rule('Tap CMD to toggle Kana/Eisuu').manipulators([
			k.withMapper<k.ModifierKeyCode, k.JapaneseKeyCode>({
				left_command: 'japanese_eisuu',
				right_command: 'japanese_kana',
			} as const)((cmd, lang) =>
				k
					.map({ key_code: cmd, modifiers: { optional: ['any'] } })
					.to({ key_code: cmd, lazy: true })
					.toIfAlone({ key_code: lang })
					.description(`Tap ${cmd} alone to switch to ${lang}`)
					.parameters({ 'basic.to_if_held_down_threshold_milliseconds': 100 }),
			),
		]),

		k.rule('Hold tab to super key, tap tab to tab').manipulators([
			k
				.map({ key_code: 'tab' })
				.toIfAlone({ key_code: 'tab', lazy: true })
				.toIfHeldDown({ key_code: 'tab', repeat: true })
				.to({
					key_code: 'left_command',
					modifiers: ['left_option', 'left_shift', 'left_control'],
				}),
		]),

		k.rule('fn + h/j/k/l to arrow keys').manipulators([
			k.withMapper<k.LetterKeyCode, k.ArrowKeyCode>({
				h: 'left_arrow',
				j: 'down_arrow',
				k: 'up_arrow',
				l: 'right_arrow',
			} as const)((key, arrow) =>
				k
					.map({
						key_code: key,
						modifiers: { mandatory: ['fn'] },
					})
					.to({ key_code: arrow })
					.description(`Tap ${key} to ${arrow}`),
			),
		]),

		k.rule('Right option to super key').manipulators([
			k.map({ key_code: 'right_option' }).to({
				key_code: 'right_command',
				modifiers: ['right_option', 'right_shift', 'right_control'],
			}),
		]),
	],
	{
		'basic.to_if_alone_timeout_milliseconds': 1000,
		'basic.to_if_held_down_threshold_milliseconds': 500,
		'basic.to_delayed_action_delay_milliseconds': 500,
		'basic.simultaneous_threshold_milliseconds': 50,
		'mouse_motion_to_scroll.speed': 100,
	},
);
