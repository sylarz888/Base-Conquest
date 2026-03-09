'use client';

import { motion, AnimatePresence } from 'framer-motion';
import { cn } from '@/lib/utils';
import type { CombatResult } from '@/types/game';

// ── Single Die ────────────────────────────────────────────────────────────────

const DIE_DOTS: Record<number, [number, number][]> = {
  1: [[50, 50]],
  2: [[25, 25], [75, 75]],
  3: [[25, 25], [50, 50], [75, 75]],
  4: [[25, 25], [75, 25], [25, 75], [75, 75]],
  5: [[25, 25], [75, 25], [50, 50], [25, 75], [75, 75]],
  6: [[25, 20], [75, 20], [25, 50], [75, 50], [25, 80], [75, 80]],
};

function Die({
  value,
  color,
  delay = 0,
  lost = false,
}: {
  value: number;
  color: string;
  delay?: number;
  lost?: boolean;
}) {
  const dots = DIE_DOTS[value] ?? DIE_DOTS[1];

  return (
    <motion.div
      initial={{ rotate: -180, scale: 0, opacity: 0 }}
      animate={{ rotate: 0, scale: 1, opacity: lost ? 0.35 : 1 }}
      transition={{ delay, type: 'spring', stiffness: 300, damping: 20 }}
      className={cn('relative', lost && 'grayscale')}
    >
      <svg width="52" height="52" viewBox="0 0 100 100">
        <rect
          x="4" y="4" width="92" height="92" rx="18"
          fill="#0d1829"
          stroke={color}
          strokeWidth="4"
        />
        {lost && (
          <line x1="10" y1="10" x2="90" y2="90" stroke="#e05252" strokeWidth="4" opacity="0.6" />
        )}
        {dots.map(([dx, dy], i) => (
          <circle key={i} cx={dx} cy={dy} r="8" fill={color} />
        ))}
      </svg>
    </motion.div>
  );
}

// ── Dice Group ────────────────────────────────────────────────────────────────

function DiceGroup({
  dice,
  losses,
  color,
  label,
}: {
  dice: number[];
  losses: number;
  color: string;
  label: string;
}) {
  return (
    <div className="flex flex-col items-center gap-2">
      <span className="text-xs uppercase tracking-widest font-medium" style={{ color }}>
        {label}
      </span>
      <div className="flex gap-2">
        {dice.map((d, i) => (
          <Die key={i} value={d} color={color} delay={i * 0.12} lost={i < losses} />
        ))}
      </div>
      {losses > 0 && (
        <span className="text-xs text-danger font-mono">−{losses} lost</span>
      )}
    </div>
  );
}

// ── Result Banner ─────────────────────────────────────────────────────────────

function ResultBanner({ conquered }: { conquered: boolean }) {
  return (
    <motion.div
      initial={{ scale: 0.5, opacity: 0 }}
      animate={{ scale: 1, opacity: 1 }}
      transition={{ delay: 0.8, type: 'spring', stiffness: 400, damping: 25 }}
      className={cn(
        'text-center py-2 px-4 rounded-xl font-display font-bold text-lg border',
        conquered
          ? 'bg-verdant/15 border-verdant/40 text-verdant'
          : 'bg-danger/10 border-danger/30 text-danger',
      )}
    >
      {conquered ? '⚔ Conquered!' : '🛡 Defended!'}
    </motion.div>
  );
}

// ── Main Component ────────────────────────────────────────────────────────────

export interface DiceRollProps {
  result: CombatResult | null;
  isPending: boolean;
  vrfRequestId?: bigint;
  className?: string;
}

export function DiceRoll({ result, isPending, vrfRequestId, className }: DiceRollProps) {
  return (
    <div className={cn('rounded-xl border border-white/10 bg-ocean-950/90 p-5', className)}>
      <div className="flex items-center justify-between mb-4">
        <h3 className="font-display text-white font-semibold">Combat</h3>
        {vrfRequestId !== undefined && (
          <span className="text-xs font-mono text-slate-600">
            VRF #{vrfRequestId.toString().slice(-6)}
          </span>
        )}
      </div>

      <AnimatePresence mode="wait">
        {isPending && (
          <motion.div
            key="pending"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="flex flex-col items-center gap-4 py-6"
          >
            {/* Dice rolling animation */}
            <div className="flex gap-3">
              {[0, 1, 2].map(i => (
                <motion.div
                  key={i}
                  animate={{ rotate: [0, 180, 360], scale: [1, 0.8, 1] }}
                  transition={{ duration: 0.8, delay: i * 0.2, repeat: Infinity }}
                >
                  <svg width="44" height="44" viewBox="0 0 100 100">
                    <rect x="4" y="4" width="92" height="92" rx="18"
                      fill="#0d1829" stroke="#e05252" strokeWidth="4" />
                    <circle cx="50" cy="50" r="10" fill="#e05252" />
                  </svg>
                </motion.div>
              ))}
            </div>
            <p className="text-xs text-slate-500 text-center">
              Chainlink VRF generating provably-fair randomness…
              <br />
              <span className="text-slate-600">~20 seconds on Base</span>
            </p>
          </motion.div>
        )}

        {result && !isPending && (
          <motion.div
            key="result"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="space-y-4"
          >
            <div className="flex items-center justify-center gap-6">
              <DiceGroup
                dice={result.atkDice}
                losses={result.atkLosses}
                color="#e05252"
                label="Attacker"
              />
              <div className="text-2xl text-slate-600">vs</div>
              <DiceGroup
                dice={result.defDice}
                losses={result.defLosses}
                color="#4a90d9"
                label="Defender"
              />
            </div>
            <ResultBanner conquered={result.conquered} />
          </motion.div>
        )}

        {!result && !isPending && (
          <motion.div
            key="idle"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            className="py-6 text-center text-xs text-slate-600"
          >
            Attack a territory to roll dice
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
