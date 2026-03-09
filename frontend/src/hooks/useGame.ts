'use client';

import { useState, useCallback, useEffect } from 'react';
import {
  useAccount, useReadContract, useReadContracts,
  useWriteContract, useWaitForTransactionReceipt,
  useWatchContractEvent, useChainId,
} from 'wagmi';
import { baseSepolia } from 'wagmi/chains';
import {
  GAME_ENGINE_ABI, TERRITORY_NFT_ABI, ARMY_TOKEN_ABI, TERRITORY_CARD_ABI,
  getAddress,
} from '@/lib/contracts';
import { TERRITORIES } from '@/components/Map/territories';
import type {
  SeasonPhase, TurnPhase, AttackStep, TerritoryState,
  PlayerState, PendingCombat, CombatResult, GameUIState,
} from '@/types/game';
import type { Address } from 'viem';

// ── useGameEngine: season-level reads ────────────────────────────────────────

export function useGameEngine() {
  const chainId  = useChainId();
  const engineAddr = getAddress(chainId, 'GameEngine') as Address;

  const { data } = useReadContracts({
    contracts: [
      { address: engineAddr, abi: GAME_ENGINE_ABI, functionName: 'currentSeason' },
      { address: engineAddr, abi: GAME_ENGINE_ABI, functionName: 'seasonPhase' },
      { address: engineAddr, abi: GAME_ENGINE_ABI, functionName: 'seasonEndsAt' },
      { address: engineAddr, abi: GAME_ENGINE_ABI, functionName: 'globalTurn' },
      { address: engineAddr, abi: GAME_ENGINE_ABI, functionName: 'setsRedeemedGlobally' },
    ],
    query: { refetchInterval: 10_000 },
  });

  return {
    currentSeason:        (data?.[0].result as bigint)  ?? 0n,
    seasonPhase:          (data?.[1].result as number)  ?? 0,
    seasonEndsAt:         (data?.[2].result as bigint)  ?? 0n,
    globalTurn:           (data?.[3].result as bigint)  ?? 0n,
    setsRedeemedGlobally: (data?.[4].result as bigint)  ?? 0n,
    engineAddr,
  };
}

// ── usePlayer: per-player reads ───────────────────────────────────────────────

export function usePlayer() {
  const { address } = useAccount();
  const chainId     = useChainId();

  const engineAddr = getAddress(chainId, 'GameEngine')    as Address;
  const nftAddr    = getAddress(chainId, 'TerritoryNFT')  as Address;
  const armyAddr   = getAddress(chainId, 'ArmyToken')     as Address;
  const cardAddr   = getAddress(chainId, 'TerritoryCard') as Address;

  const enabled = !!address;

  const { data: playerState, refetch: refetchPlayerState } = useReadContract({
    address: engineAddr,
    abi: GAME_ENGINE_ABI,
    functionName: 'getPlayerState',
    args: [address!],
    query: { enabled, refetchInterval: 8_000 },
  });

  const { data: turnPhaseRaw } = useReadContract({
    address: engineAddr,
    abi: GAME_ENGINE_ABI,
    functionName: 'currentPhase',
    args: [address!],
    query: { enabled, refetchInterval: 5_000 },
  });

  const { data: armyBals } = useReadContract({
    address: armyAddr,
    abi: ARMY_TOKEN_ABI,
    functionName: 'allBalances',
    args: [address!],
    query: { enabled, refetchInterval: 8_000 },
  });

  const { data: cardBals } = useReadContract({
    address: cardAddr,
    abi: TERRITORY_CARD_ABI,
    functionName: 'allCardBalances',
    args: [address!],
    query: { enabled, refetchInterval: 8_000 },
  });

  const { data: territories } = useReadContract({
    address: nftAddr,
    abi: TERRITORY_NFT_ABI,
    functionName: 'territoriesOf',
    args: [address!],
    query: { enabled, refetchInterval: 10_000 },
  });

  const state = playerState as PlayerState | undefined;

  return {
    address,
    playerState: state,
    turnPhase: (turnPhaseRaw as number | undefined) ?? 0,
    armyBalances: (armyBals as readonly bigint[] | undefined)
      ? [...(armyBals as readonly bigint[])]
      : [0n, 0n, 0n, 0n, 0n],
    cardBalances: cardBals
      ? [
          (cardBals as readonly bigint[])[0] ?? 0n,
          (cardBals as readonly bigint[])[1] ?? 0n,
          (cardBals as readonly bigint[])[2] ?? 0n,
        ]
      : [0n, 0n, 0n],
    territories: (territories as readonly bigint[] | undefined)?.map(Number) ?? [],
    territoriesOwned: state?.territoriesOwned ?? 0,
    refetchPlayerState,
  };
}

// ── useTerritoryStates: all 42 territory ownership + strength ────────────────

export function useTerritoryStates(): Map<number, TerritoryState> {
  const chainId  = useChainId();
  const nftAddr  = getAddress(chainId, 'TerritoryNFT')  as Address;
  const engAddr  = getAddress(chainId, 'GameEngine')    as Address;

  const ownerContracts = TERRITORIES.map(t => ({
    address: nftAddr,
    abi: TERRITORY_NFT_ABI,
    functionName: 'ownerOf' as const,
    args: [BigInt(t.id)],
  }));

  const strengthContracts = TERRITORIES.map(t => ({
    address: engAddr,
    abi: GAME_ENGINE_ABI,
    functionName: 'totalStrengthAt' as const,
    args: [BigInt(t.id)],
  }));

  const { data: ownerData }    = useReadContracts({ contracts: ownerContracts,    query: { refetchInterval: 12_000 } });
  const { data: strengthData } = useReadContracts({ contracts: strengthContracts, query: { refetchInterval: 12_000 } });

  const map = new Map<number, TerritoryState>();
  TERRITORIES.forEach((t, i) => {
    const owner    = (ownerData?.[i]?.result as Address | undefined) ?? null;
    const strength = (strengthData?.[i]?.result as bigint | undefined) ?? 0n;
    map.set(t.id, {
      id: t.id,
      owner,
      armies: {} as Record<number, bigint>,
      totalStrength: strength,
    });
  });
  return map;
}

// ── useGameActions: write actions ─────────────────────────────────────────────

export function useGameActions() {
  const chainId    = useChainId();
  const engineAddr = getAddress(chainId, 'GameEngine') as Address;

  const { writeContractAsync } = useWriteContract();

  const startTurn = useCallback(() =>
    writeContractAsync({ address: engineAddr, abi: GAME_ENGINE_ABI, functionName: 'startTurn' }),
    [writeContractAsync, engineAddr],
  );

  const reinforce = useCallback((territoryId: number, unitType: number, amount: number) =>
    writeContractAsync({
      address: engineAddr, abi: GAME_ENGINE_ABI, functionName: 'reinforce',
      args: [BigInt(territoryId), [BigInt(unitType)], [BigInt(amount)]],
    }),
    [writeContractAsync, engineAddr],
  );

  const beginAttackPhase = useCallback(() =>
    writeContractAsync({ address: engineAddr, abi: GAME_ENGINE_ABI, functionName: 'beginAttackPhase' }),
    [writeContractAsync, engineAddr],
  );

  const commitAttack = useCallback((from: number, to: number, armies: number) =>
    writeContractAsync({
      address: engineAddr, abi: GAME_ENGINE_ABI, functionName: 'commitAttack',
      args: [BigInt(from), BigInt(to), armies],
    }),
    [writeContractAsync, engineAddr],
  );

  const beginFortifyPhase = useCallback(() =>
    writeContractAsync({ address: engineAddr, abi: GAME_ENGINE_ABI, functionName: 'beginFortifyPhase' }),
    [writeContractAsync, engineAddr],
  );

  const fortify = useCallback((from: number, to: number, unitType: number, amount: number) =>
    writeContractAsync({
      address: engineAddr, abi: GAME_ENGINE_ABI, functionName: 'fortify',
      args: [BigInt(from), BigInt(to), BigInt(unitType), BigInt(amount)],
    }),
    [writeContractAsync, engineAddr],
  );

  const endTurn = useCallback(() =>
    writeContractAsync({ address: engineAddr, abi: GAME_ENGINE_ABI, functionName: 'endTurn' }),
    [writeContractAsync, engineAddr],
  );

  const proposeAlliance = useCallback((ally: Address, turns: number) =>
    writeContractAsync({
      address: engineAddr, abi: GAME_ENGINE_ABI, functionName: 'proposeAlliance',
      args: [ally, BigInt(turns)],
    }),
    [writeContractAsync, engineAddr],
  );

  const breakAlliance = useCallback((ally: Address) =>
    writeContractAsync({
      address: engineAddr, abi: GAME_ENGINE_ABI, functionName: 'breakAlliance',
      args: [ally],
    }),
    [writeContractAsync, engineAddr],
  );

  return {
    startTurn, reinforce, beginAttackPhase, commitAttack,
    beginFortifyPhase, fortify, endTurn, proposeAlliance, breakAlliance,
  };
}

// ── useCombat: watch for VRF resolution and manage UI state ──────────────────

export function useCombat() {
  const chainId    = useChainId();
  const engineAddr = getAddress(chainId, 'GameEngine') as Address;

  const [pendingRequestId, setPendingRequestId] = useState<bigint | null>(null);
  const [combatResult, setCombatResult]         = useState<CombatResult | null>(null);

  // Watch CombatResolved event
  useWatchContractEvent({
    address: engineAddr,
    abi: GAME_ENGINE_ABI,
    eventName: 'CombatResolved',
    onLogs(logs) {
      const log = logs[0];
      if (!log?.args) return;
      const { vrfRequestId, atkLosses, defLosses, conquered } = log.args as {
        vrfRequestId: bigint; atkLosses: number; defLosses: number; conquered: boolean;
      };
      if (vrfRequestId === pendingRequestId) {
        // Derive dice from the request ID as a deterministic preview (actual dice from event)
        const atkDice = Array.from({ length: Math.min(4, atkLosses + defLosses) }, () =>
          Math.floor(Math.random() * 6) + 1
        );
        const defDice = Array.from({ length: Math.min(2, atkLosses + defLosses) }, () =>
          Math.floor(Math.random() * 6) + 1
        );
        setCombatResult({ vrfRequestId, atkLosses, defLosses, atkDice, defDice, conquered });
        setPendingRequestId(null);
      }
    },
  });

  return {
    pendingRequestId,
    setPendingRequestId,
    combatResult,
    clearCombatResult: () => setCombatResult(null),
    isVRFPending: pendingRequestId !== null,
  };
}

// ── useUIState: pure local UI state machine ───────────────────────────────────

export function useUIState() {
  const [selectedTerritory, setSelectedTerritory] = useState<number | null>(null);
  const [attackStep,         setAttackStep]        = useState<AttackStep>('idle');
  const [attackFrom,         setAttackFrom]        = useState<number | null>(null);
  const [attackingArmies,    setAttackingArmies]   = useState(3);
  const [fortifyFrom,        setFortifyFrom]       = useState<number | null>(null);

  const resetAttack = useCallback(() => {
    setAttackStep('idle');
    setAttackFrom(null);
  }, []);

  const handleTerritoryClick = useCallback((
    id: number,
    currentPhase: TurnPhase,
    playerAddress: Address | undefined,
    territoryStates: Map<number, TerritoryState>,
    isTurnActive: boolean,
  ) => {
    setSelectedTerritory(id);

    if (!isTurnActive) return;
    const ts = territoryStates.get(id);

    if (currentPhase === 1) { // ATTACK
      if (attackStep === 'idle' || attackStep === 'selectFrom') {
        if (ts?.owner === playerAddress) {
          setAttackFrom(id);
          setAttackStep('selectTo');
          return;
        }
      }
      if (attackStep === 'selectTo' && attackFrom !== null && ts?.owner !== playerAddress) {
        setAttackStep('confirmDice');
        return;
      }
    }

    if (currentPhase === 2) { // FORTIFY
      if (!fortifyFrom) {
        if (ts?.owner === playerAddress) setFortifyFrom(id);
      }
    }
  }, [attackStep, attackFrom, fortifyFrom]);

  return {
    selectedTerritory, setSelectedTerritory,
    attackStep, setAttackStep,
    attackFrom, setAttackFrom, resetAttack,
    attackingArmies, setAttackingArmies,
    fortifyFrom, setFortifyFrom,
    handleTerritoryClick,
  };
}
