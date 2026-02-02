import * as k from 'karabiner.ts';
import { z } from 'zod';
import { $ } from 'bun';

export function toHideApp(name: string) {
	return k.to$(
		`osascript -e 'tell application "System Events" to set visible of process "${name}" to false'`,
	);
}

async function findAppPath(appName: string): Promise<string | undefined> {
	// Try mdfind first
	const output =
		await $`mdfind "kMDItemKind == 'Application' && kMDItemFSName == '${appName}.app'"`.text();
	const mdfindResult = output.trim().split('\n').at(0);

	if (mdfindResult) {
		return mdfindResult;
	}

	// Fallback: check /Applications directly
	const directPath = `/Applications/${appName}.app`;
	const exists = await $`test -d ${directPath}`.quiet().nothrow();

	return exists.exitCode === 0 ? directPath : undefined;
}

export async function extractIdentifier(appName: string): Promise<string> {
	const appPath = await findAppPath(appName);

	if (appPath == null) {
		throw new Error(`Application ${appName} not found`);
	}

	const output = await $`mdls -name kMDItemCFBundleIdentifier ${appPath}`.text();

	const identifier = output
		.match(/"(.*)"/)
		?.at(1)
		?.trim();

	return z.string().parse(identifier, {
		error: () => `Failed to extract bundle identifier for ${appName}`,
	});
}

export async function extractIdentifierOptional(appName: string): Promise<string | undefined> {
	try {
		return await extractIdentifier(appName);
	} catch {
		return undefined;
	}
}

export async function getDeviceId(
	deviceName: string,
): Promise<Readonly<k.DeviceIdentifier | undefined>> {
	const output = await $`hidutil list -n`.text();
	const lines = output.trim().split('\n').filter(Boolean);

	const devices = lines.map((line) => JSON.parse(line));

	const _devices = new Map(
		devices.map((device) => [
			device.Product,
			{
				product_id: device.ProductID as number,
				vendor_id: device.VendorID as number,
			} as const satisfies k.DeviceIdentifier,
		]),
	);

	return _devices.get(deviceName);
}

export const ifTrackpadTouched = k.ifVar('multitouch_extension_finger_count_total', 0).unless();
