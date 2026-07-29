#!/usr/bin/env bun
/**
 * Ensure the TypeWhisper dictionary contains the custom terms and corrections
 * defined in dictionary.json, via its local HTTP API.
 *
 * This is intentionally ADDITIVE, not a mirror. Activating a term pack
 * materialises its terms and corrections into the same dictionary store this
 * API exposes, and the API gives no way to tell pack-provided entries apart
 * from user-defined ones. A wholesale replace would therefore wipe every
 * activated term pack, so we only ever merge our own entries in and never
 * delete. To remove an entry, delete it in the app (or with an explicit
 * DELETE request).
 *
 * The TypeWhisper HTTP API must be enabled in Settings > Advanced. It binds to
 * 127.0.0.1 only. Override the port with $TYPEWHISPER_PORT and the bearer
 * token with $TYPEWHISPER_API_TOKEN when the defaults do not match.
 *
 * @example
 * ```sh
 * ./dict-sync.ts             # sync from dictionary.json beside this script
 * ./dict-sync.ts other.json  # sync from a specific file
 * ./dict-sync.ts --strict    # exit non-zero when the API is unreachable
 * ```
 */

import { dirname, join, resolve } from 'node:path';

/** A literal replacement applied to a transcription. */
interface Correction {
	original: string;
	replacement: string;
	caseSensitive: boolean;
}

/** The dictionary as stored in dictionary.json. */
interface Dictionary {
	terms: string[];
	corrections: Correction[];
}

/**
 * Validate the parsed contents of a dictionary file.
 *
 * @param data - Parsed JSON of unknown shape.
 * @param source - File path, used in error messages.
 * @returns The validated dictionary.
 * @throws When the shape does not match {@link Dictionary}.
 */
function parseDictionary(data: unknown, source: string): Dictionary {
	if (typeof data !== 'object' || data === null || Array.isArray(data)) {
		throw new Error(`${source}: expected a JSON object`);
	}

	const { terms, corrections } = data as Record<string, unknown>;

	if (!Array.isArray(terms) || !terms.every((t) => typeof t === 'string')) {
		throw new Error(`${source}: "terms" must be an array of strings`);
	}

	const shape = '{original, replacement, caseSensitive}';
	if (!Array.isArray(corrections)) {
		throw new Error(`${source}: "corrections" must be an array of ${shape}`);
	}
	for (const c of corrections) {
		if (
			typeof c !== 'object' ||
			c === null ||
			typeof (c as Correction).original !== 'string' ||
			typeof (c as Correction).replacement !== 'string' ||
			typeof (c as Correction).caseSensitive !== 'boolean'
		) {
			throw new Error(`${source}: "corrections" must be an array of ${shape}`);
		}
	}

	return { terms, corrections: corrections as Correction[] };
}

/** Build request headers, adding bearer auth only when a token is configured. */
function authHeaders(): Record<string, string> {
	const headers: Record<string, string> = { 'Content-Type': 'application/json' };
	const token = process.env.TYPEWHISPER_API_TOKEN ?? '';
	if (token !== '') {
		headers.Authorization = `Bearer ${token}`;
	}
	return headers;
}

async function main(): Promise<void> {
	const args = process.argv.slice(2);
	const strict = args.includes('--strict');
	const fileArg = args.find((a) => !a.startsWith('--'));
	const file =
		fileArg === undefined ? join(dirname(import.meta.path), 'dictionary.json') : resolve(fileArg);

	const dict = parseDictionary(await Bun.file(file).json(), file);

	const port = process.env.TYPEWHISPER_PORT ?? '8978';
	const root = `http://localhost:${port}`;
	const base = `${root}/v1/dictionary`;
	const headers = authHeaders();

	// Optional dependency: skip quietly unless --strict.
	const reachable = await fetch(`${root}/v1/status`, { headers })
		.then((r) => r.ok)
		.catch(() => false);

	if (!reachable) {
		const message = `typewhisper-dict-sync: API not reachable on :${port} — enable it in Settings > Advanced`;
		if (strict) {
			throw new Error(message);
		}
		console.error(`${message} (skipping)`);
		return;
	}

	// terms: merge our terms in. replace:false keeps term-pack terms intact.
	await fetch(`${base}/terms`, {
		method: 'PUT',
		headers,
		body: JSON.stringify({ terms: dict.terms, replace: false }),
	});

	// corrections: add or update each one (PUT is idempotent per original).
	for (const correction of dict.corrections) {
		await fetch(`${base}/corrections`, {
			method: 'PUT',
			headers,
			body: JSON.stringify(correction),
		});
	}

	console.log(
		`typewhisper-dict-sync: synced ${dict.terms.length} terms, ${dict.corrections.length} corrections from ${file}`,
	);
}

await main();
