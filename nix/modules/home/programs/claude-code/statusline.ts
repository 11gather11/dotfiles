#!/usr/bin/env bun

const data = await Bun.readableStreamToJSON(Bun.stdin.stream());

const BLOCKS = ' ▏▎▍▌▋▊▉█';
const R = '\x1b[0m';
const DIM = '\x1b[2m';

function gradient(pct: number): string {
	if (pct < 50) {
		const r = Math.floor(pct * 5.1);
		return `\x1b[38;2;${r};200;80m`;
	}
	const g = Math.floor(200 - (pct - 50) * 4);
	return `\x1b[38;2;255;${Math.max(g, 0)};60m`;
}

function bar(pct: number, width = 10): string {
	pct = Math.min(Math.max(pct, 0), 100);
	const filled = (pct * width) / 100;
	const full = Math.floor(filled);
	const frac = Math.floor((filled - full) * 8);
	let b = '█'.repeat(full);
	if (full < width) {
		b += BLOCKS[frac];
		b += '░'.repeat(width - full - 1);
	}
	return b;
}

function fmt(label: string, pct: number): string {
	const p = Math.round(pct);
	return `${label} ${gradient(pct)}${bar(pct)} ${p}%${R}`;
}

const model = data?.model?.display_name ?? 'Claude';
const parts: string[] = [model];

const ctx = data?.context_window?.used_percentage;
if (ctx != null) parts.push(fmt('ctx', ctx));

const five = data?.rate_limits?.five_hour?.used_percentage;
if (five != null) parts.push(fmt('5h', five));

const week = data?.rate_limits?.seven_day?.used_percentage;
if (week != null) parts.push(fmt('7d', week));

process.stdout.write(parts.map((p) => ` ${p} `).join(`${DIM}│${R}`));
