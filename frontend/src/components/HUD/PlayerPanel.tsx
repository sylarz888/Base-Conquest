'use client';

import { UNIT_META } from '@/types/game';
import { cn, shortAddress, playerColor } from '@/lib/utils';
import type { Address } from 'viem';

// ── Army Badge ─────────────────────────────────────────────────────────────────

function ArmyBadge({ unitType, count }: { unitType: number; count: bigint }) {
  const meta = UNIT_META[unitType as keyof typeof UNIT_META];
  if (!meta || count === 0n) return null;
  return (
    <div
      className="flex items-center gap-1.5 px-2 py-1 rounded-md border text-xs font-mono"
      style={{ backgroundColor: meta.bgColor, borderColor: meta.color + '66' }}
      title={meta.effect}
    >
      <span style={{ color: meta.color }}>{meta.symbol}</span>
      <span className="text-slate-300">{count.toString()}</span>
      <span className="text-slate-500">{meta.name}</span>
    </div>
  );
}

// ── Card Badge ─────────────────────────────────────────────────────────────────

const CARD_COLORS = { 1: '#94a3b8', 2: '#f6c84e', 3: '#e05252' } as const;
const CARD_NAMES  = { 1: 'Infantry', 2: 'Cavalry', 3: 'Artillery' } as const;

function CardBadge({ type, count }: { type: 1 | 2 | 3; count: bigint }) {
  if (count === 0n) return null;
  return (
    <div
      className="flex items-center gap-1 px-2 py-0.5 rounded text-xs border"
      style={{ borderColor: CARD_COLORS[type] + '55', color: CARD_COLORS[type] }}
    >
      <span>🃏</span>
      <span>{count.toString()} {CARD_NAMES[type]}</span>
    </div>
  );
}

// ── Stat Row ──────────────────────────────────────────────────────────────────

function StatRow({ label, value, accent }: { label: string; value: string | number; accent?: boolean }) {
  return (
    <div className="flex justify-between items-center text-xs py-0.5">
      <span className="text-slate-500">{label}</span>
      <span className={cn('font-mono', accent ? 'text-gold-400' : 'text-slate-300')}>
        {value}
      </span>
    </div>
  );
}

// ── Main Component ─────────────────────────────────────────────────────────────

export interface PlayerPanelProps {
  address: Address | undefined;
  territories: number;
  continentsControlled: number;
  armyBalances: bigint[];      // index 0-4 → Infantry–Admiral
  cardBalances: bigint[];      // index 0-2 → Infantry–Artillery cards
  turnPhase: string;
  globalTurn: bigint;
  seasonEndsAt: bigint;
  hasPendingCombat: boolean;
  isTurnActive: boolean;
  onStartTurn: () => void;
  onEndTurn: () => void;
  className?: string;
}

export function PlayerPanel({
  address,
  territories,
  continentsControlled,
  armyBalances,
  cardBalances,
  turnPhase,
  globalTurn,
  hasPendingCombat,
  isTurnActive,
  onStartTurn,
  onEndTurn,
  className,
}: PlayerPanelProps) {
  const color = playerColor(address);
  const totalCards = cardBalances.reduce((s, c) => s + c, 0n);

  return (
    <div className={cn(
      'flex flex-col gap-3 rounded-xl border bg-ocean-900/95 p-4 text-sm backdrop-blur',
      className,
    )}
      style={{ borderColor: color + '44' }}
    >
      {/* Header */}
      <div className="flex items-center gap-2">
        <div className="w-3 h-3 rounded-full flex-shrink-0" style={{ backgroundColor: color }} />
        <span className="font-display text-white font-semibold truncate">
          {address ? shortAddress(address) : 'Not connected'}
        </span>
        {isTurnActive && (
          <span className="ml-auto text-xs px-1.5 py-0.5 rounded bg-gold-500/20 text-gold-400 border border-gold-500/30 flex-shrink-0">
            YOUR TURN
          </span>
        )}
      </div>

      {/* Stats */}
      <div className="rounded-lg bg-ocean-950/60 p-2 border border-white/5 space-y-0.5">
        <StatRow label="Territories"  value={territories} accent={territories > 20} />
        <StatRow label="Continents"   value={continentsControlled} />
        <StatRow label="Global Turn"  value={globalTurn.toString()} />
        <StatRow label="Phase"        value={turnPhase} accent />
      </div>

      {/* Armies in hand */}
      {armyBalances.some(b => b > 0n) && (
        <div>
          <p className="text-xs text-slate-500 mb-1.5 uppercase tracking-wide">Armies in hand</p>
          <div className="flex flex-wrap gap-1.5">
            {armyBalances.map((bal, i) => (
              <ArmyBadge key={i} unitType={i + 1} count={bal} />
            ))}
          </div>
        </div>
      )}

      {/* Territory cards */}
      {totalCards > 0n && (
        <div>
          <p className="text-xs text-slate-500 mb-1.5 uppercase tracking-wide">
            Territory Cards ({totalCards.toString()})
          </p>
          <div className="flex flex-wrap gap-1.5">
            {cardBalances.map((bal, i) =>
              <CardBadge key={i} type={(i + 1) as 1 | 2 | 3} count={bal} />
            )}
          </div>
        </div>
      )}

      {/* Pending combat warning */}
      {hasPendingCombat && (
        <div className="flex items-center gap-2 rounded-lg bg-danger/10 border border-danger/30 px-3 py-2">
          <span className="text-danger text-lg">⚔</span>
          <div className="text-xs">
            <p className="text-danger font-medium">Combat pending</p>
            <p className="text-slate-400">Awaiting VRF oracle…</p>
          </div>
        </div>
      )}

      {/* Turn controls */}
      <div className="mt-1 flex flex-col gap-2">
        {!isTurnActive ? (
          <button
            onClick={onStartTurn}
            disabled={!address}
            className="w-full py-2 rounded-lg font-display font-semibold text-sm
              bg-gold-500 text-ocean-950 hover:bg-gold-400 active:bg-gold-600
              disabled:opacity-40 disabled:cursor-not-allowed
              transition-colors duration-150 shadow-lg"
          >
            Start Turn
          </button>
        ) : (
          <button
            onClick={onEndTurn}
            disabled={hasPendingCombat}
            className="w-full py-2 rounded-lg font-display font-semibold text-sm
              bg-ocean-700 text-white hover:bg-ocean-600 active:bg-ocean-800
              border border-white/10
              disabled:opacity-40 disabled:cursor-not-allowed
              transition-colors duration-150"
          >
            End Turn
          </button>
        )}
      </div>
    </div>
  );
}
