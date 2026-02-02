import * as k from 'karabiner.ts';
import { getDeviceId } from './utils.ts';

// HHKB-Hybrid (動的に検出、見つからない場合はデフォルト値)
export const HHKB =
	(await getDeviceId('HHKB-Hybrid_1')) ??
	({ vendor_id: 1278, product_id: 33 } as const satisfies k.DeviceIdentifier);

// MacBook内蔵キーボードだけに適用する条件 (HHKB以外)
export const ifNotHHKB = k.ifDevice([HHKB]).unless();

// HHKBだけに適用する条件
export const ifHHKB = k.ifDevice([HHKB]);
