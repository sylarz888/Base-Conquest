import { base, baseSepolia } from 'wagmi/chains';
import type { Address } from 'viem';

// ── Deployment Addresses ──────────────────────────────────────────────────────

const ADDRESSES: Record<number, Record<string, Address>> = {
  [base.id]: {
    TerritoryNFT:  '0x0000000000000000000000000000000000000000',
    ArmyToken:     '0x0000000000000000000000000000000000000000',
    TerritoryCard: '0x0000000000000000000000000000000000000000',
    GameEngine:    '0x0000000000000000000000000000000000000000',
    TreasuryVault: '0x0000000000000000000000000000000000000000',
  },
  [baseSepolia.id]: {
    TerritoryNFT:  '0x0000000000000000000000000000000000000000',
    ArmyToken:     '0x0000000000000000000000000000000000000000',
    TerritoryCard: '0x0000000000000000000000000000000000000000',
    GameEngine:    '0x0000000000000000000000000000000000000000',
    TreasuryVault: '0x0000000000000000000000000000000000000000',
  },
};

export function getAddress(chainId: number, contract: string): Address {
  return ADDRESSES[chainId]?.[contract] ?? '0x0000000000000000000000000000000000000000';
}

// ── ABIs ──────────────────────────────────────────────────────────────────────

export const GAME_ENGINE_ABI = [
  // ── View Functions ──────────────────────────────────────────────────────────
  {
    type: 'function', name: 'currentSeason',
    inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'seasonPhase',
    inputs: [], outputs: [{ type: 'uint8' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'seasonEndsAt',
    inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'globalTurn',
    inputs: [], outputs: [{ type: 'uint64' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'setsRedeemedGlobally',
    inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'armiesAt',
    inputs: [{ name: 'territoryId', type: 'uint256' }, { name: 'unitType', type: 'uint256' }],
    outputs: [{ type: 'uint256' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'totalStrengthAt',
    inputs: [{ name: 'territoryId', type: 'uint256' }],
    outputs: [{ type: 'uint256' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'getPlayerState',
    inputs: [{ name: 'player', type: 'address' }],
    outputs: [{
      type: 'tuple',
      components: [
        { name: 'territoriesOwned',           type: 'uint32' },
        { name: 'lastTurnTaken',              type: 'uint64' },
        { name: 'missedTurns',               type: 'uint8'  },
        { name: 'inactive',                  type: 'bool'   },
        { name: 'attackPenaltyUntilTurn',    type: 'uint64' },
        { name: 'betrayalCooldownUntilTurn', type: 'uint64' },
      ],
    }],
    stateMutability: 'view',
  },
  {
    type: 'function', name: 'currentPhase',
    inputs: [{ name: 'player', type: 'address' }],
    outputs: [{ type: 'uint8' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'hasActiveNAP',
    inputs: [{ name: 'player1', type: 'address' }, { name: 'player2', type: 'address' }],
    outputs: [{ type: 'bool' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'getPendingCombat',
    inputs: [{ name: 'vrfRequestId', type: 'uint256' }],
    outputs: [{
      type: 'tuple',
      components: [
        { name: 'vrfRequestId',    type: 'uint256' },
        { name: 'attacker',        type: 'address' },
        { name: 'fromTerritory',   type: 'uint256' },
        { name: 'toTerritory',     type: 'uint256' },
        { name: 'attackingArmies', type: 'uint8'   },
        { name: 'committedAt',     type: 'uint48'  },
        { name: 'resolved',        type: 'bool'    },
      ],
    }],
    stateMutability: 'view',
  },
  {
    type: 'function', name: 'getAlliance',
    inputs: [{ name: 'player1', type: 'address' }, { name: 'player2', type: 'address' }],
    outputs: [{
      type: 'tuple',
      components: [
        { name: 'player1',       type: 'address' },
        { name: 'player2',       type: 'address' },
        { name: 'expiresAtTurn', type: 'uint64'  },
        { name: 'active',        type: 'bool'    },
      ],
    }],
    stateMutability: 'view',
  },
  {
    type: 'function', name: 'areAdjacent',
    inputs: [{ name: 'fromTerritory', type: 'uint256' }, { name: 'toTerritory', type: 'uint256' }],
    outputs: [{ type: 'bool' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'cardSetBonus',
    inputs: [{ name: 'setsRedeemedGlobally', type: 'uint256' }],
    outputs: [{ type: 'uint256' }], stateMutability: 'pure',
  },
  // ── Write Functions ─────────────────────────────────────────────────────────
  {
    type: 'function', name: 'startTurn',
    inputs: [], outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'reinforce',
    inputs: [
      { name: 'territoryId', type: 'uint256' },
      { name: 'unitTypes',   type: 'uint256[]' },
      { name: 'amounts',     type: 'uint256[]' },
    ],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'redeemCards',
    inputs: [
      { name: 'cardTypes',       type: 'uint8[3]'   },
      { name: 'cardIds',         type: 'uint256[3]' },
      { name: 'bonusTerritoryId', type: 'uint256'   },
    ],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'beginAttackPhase',
    inputs: [], outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'commitAttack',
    inputs: [
      { name: 'fromTerritory',   type: 'uint256' },
      { name: 'toTerritory',     type: 'uint256' },
      { name: 'attackingArmies', type: 'uint8'   },
    ],
    outputs: [{ name: 'vrfRequestId', type: 'uint256' }],
    stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'cancelExpiredAttack',
    inputs: [{ name: 'vrfRequestId', type: 'uint256' }],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'beginFortifyPhase',
    inputs: [], outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'fortify',
    inputs: [
      { name: 'fromTerritory', type: 'uint256' },
      { name: 'toTerritory',   type: 'uint256' },
      { name: 'unitType',      type: 'uint256' },
      { name: 'amount',        type: 'uint256' },
    ],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'endTurn',
    inputs: [], outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'proposeAlliance',
    inputs: [
      { name: 'ally',             type: 'address' },
      { name: 'durationInTurns',  type: 'uint64'  },
    ],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'acceptAlliance',
    inputs: [{ name: 'proposer', type: 'address' }],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'breakAlliance',
    inputs: [{ name: 'ally', type: 'address' }],
    outputs: [], stateMutability: 'nonpayable',
  },
  {
    type: 'function', name: 'settleTimerVictory',
    inputs: [], outputs: [], stateMutability: 'nonpayable',
  },
  // ── Events ──────────────────────────────────────────────────────────────────
  {
    type: 'event', name: 'TurnStarted',
    inputs: [
      { name: 'player',   type: 'address', indexed: true  },
      { name: 'seasonId', type: 'uint256', indexed: false },
      { name: 'globalTurn', type: 'uint64', indexed: false },
    ],
  },
  {
    type: 'event', name: 'AttackCommitted',
    inputs: [
      { name: 'attacker',        type: 'address', indexed: true  },
      { name: 'fromTerritory',   type: 'uint256', indexed: true  },
      { name: 'toTerritory',     type: 'uint256', indexed: true  },
      { name: 'attackingArmies', type: 'uint8',   indexed: false },
      { name: 'vrfRequestId',    type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event', name: 'CombatResolved',
    inputs: [
      { name: 'vrfRequestId', type: 'uint256', indexed: true  },
      { name: 'atkLosses',    type: 'uint8',   indexed: false },
      { name: 'defLosses',    type: 'uint8',   indexed: false },
      { name: 'conquered',    type: 'bool',    indexed: false },
    ],
  },
  {
    type: 'event', name: 'TerritoryConquered',
    inputs: [
      { name: 'territoryId', type: 'uint256', indexed: true  },
      { name: 'attacker',    type: 'address', indexed: true  },
      { name: 'defender',    type: 'address', indexed: true  },
      { name: 'advancing',   type: 'uint256', indexed: false },
    ],
  },
  {
    type: 'event', name: 'TurnEnded',
    inputs: [
      { name: 'player',     type: 'address', indexed: true  },
      { name: 'globalTurn', type: 'uint64',  indexed: false },
      { name: 'drewCard',   type: 'bool',    indexed: false },
    ],
  },
  {
    type: 'event', name: 'AllianceFormed',
    inputs: [
      { name: 'key',           type: 'bytes32', indexed: true  },
      { name: 'player1',       type: 'address', indexed: true  },
      { name: 'player2',       type: 'address', indexed: true  },
      { name: 'expiresAtTurn', type: 'uint64',  indexed: false },
    ],
  },
] as const;

export const TERRITORY_NFT_ABI = [
  {
    type: 'function', name: 'ownerOf',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ type: 'address' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'territoriesOwnedBy',
    inputs: [{ name: 'owner', type: 'address' }],
    outputs: [{ type: 'uint256' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'territoriesOf',
    inputs: [{ name: 'owner', type: 'address' }],
    outputs: [{ type: 'uint256[]' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'controlsContinent',
    inputs: [{ name: 'owner', type: 'address' }, { name: 'continentId', type: 'uint8' }],
    outputs: [{ type: 'bool' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'isLocked',
    inputs: [], outputs: [{ type: 'bool' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'canTransfer',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ type: 'bool' }], stateMutability: 'view',
  },
] as const;

export const ARMY_TOKEN_ABI = [
  {
    type: 'function', name: 'balanceOf',
    inputs: [{ name: 'account', type: 'address' }, { name: 'id', type: 'uint256' }],
    outputs: [{ type: 'uint256' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'allBalances',
    inputs: [{ name: 'player', type: 'address' }],
    outputs: [{ name: 'bals', type: 'uint256[5]' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'totalStrength',
    inputs: [{ name: 'player', type: 'address' }],
    outputs: [{ type: 'uint256' }], stateMutability: 'view',
  },
] as const;

export const TERRITORY_CARD_ABI = [
  {
    type: 'function', name: 'allCardBalances',
    inputs: [{ name: 'player', type: 'address' }],
    outputs: [
      { name: 'infantry',  type: 'uint256' },
      { name: 'cavalry',   type: 'uint256' },
      { name: 'artillery', type: 'uint256' },
    ],
    stateMutability: 'view',
  },
  {
    type: 'function', name: 'setsRedeemedCount',
    inputs: [], outputs: [{ type: 'uint256' }], stateMutability: 'view',
  },
  {
    type: 'function', name: 'previewSetBonus',
    inputs: [
      { name: 'setsAlreadyRedeemed', type: 'uint256' },
      { name: 'cardTypes',           type: 'uint8[3]' },
    ],
    outputs: [{ type: 'uint256' }], stateMutability: 'pure',
  },
] as const;
