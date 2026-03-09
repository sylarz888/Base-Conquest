'use client';

import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { cn } from '@/lib/utils';
import { UNIT_META } from '@/types/game';
import type { TurnPhase, AttackStep } from '@/types/game';

// ── Phase indicator ───────────────────────────────────────────────────────────

const PHASES: { id: TurnPhase; label: string; icon: string; description: string }[] = [
  { id: 0, label: 'Reinforce', icon: '🛡', description: 'Deploy your armies and redeem card sets' },
  { id: 1, label: 'Attack',    icon: '⚔',  description: 'Launch up to 3 attacks using Chainlink VRF dice' },
  { id: 2, label: 'Fortify',   icon: '🏰', description: 'Move armies once between adjacent territories' },
];

function PhaseBar({ currentPhase, isTurnActive }: { currentPhase: TurnPhase; isTurnActive: boolean }) {
  return (
    <div className="flex items-center gap-0.5 rounded-full bg-ocean-950/80 p-1 border border-white/10">
      {PHASES.map((p, i) => {
        const active  = isTurnActive && currentPhase === p.id;
        const done    = isTurnActive && currentPhase > p.id;
        return (
          <div key={p.id} className="flex items-center">
            <div
              title={p.description}
              className={cn(
                'flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium transition-all duration-300',
                active ? 'bg-gold-500 text-ocean-950'
                  : done ? 'text-slate-400 bg-ocean-800/50'
                  : 'text-slate-600',
              )}
            >
              <span>{p.icon}</span>
              <span className="hidden sm:inline">{p.label}</span>
            </div>
            {i < PHASES.length - 1 && (
              <div className={cn('w-4 h-px mx-0.5', done ? 'bg-slate-500' : 'bg-ocean-800')} />
            )}
          </div>
        );
      })}
    </div>
  );
}

// ── Reinforce Controls ─────────────────────────────────────────────────────────

export interface ReinforceControlsProps {
  selectedTerritory: number | null;
  armyBalances: bigint[];
  onReinforce: (territoryId: number, unitType: number, amount: number) => Promise<void>;
  onBeginAttack: () => void;
}

function ReinforceControls({ selectedTerritory, armyBalances, onReinforce, onBeginAttack }: ReinforceControlsProps) {
  const [selectedUnit, setSelectedUnit] = useState(1);
  const [amount, setAmount]             = useState(1);
  const [loading, setLoading]           = useState(false);

  const available = armyBalances[selectedUnit - 1] ?? 0n;

  async function handleReinforce() {
    if (!selectedTerritory) return;
    setLoading(true);
    try { await onReinforce(selectedTerritory, selectedUnit, amount); }
    finally { setLoading(false); }
  }

  return (
    <div className="flex items-center gap-3 flex-wrap">
      {!selectedTerritory && (
        <p className="text-xs text-slate-500">Select a territory to reinforce</p>
      )}

      {selectedTerritory && (
        <>
          {/* Unit selector */}
          <div className="flex gap-1">
            {[1, 2, 3, 4, 5].map(ut => {
              const meta = UNIT_META[ut as keyof typeof UNIT_META];
              const bal  = armyBalances[ut - 1] ?? 0n;
              return (
                <button
                  key={ut}
                  onClick={() => { setSelectedUnit(ut); setAmount(1); }}
                  disabled={bal === 0n}
                  title={`${meta.name} — ${meta.effect}`}
                  className={cn(
                    'flex items-center gap-1 px-2 py-1 rounded-md text-xs border transition-colors',
                    selectedUnit === ut
                      ? 'border-gold-500 bg-gold-500/10 text-gold-400'
                      : 'border-white/10 text-slate-400 hover:border-white/25',
                    bal === 0n && 'opacity-30 cursor-not-allowed',
                  )}
                >
                  <span>{meta.symbol}</span>
                  <span>{Number(bal)}</span>
                </button>
              );
            })}
          </div>

          {/* Amount */}
          <div className="flex items-center gap-1">
            <button onClick={() => setAmount(a => Math.max(1, a - 1))}
              className="w-6 h-6 rounded bg-ocean-700 text-white hover:bg-ocean-600 text-sm">−</button>
            <span className="w-8 text-center text-sm font-mono text-white">{amount}</span>
            <button onClick={() => setAmount(a => Math.min(Number(available), a + 1))}
              className="w-6 h-6 rounded bg-ocean-700 text-white hover:bg-ocean-600 text-sm">+</button>
          </div>

          <button
            onClick={handleReinforce}
            disabled={loading || available < BigInt(amount)}
            className="px-3 py-1.5 rounded-lg bg-northlands text-white text-sm font-medium
              hover:bg-northlands/80 disabled:opacity-40 transition-colors"
          >
            {loading ? 'Reinforcing…' : 'Deploy'}
          </button>
        </>
      )}

      <button
        onClick={onBeginAttack}
        className="ml-auto px-4 py-1.5 rounded-lg bg-gold-500 text-ocean-950 text-sm font-display font-semibold
          hover:bg-gold-400 transition-colors shadow"
      >
        Attack Phase →
      </button>
    </div>
  );
}

// ── Attack Controls ────────────────────────────────────────────────────────────

export interface AttackControlsProps {
  attackStep: AttackStep;
  attackFrom: number | null;
  attackingArmies: number;
  maxDice: number;
  isVRFPending: boolean;
  onSetArmies: (n: number) => void;
  onBeginFortify: () => void;
}

function AttackControls({
  attackStep, attackFrom, attackingArmies, maxDice,
  isVRFPending, onSetArmies, onBeginFortify,
}: AttackControlsProps) {
  return (
    <div className="flex items-center gap-3 flex-wrap">
      {attackStep === 'idle' && (
        <p className="text-xs text-slate-500">
          Select one of your territories to attack from
        </p>
      )}
      {attackStep === 'selectFrom' && attackFrom !== null && (
        <p className="text-xs text-slate-400">
          Now select an adjacent enemy territory to attack
        </p>
      )}
      {(attackStep === 'selectTo' || attackStep === 'confirmDice') && (
        <div className="flex items-center gap-2">
          <span className="text-xs text-slate-400">Dice (1–{maxDice}):</span>
          <div className="flex gap-1">
            {Array.from({ length: maxDice }, (_, i) => i + 1).map(n => (
              <button
                key={n}
                onClick={() => onSetArmies(n)}
                className={cn(
                  'w-8 h-8 rounded-lg border text-sm font-mono font-bold transition-colors',
                  attackingArmies === n
                    ? 'bg-danger border-danger text-white'
                    : 'border-white/15 text-slate-400 hover:border-danger/50'
                )}
              >
                {n}
              </button>
            ))}
          </div>
        </div>
      )}

      {isVRFPending && (
        <div className="flex items-center gap-2 text-xs text-slate-400">
          <motion.div
            animate={{ rotate: 360 }}
            transition={{ duration: 1.5, repeat: Infinity, ease: 'linear' }}
            className="w-3.5 h-3.5 border-2 border-danger/30 border-t-danger rounded-full"
          />
          Awaiting Chainlink VRF…
        </div>
      )}

      <button
        onClick={onBeginFortify}
        className="ml-auto px-4 py-1.5 rounded-lg bg-ocean-700 text-white text-sm font-display font-semibold
          hover:bg-ocean-600 border border-white/10 transition-colors"
      >
        Fortify Phase →
      </button>
    </div>
  );
}

// ── Fortify Controls ──────────────────────────────────────────────────────────

export interface FortifyControlsProps {
  selectedTerritory: number | null;
  onFortify: (from: number, to: number, unitType: number, amount: number) => Promise<void>;
  onEndTurn: () => void;
  fortifyFrom: number | null;
  onSetFortifyFrom: (id: number | null) => void;
}

function FortifyControls({ selectedTerritory, onFortify, onEndTurn, fortifyFrom, onSetFortifyFrom }: FortifyControlsProps) {
  const [amount, setAmount] = useState(1);
  const [loading, setLoading] = useState(false);

  async function handleFortify() {
    if (!fortifyFrom || !selectedTerritory || fortifyFrom === selectedTerritory) return;
    setLoading(true);
    try { await onFortify(fortifyFrom, selectedTerritory, 1, amount); }
    finally { setLoading(false); }
  }

  return (
    <div className="flex items-center gap-3 flex-wrap">
      <p className="text-xs text-slate-400">
        {!fortifyFrom
          ? 'Select the territory to move armies FROM'
          : !selectedTerritory || selectedTerritory === fortifyFrom
            ? 'Now select the adjacent territory to move armies TO'
            : `Moving ${amount} armies from #${fortifyFrom} to #${selectedTerritory}`}
      </p>

      {fortifyFrom && selectedTerritory && selectedTerritory !== fortifyFrom && (
        <>
          <div className="flex items-center gap-1">
            <button onClick={() => setAmount(a => Math.max(1, a - 1))}
              className="w-6 h-6 rounded bg-ocean-700 text-white hover:bg-ocean-600 text-sm">−</button>
            <span className="w-8 text-center text-sm font-mono text-white">{amount}</span>
            <button onClick={() => setAmount(a => a + 1)}
              className="w-6 h-6 rounded bg-ocean-700 text-white hover:bg-ocean-600 text-sm">+</button>
          </div>
          <button onClick={handleFortify} disabled={loading}
            className="px-3 py-1.5 rounded-lg bg-verdant text-white text-sm hover:opacity-80 disabled:opacity-40 transition-opacity">
            {loading ? 'Moving…' : 'Move Armies'}
          </button>
        </>
      )}

      <button
        onClick={onEndTurn}
        className="ml-auto px-4 py-1.5 rounded-lg bg-gold-500 text-ocean-950 text-sm font-display font-semibold
          hover:bg-gold-400 transition-colors shadow"
      >
        End Turn ✓
      </button>
    </div>
  );
}

// ── Master TurnControls Component ──────────────────────────────────────────────

export interface TurnControlsProps {
  isTurnActive: boolean;
  currentPhase: TurnPhase;
  attackStep: AttackStep;
  attackFrom: number | null;
  attackingArmies: number;
  maxDice: number;
  isVRFPending: boolean;
  selectedTerritory: number | null;
  armyBalances: bigint[];
  fortifyFrom: number | null;
  onReinforce: (territoryId: number, unitType: number, amount: number) => Promise<void>;
  onBeginAttack: () => void;
  onSetArmies: (n: number) => void;
  onBeginFortify: () => void;
  onFortify: (from: number, to: number, unitType: number, amount: number) => Promise<void>;
  onEndTurn: () => void;
  onSetFortifyFrom: (id: number | null) => void;
  className?: string;
}

export function TurnControls(props: TurnControlsProps) {
  if (!props.isTurnActive) {
    return (
      <div className={cn(
        'flex items-center justify-center rounded-xl border border-white/5 bg-ocean-900/80 px-4 py-3',
        props.className,
      )}>
        <p className="text-sm text-slate-500">Start your turn to play</p>
      </div>
    );
  }

  return (
    <div className={cn(
      'flex flex-col gap-2 rounded-xl border border-white/10 bg-ocean-900/95 px-4 py-3 backdrop-blur',
      props.className,
    )}>
      <PhaseBar currentPhase={props.currentPhase} isTurnActive={props.isTurnActive} />
      <div className="border-t border-white/5 pt-2">
        <AnimatePresence mode="wait">
          {props.currentPhase === 0 && (
            <motion.div key="reinforce"
              initial={{ opacity: 0, y: 4 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -4 }}
              transition={{ duration: 0.2 }}
            >
              <ReinforceControls
                selectedTerritory={props.selectedTerritory}
                armyBalances={props.armyBalances}
                onReinforce={props.onReinforce}
                onBeginAttack={props.onBeginAttack}
              />
            </motion.div>
          )}
          {props.currentPhase === 1 && (
            <motion.div key="attack"
              initial={{ opacity: 0, y: 4 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -4 }}
              transition={{ duration: 0.2 }}
            >
              <AttackControls
                attackStep={props.attackStep}
                attackFrom={props.attackFrom}
                attackingArmies={props.attackingArmies}
                maxDice={props.maxDice}
                isVRFPending={props.isVRFPending}
                onSetArmies={props.onSetArmies}
                onBeginFortify={props.onBeginFortify}
              />
            </motion.div>
          )}
          {props.currentPhase === 2 && (
            <motion.div key="fortify"
              initial={{ opacity: 0, y: 4 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -4 }}
              transition={{ duration: 0.2 }}
            >
              <FortifyControls
                selectedTerritory={props.selectedTerritory}
                onFortify={props.onFortify}
                onEndTurn={props.onEndTurn}
                fortifyFrom={props.fortifyFrom}
                onSetFortifyFrom={props.onSetFortifyFrom}
              />
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}
