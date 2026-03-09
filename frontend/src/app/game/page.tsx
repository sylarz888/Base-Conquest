'use client';

import { useCallback, useState } from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { toast } from 'sonner';
import Link from 'next/link';

import { GameMap }     from '@/components/Map/GameMap';
import { PlayerPanel } from '@/components/HUD/PlayerPanel';
import { TurnControls } from '@/components/HUD/TurnControls';
import { DiceRoll }    from '@/components/Combat/DiceRoll';

import {
  useGameEngine, usePlayer, useTerritoryStates,
  useGameActions, useCombat, useUIState,
} from '@/hooks/useGame';
import { countdown } from '@/lib/utils';
import { CONTINENTS } from '@/components/Map/territories';
import type { TerritoryState, TurnPhase } from '@/types/game';

// ── Season Header Bar ─────────────────────────────────────────────────────────

function SeasonBar({
  season, phase, endsAt, globalTurn,
}: { season: bigint; phase: number; endsAt: bigint; globalTurn: bigint }) {
  const PHASE_LABELS = ['Inactive', 'Auction', 'Active ⚡', 'Ended'];
  const isActive = phase === 2;

  return (
    <div className="flex items-center justify-between px-4 py-2 bg-ocean-900/90 border-b border-white/5 text-xs">
      <div className="flex items-center gap-4">
        <span className="font-display text-gold-400 font-semibold">Base-Conquest</span>
        <span className="text-slate-500">Season {season.toString()}</span>
        <span className={`px-1.5 py-0.5 rounded text-xs font-mono ${isActive ? 'bg-verdant/15 text-verdant' : 'bg-ocean-800 text-slate-400'}`}>
          {PHASE_LABELS[phase] ?? 'Unknown'}
        </span>
        <span className="text-slate-600 hidden sm:inline">Turn {globalTurn.toString()}</span>
      </div>
      <div className="flex items-center gap-3">
        {isActive && endsAt > 0n && (
          <span className="text-slate-500 hidden md:inline">
            ⏳ {countdown(Number(endsAt))} remaining
          </span>
        )}
        <Link href="/" className="text-slate-500 hover:text-white transition-colors">← Home</Link>
        <ConnectButton
          showBalance={false}
          chainStatus="icon"
          accountStatus="avatar"
        />
      </div>
    </div>
  );
}

// ── Continent Control Sidebar Row ─────────────────────────────────────────────

function ContinentStatus({ territoryStates, playerAddress }: {
  territoryStates: Map<number, TerritoryState>;
  playerAddress: string | undefined;
}) {
  return (
    <div className="rounded-xl border border-white/5 bg-ocean-900/80 p-3">
      <p className="text-xs text-slate-500 uppercase tracking-wide mb-2">Continent Control</p>
      <div className="space-y-1">
        {Object.values(CONTINENTS).map(c => {
          const ids = Array.from({ length: c.id === 1 ? 9 : c.id === 2 ? 7 : c.id === 3 ? 6 : c.id === 4 ? 12 : 4 }, (_, i) => {
            const offsets = [1, 10, 17, 23, 35, 39];
            return offsets[c.id - 1] + i;
          });
          const owners = ids.map(id => territoryStates.get(id)?.owner).filter(Boolean);
          const dominated = owners.length === ids.length && owners.every(o => o === owners[0]);
          const youControl = dominated && owners[0]?.toLowerCase() === playerAddress?.toLowerCase();
          const pct = Math.round((owners.length / ids.length) * 100);

          return (
            <div key={c.id} className="flex items-center gap-2 text-xs">
              <div className="w-2 h-2 rounded-full flex-shrink-0" style={{ backgroundColor: c.textColor }} />
              <span className="text-slate-400 truncate flex-1" style={{ maxWidth: 90 }}>{c.name}</span>
              <div className="flex-1 h-1 rounded-full bg-ocean-800 overflow-hidden">
                <div className="h-full rounded-full transition-all"
                  style={{ width: `${pct}%`, backgroundColor: c.textColor + '88' }} />
              </div>
              {youControl && <span className="text-verdant text-xs">✓</span>}
              <span className="font-mono text-slate-600 flex-shrink-0">+{c.bonusArmies}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ── Main Game Board ───────────────────────────────────────────────────────────

export default function GamePage() {
  const engine          = useGameEngine();
  const player          = usePlayer();
  const territoryStates = useTerritoryStates();
  const actions         = useGameActions();
  const combat          = useCombat();
  const ui              = useUIState();

  // Calculate max dice (General in any territory gives +1)
  const maxDice = 3; // TODO: check if player has General on attackFrom territory

  const isTurnActive  = player.turnPhase !== undefined && (player.playerState?.lastTurnTaken ?? 0n) === engine.globalTurn;
  const hasPendingCombat = combat.isVRFPending;

  // Territory click handler
  const handleTerritoryClick = useCallback((id: number) => {
    ui.handleTerritoryClick(
      id,
      player.turnPhase as TurnPhase,
      player.address,
      territoryStates,
      isTurnActive,
    );
  }, [ui, player.turnPhase, player.address, territoryStates, isTurnActive]);

  // Actions with toast feedback
  async function handleStartTurn() {
    try {
      await actions.startTurn();
      toast.success('Turn started! Deploy your armies.');
    } catch (e: unknown) {
      toast.error((e as Error).message?.slice(0, 80) ?? 'Transaction failed');
    }
  }

  async function handleReinforce(territoryId: number, unitType: number, amount: number) {
    try {
      await actions.reinforce(territoryId, unitType, amount);
      toast.success(`Deployed ${amount} armies to territory #${territoryId}`);
    } catch (e: unknown) {
      toast.error((e as Error).message?.slice(0, 80) ?? 'Reinforce failed');
    }
  }

  async function handleBeginAttack() {
    try {
      await actions.beginAttackPhase();
      ui.setAttackStep('selectFrom');
      toast.info('Attack phase — select a territory to attack from');
    } catch (e: unknown) {
      toast.error((e as Error).message?.slice(0, 80) ?? 'Failed');
    }
  }

  async function handleBeginFortify() {
    try {
      await actions.beginFortifyPhase();
      ui.setAttackStep('idle');
      toast.info('Fortify phase — move armies once between adjacent territories');
    } catch (e: unknown) {
      toast.error((e as Error).message?.slice(0, 80) ?? 'Failed');
    }
  }

  async function handleFortify(from: number, to: number, unitType: number, amount: number) {
    try {
      await actions.fortify(from, to, unitType, amount);
      ui.setFortifyFrom(null);
      toast.success(`Moved ${amount} armies from #${from} → #${to}`);
    } catch (e: unknown) {
      toast.error((e as Error).message?.slice(0, 80) ?? 'Fortify failed');
    }
  }

  async function handleEndTurn() {
    try {
      await actions.endTurn();
      ui.resetAttack();
      ui.setFortifyFrom(null);
      ui.setSelectedTerritory(null);
      toast.success('Turn ended. See you in 24 hours!');
    } catch (e: unknown) {
      toast.error((e as Error).message?.slice(0, 80) ?? 'Failed');
    }
  }

  // Attack confirmation
  async function handleCommitAttack() {
    if (!ui.attackFrom || !ui.selectedTerritory) return;
    try {
      const txResult = await actions.commitAttack(ui.attackFrom, ui.selectedTerritory, ui.attackingArmies);
      // Extract VRF request ID from tx receipt (simplified — production would parse logs)
      ui.setAttackStep('pending');
      combat.clearCombatResult();
      toast.loading('VRF request submitted — awaiting Chainlink oracle…', { id: 'vrf' });
    } catch (e: unknown) {
      toast.error((e as Error).message?.slice(0, 80) ?? 'Attack failed');
      ui.resetAttack();
    }
  }

  const continentsControlled = Object.keys(CONTINENTS).filter(cid =>
    Object.values(CONTINENTS).find(c => c.id === Number(cid))
      && player.territories.length > 0
  ).length;

  return (
    <div className="h-screen flex flex-col overflow-hidden bg-ocean-950">
      {/* Top bar */}
      <SeasonBar
        season={engine.currentSeason}
        phase={engine.seasonPhase}
        endsAt={engine.seasonEndsAt}
        globalTurn={engine.globalTurn}
      />

      {/* Main layout: left sidebar | map | right sidebar */}
      <div className="flex flex-1 overflow-hidden">

        {/* Left Sidebar */}
        <aside className="w-60 flex-shrink-0 overflow-y-auto p-3 flex flex-col gap-3 border-r border-white/5">
          <PlayerPanel
            address={player.address}
            territories={player.territoriesOwned}
            continentsControlled={continentsControlled}
            armyBalances={player.armyBalances}
            cardBalances={player.cardBalances}
            turnPhase={['Reinforce', 'Attack', 'Fortify'][player.turnPhase] ?? 'Waiting'}
            globalTurn={engine.globalTurn}
            seasonEndsAt={engine.seasonEndsAt}
            hasPendingCombat={hasPendingCombat}
            isTurnActive={isTurnActive}
            onStartTurn={handleStartTurn}
            onEndTurn={handleEndTurn}
          />

          <ContinentStatus
            territoryStates={territoryStates}
            playerAddress={player.address}
          />
        </aside>

        {/* Map — fills all remaining space */}
        <main className="flex-1 relative overflow-hidden p-3">
          <GameMap
            territoryStates={territoryStates}
            playerAddress={player.address}
            selectedTerritory={ui.selectedTerritory}
            attackStep={ui.attackStep}
            attackFrom={ui.attackFrom}
            onSelectTerritory={handleTerritoryClick}
            className="w-full h-full"
          />

          {/* Bottom controls bar — overlays map */}
          <div className="absolute bottom-3 left-3 right-3">
            <TurnControls
              isTurnActive={isTurnActive}
              currentPhase={player.turnPhase as TurnPhase}
              attackStep={ui.attackStep}
              attackFrom={ui.attackFrom}
              attackingArmies={ui.attackingArmies}
              maxDice={maxDice}
              isVRFPending={hasPendingCombat}
              selectedTerritory={ui.selectedTerritory}
              armyBalances={player.armyBalances}
              fortifyFrom={ui.fortifyFrom}
              onReinforce={handleReinforce}
              onBeginAttack={handleBeginAttack}
              onSetArmies={ui.setAttackingArmies}
              onBeginFortify={handleBeginFortify}
              onFortify={handleFortify}
              onEndTurn={handleEndTurn}
              onSetFortifyFrom={ui.setFortifyFrom}
            />
          </div>
        </main>

        {/* Right Sidebar */}
        <aside className="w-56 flex-shrink-0 overflow-y-auto p-3 flex flex-col gap-3 border-l border-white/5">
          <DiceRoll
            result={combat.combatResult}
            isPending={hasPendingCombat}
            vrfRequestId={combat.pendingRequestId ?? undefined}
          />

          {/* Attack confirmation panel */}
          {ui.attackStep === 'confirmDice' && ui.attackFrom && ui.selectedTerritory && (
            <div className="rounded-xl border border-danger/30 bg-danger/5 p-4">
              <h4 className="font-display text-white text-sm font-semibold mb-3">Confirm Attack</h4>
              <div className="text-xs text-slate-400 space-y-1 mb-4">
                <div className="flex justify-between">
                  <span>From</span>
                  <span className="text-white">Territory #{ui.attackFrom}</span>
                </div>
                <div className="flex justify-between">
                  <span>To</span>
                  <span className="text-danger">Territory #{ui.selectedTerritory}</span>
                </div>
                <div className="flex justify-between">
                  <span>Dice</span>
                  <span className="text-gold-400">{ui.attackingArmies}</span>
                </div>
              </div>
              <button
                onClick={handleCommitAttack}
                className="w-full py-2 rounded-lg bg-danger text-white text-sm font-display font-semibold
                  hover:bg-danger/80 transition-colors shadow-lg shadow-danger/20"
              >
                ⚔ Roll Dice
              </button>
              <button
                onClick={ui.resetAttack}
                className="w-full py-1.5 mt-1 rounded-lg text-slate-500 text-xs hover:text-white transition-colors"
              >
                Cancel
              </button>
            </div>
          )}

          {/* Selected territory info */}
          {ui.selectedTerritory && (
            <div className="rounded-xl border border-white/5 bg-ocean-900/80 p-3 text-xs">
              <p className="text-slate-500 uppercase tracking-wide mb-2 text-xs">Territory #{ui.selectedTerritory}</p>
              {(() => {
                const ts = territoryStates.get(ui.selectedTerritory);
                const owner = ts?.owner;
                return (
                  <div className="space-y-1 text-slate-300">
                    <div className="flex justify-between">
                      <span className="text-slate-500">Owner</span>
                      <span>{owner ? `${owner.slice(0, 6)}…${owner.slice(-4)}` : 'Unowned'}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-500">Strength</span>
                      <span className="font-mono">{ts?.totalStrength?.toString() ?? '0'}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-500">Yours?</span>
                      <span>{owner?.toLowerCase() === player.address?.toLowerCase() ? '✓ Yes' : '✗ No'}</span>
                    </div>
                  </div>
                );
              })()}
            </div>
          )}
        </aside>
      </div>
    </div>
  );
}
