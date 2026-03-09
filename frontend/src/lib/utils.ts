import { type ClassValue, clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';
import type { Address } from 'viem';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** Shorten a wallet address for display. */
export function shortAddress(addr: Address | string | undefined): string {
  if (!addr) return '—';
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

/** Format a bigint as a human-readable number. */
export function fmt(n: bigint | number | undefined): string {
  if (n === undefined) return '—';
  return Number(n).toLocaleString();
}

/** Countdown string from a Unix timestamp. */
export function countdown(endsAt: number): string {
  const diff = endsAt - Math.floor(Date.now() / 1000);
  if (diff <= 0) return 'Ended';
  const d = Math.floor(diff / 86400);
  const h = Math.floor((diff % 86400) / 3600);
  const m = Math.floor((diff % 3600) / 60);
  if (d > 0) return `${d}d ${h}h`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

/** Hex polygon points string for SVG flat-top hex of radius r around (cx, cy). */
export function hexPoints(cx: number, cy: number, r: number): string {
  const pts: string[] = [];
  for (let i = 0; i < 6; i++) {
    const angleDeg = 60 * i;           // flat-top
    const angleRad = (Math.PI / 180) * angleDeg;
    pts.push(`${(cx + r * Math.cos(angleRad)).toFixed(2)},${(cy + r * Math.sin(angleRad)).toFixed(2)}`);
  }
  return pts.join(' ');
}

/** Returns a deterministic player color for an address (for map coloring). */
const PLAYER_COLORS = [
  '#e05252', '#4a90d9', '#4aae6a', '#f6c84e',
  '#c084fc', '#38bdf8', '#fb923c', '#f472b6',
];

export function playerColor(addr: Address | string | undefined): string {
  if (!addr) return '#374151';
  const n = parseInt(addr.slice(2, 8), 16);
  return PLAYER_COLORS[n % PLAYER_COLORS.length];
}

/** Plural helper. */
export function plural(n: number, singular: string, plural_?: string): string {
  return `${n} ${n === 1 ? singular : (plural_ ?? singular + 's')}`;
}
