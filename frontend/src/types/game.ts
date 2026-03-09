import type { Address } from 'viem';

// ── Enums matching on-chain IGameEngine ───────────────────────────────────────

export enum SeasonPhase {
  INACTIVE = 0,
  AUCTION  = 1,
  ACTIVE   = 2,
  ENDED    = 3,
}

export enum TurnPhase {
  REINFORCE = 0,
  ATTACK    = 1,
  FORTIFY   = 2,
}

// ── Unit Types ────────────────────────────────────────────────────────────────

export const UNIT_TYPES = {
  INFANTRY:  1,
  CAVALRY:   2,
  ARTILLERY: 3,
  GENERAL:   4,
  ADMIRAL:   5,
} as const;

export type UnitTypeId = (typeof UNIT_TYPES)[keyof typeof UNIT_TYPES];

export interface UnitTypeMeta {
  id: UnitTypeId;
  name: string;
  symbol: string;
  cost: number;       // Infantry equivalent
  maxDice?: number;   // bonus dice contribution
  effect: string;
  color: string;
  bgColor: string;
}

export const UNIT_META: Record<UnitTypeId, UnitTypeMeta> = {
  1: { id: 1, name: 'Infantry',  symbol: '⚔',  cost: 1,  effect: 'Standard unit',                          color: '#94a3b8', bgColor: '#1e293b' },
  2: { id: 2, name: 'Cavalry',   symbol: '🐎', cost: 3,  effect: 'Reroll attacker\'s lowest die',           color: '#f6c84e', bgColor: '#2d2400' },
  3: { id: 3, name: 'Artillery', symbol: '💣', cost: 5,  effect: 'Defender rerolls their lowest die',       color: '#e05252', bgColor: '#2d0a0a' },
  4: { id: 4, name: 'General',   symbol: '⭐', cost: 10, effect: '+1 max attack die (up to 4)',              color: '#c084fc', bgColor: '#1e0d38' },
  5: { id: 5, name: 'Admiral',   symbol: '⚓', cost: 10, effect: 'Enables naval attacks to distant islands', color: '#38bdf8', bgColor: '#0c1a2e' },
};

// ── Card Types ────────────────────────────────────────────────────────────────

export const CARD_TYPES = {
  INFANTRY:  1,
  CAVALRY:   2,
  ARTILLERY: 3,
} as const;

export type CardTypeId = (typeof CARD_TYPES)[keyof typeof CARD_TYPES];

export interface CardSet {
  infantry:  number;
  cavalry:   number;
  artillery: number;
}

// ── Territory & Map ───────────────────────────────────────────────────────────

export interface TerritoryMeta {
  id: number;
  name: string;
  continentId: ContinentId;
  cx: number;          // SVG center X
  cy: number;          // SVG center Y
  adjacentIds: number[];
  navalIds: number[];  // naval connections (Admiral required)
}

export type ContinentId = 1 | 2 | 3 | 4 | 5 | 6;

export interface ContinentMeta {
  id: ContinentId;
  name: string;
  bonusArmies: number;
  color: string;         // fill color for SVG
  borderColor: string;   // stroke color
  textColor: string;
  description: string;
}

// ── On-chain state ────────────────────────────────────────────────────────────

export interface TerritoryState {
  id: number;
  owner: Address | null;
  armies: Record<UnitTypeId, bigint>;  // unitType → count
  totalStrength: bigint;
  isConquering?: boolean;   // VRF pending
}

export interface PlayerState {
  address: Address;
  territoriesOwned: number;
  lastTurnTaken: bigint;    // globalTurn
  missedTurns: number;
  inactive: boolean;
  attackPenaltyUntilTurn: bigint;
  betrayalCooldownUntilTurn: bigint;
}

export interface PendingCombat {
  vrfRequestId: bigint;
  attacker: Address;
  fromTerritory: number;
  toTerritory: number;
  attackingArmies: number;
  committedAt: number;
  resolved: boolean;
}

export interface Alliance {
  player1: Address;
  player2: Address;
  expiresAtTurn: bigint;
  active: boolean;
}

// ── UI State ──────────────────────────────────────────────────────────────────

export type AttackStep = 'idle' | 'selectFrom' | 'selectTo' | 'confirmDice' | 'pending' | 'resolved';

export interface CombatResult {
  vrfRequestId: bigint;
  atkLosses: number;
  defLosses: number;
  atkDice: number[];
  defDice: number[];
  conquered: boolean;
}

export interface GameUIState {
  selectedTerritory: number | null;
  attackStep: AttackStep;
  attackFrom: number | null;
  attackTo: number | null;
  pendingCombat: PendingCombat | null;
  lastCombatResult: CombatResult | null;
  hoveredTerritory: number | null;
  showAllianceModal: boolean;
  showCardsModal: boolean;
}

// ── Leaderboard ───────────────────────────────────────────────────────────────

export interface LeaderboardEntry {
  rank: number;
  address: Address;
  ensName?: string;
  territories: number;
  continents: number;
  totalStrength: bigint;
  isAllied?: boolean;
}
