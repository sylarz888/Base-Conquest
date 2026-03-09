'use client';

import { useRef, useState, useCallback } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { TERRITORIES, CONTINENTS, CONNECTIONS, NAVAL_PAIRS, TERRITORY_MAP } from './territories';
import { hexPoints, playerColor, cn } from '@/lib/utils';
import type { TerritoryState, AttackStep } from '@/types/game';
import type { Address } from 'viem';

// ── Constants ─────────────────────────────────────────────────────────────────

const HEX_R       = 38;   // hexagon radius (flat-top)
const HEX_R_INNER = 35;   // inner ring for border effect
const SVG_W       = 900;
const SVG_H       = 740;

// ── Sub-components ────────────────────────────────────────────────────────────

function OceanBackground() {
  return (
    <>
      <defs>
        <pattern id="ocean-wave" x="0" y="0" width="40" height="40" patternUnits="userSpaceOnUse">
          <path d="M0 20 Q10 15 20 20 Q30 25 40 20" stroke="#1a2e47" strokeWidth="1" fill="none" opacity="0.5" />
          <path d="M0 30 Q10 25 20 30 Q30 35 40 30" stroke="#1a2e47" strokeWidth="0.5" fill="none" opacity="0.3" />
        </pattern>
        <radialGradient id="ocean-glow" cx="50%" cy="50%" r="60%">
          <stop offset="0%"   stopColor="#0d1829" />
          <stop offset="100%" stopColor="#040810" />
        </radialGradient>
        <filter id="hex-shadow" x="-20%" y="-20%" width="140%" height="140%">
          <feDropShadow dx="0" dy="2" stdDeviation="3" floodColor="#000" floodOpacity="0.6" />
        </filter>
        <filter id="glow-filter" x="-30%" y="-30%" width="160%" height="160%">
          <feGaussianBlur stdDeviation="4" result="coloredBlur" />
          <feMerge>
            <feMergeNode in="coloredBlur" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
        <filter id="conquest-glow" x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur stdDeviation="8" result="coloredBlur" />
          <feMerge>
            <feMergeNode in="coloredBlur" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>
      <rect width={SVG_W} height={SVG_H} fill="url(#ocean-glow)" />
      <rect width={SVG_W} height={SVG_H} fill="url(#ocean-wave)" opacity="0.4" />
    </>
  );
}

interface ConnectionLinesProps {
  attackFrom: number | null;
  attackTo: number | null;
  attackStep: AttackStep;
}

function ConnectionLines({ attackFrom, attackTo, attackStep }: ConnectionLinesProps) {
  return (
    <g id="connections">
      {CONNECTIONS.map(([a, b]) => {
        const ta = TERRITORY_MAP.get(a);
        const tb = TERRITORY_MAP.get(b);
        if (!ta || !tb) return null;

        const key = [Math.min(a, b), Math.max(a, b)].join('-');
        const isNaval = NAVAL_PAIRS.has(key);
        const isAttackPath = attackStep !== 'idle' && (
          (a === attackFrom && b === attackTo) ||
          (b === attackFrom && a === attackTo)
        );

        if (isAttackPath) {
          return (
            <motion.line
              key={key}
              x1={ta.cx} y1={ta.cy} x2={tb.cx} y2={tb.cy}
              stroke="#e05252"
              strokeWidth={3}
              strokeDasharray="6 3"
              initial={{ pathLength: 0, opacity: 0 }}
              animate={{ pathLength: 1, opacity: 1 }}
              transition={{ duration: 0.4 }}
            />
          );
        }

        return (
          <line
            key={key}
            x1={ta.cx} y1={ta.cy}
            x2={tb.cx} y2={tb.cy}
            stroke={isNaval ? '#3a5fc4' : '#1a2e47'}
            strokeWidth={isNaval ? 1.5 : 1}
            strokeDasharray={isNaval ? '5 4' : undefined}
            opacity={isNaval ? 0.7 : 0.5}
          />
        );
      })}
    </g>
  );
}

interface HexagonProps {
  territory: TerritoryMeta;
  state: TerritoryState | undefined;
  isSelected: boolean;
  isHovered: boolean;
  isAttackFrom: boolean;
  isAttackTarget: boolean;
  isValidTarget: boolean;
  attackStep: AttackStep;
  onClick: (id: number) => void;
  onHover: (id: number | null) => void;
}

import type { TerritoryMeta } from './territories';

function Hexagon({
  territory, state, isSelected, isHovered,
  isAttackFrom, isAttackTarget, isValidTarget, attackStep,
  onClick, onHover,
}: HexagonProps) {
  const { id, cx, cy, continentId, name } = territory;
  const continent = CONTINENTS[continentId];
  const owner = state?.owner;
  const strength = state?.totalStrength ?? 0n;

  // Color logic
  const fill = owner
    ? playerColor(owner)
    : continent.color;

  const stroke = (() => {
    if (isAttackFrom)   return '#e05252';
    if (isAttackTarget) return '#e05252';
    if (isValidTarget)  return '#f6c84e';
    if (isSelected)     return '#f6c84e';
    if (isHovered)      return '#ffffff';
    return continent.borderColor;
  })();

  const strokeWidth = isSelected || isAttackFrom || isAttackTarget || isValidTarget ? 3 : 1.5;
  const filterAttr  = isAttackFrom || isAttackTarget ? 'url(#glow-filter)' : 'url(#hex-shadow)';

  const outerPts = hexPoints(cx, cy, HEX_R);
  const innerPts = hexPoints(cx, cy, HEX_R_INNER);

  // Army count display
  const armyCount = strength > 0n ? Number(strength) : null;

  const isClickable = attackStep === 'idle' || isAttackFrom || isValidTarget || isAttackTarget;

  return (
    <g
      key={id}
      style={{ cursor: isClickable ? 'pointer' : 'default' }}
      onClick={() => onClick(id)}
      onMouseEnter={() => onHover(id)}
      onMouseLeave={() => onHover(null)}
      filter={filterAttr}
    >
      {/* Outer shadow hex */}
      <polygon
        points={outerPts}
        fill={fill}
        stroke={stroke}
        strokeWidth={strokeWidth}
        opacity={isHovered ? 1 : 0.92}
      />
      {/* Inner darker bevel */}
      <polygon
        points={innerPts}
        fill="none"
        stroke="rgba(0,0,0,0.25)"
        strokeWidth={1}
      />

      {/* Selected / hover pulse ring */}
      <AnimatePresence>
        {(isSelected || isAttackFrom) && (
          <motion.polygon
            key="pulse"
            points={hexPoints(cx, cy, HEX_R + 4)}
            fill="none"
            stroke={isAttackFrom ? '#e05252' : '#f6c84e'}
            strokeWidth={2}
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: [0.8, 0.2, 0.8], scale: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 1.8, repeat: Infinity }}
          />
        )}
      </AnimatePresence>

      {/* Territory name — shown when hovered or selected */}
      {(isHovered || isSelected) && (
        <text
          x={cx}
          y={cy - HEX_R - 6}
          textAnchor="middle"
          fontSize={10}
          fontFamily="serif"
          fill="#f6c84e"
          stroke="#000"
          strokeWidth={3}
          paintOrder="stroke"
        >
          {name}
        </text>
      )}

      {/* Army strength badge */}
      {armyCount !== null && (
        <>
          <circle cx={cx} cy={cy + 2} r={13} fill="rgba(0,0,0,0.65)" stroke="rgba(255,255,255,0.15)" strokeWidth={1} />
          <text
            x={cx}
            y={cy + 7}
            textAnchor="middle"
            fontSize={12}
            fontWeight="bold"
            fontFamily="monospace"
            fill="#fff"
          >
            {armyCount > 99 ? '99+' : armyCount}
          </text>
        </>
      )}

      {/* Territory ID (small, always visible) */}
      {!armyCount && (
        <text
          x={cx}
          y={cy + 4}
          textAnchor="middle"
          fontSize={9}
          fontFamily="monospace"
          fill={continent.textColor}
          opacity={0.6}
        >
          {id}
        </text>
      )}

      {/* Valid attack target marker */}
      {isValidTarget && attackStep === 'selectTo' && (
        <motion.circle
          cx={cx} cy={cy - HEX_R + 12}
          r={5}
          fill="#e05252"
          initial={{ scale: 0 }}
          animate={{ scale: [1, 1.3, 1] }}
          transition={{ duration: 1, repeat: Infinity }}
        />
      )}
    </g>
  );
}

// ── Continent Labels ──────────────────────────────────────────────────────────

function ContinentLabels() {
  const labelPositions: Record<number, { x: number; y: number }> = {
    1: { x: 85,  y: 55  },   // Northlands
    2: { x: 492, y: 118 },   // Merchant Straits
    3: { x: 728, y: 268 },   // Iron Coast
    4: { x: 418, y: 295 },   // The Barrens
    5: { x: 740, y: 475 },   // Verdant Isles
    6: { x: 390, y: 720 },   // Deep Expanse
  };

  return (
    <g id="continent-labels" pointerEvents="none">
      {(Object.entries(CONTINENTS) as [string, ContinentMeta][]).map(([cid, c]) => {
        const pos = labelPositions[Number(cid)];
        if (!pos) return null;
        return (
          <g key={cid}>
            <text
              x={pos.x} y={pos.y}
              textAnchor="middle"
              fontSize={9}
              fontFamily="serif"
              letterSpacing="0.12em"
              fill={c.textColor}
              opacity={0.55}
              style={{ textTransform: 'uppercase' }}
            >
              {c.name.toUpperCase()}
            </text>
            <text
              x={pos.x} y={pos.y + 11}
              textAnchor="middle"
              fontSize={8}
              fontFamily="monospace"
              fill={c.textColor}
              opacity={0.35}
            >
              +{c.bonusArmies} armies
            </text>
          </g>
        );
      })}
    </g>
  );
}

// ── Tooltip ───────────────────────────────────────────────────────────────────

interface TooltipProps {
  territory: TerritoryMeta | undefined;
  state: TerritoryState | undefined;
  attackStep: AttackStep;
}

function Tooltip({ territory, state, attackStep }: TooltipProps) {
  if (!territory) return null;
  const continent = CONTINENTS[territory.continentId];
  const owner = state?.owner;

  let action = '';
  if (attackStep === 'selectFrom' && !owner) action = 'No armies here';
  if (attackStep === 'selectTo')            action = 'Click to attack';

  return (
    <div className="absolute bottom-3 left-1/2 -translate-x-1/2 pointer-events-none z-20
      bg-ocean-800/95 border rounded-lg px-4 py-2 text-sm shadow-xl
      flex items-center gap-3"
      style={{ borderColor: continent.borderColor }}
    >
      <div>
        <div className="font-display text-white font-semibold">{territory.name}</div>
        <div className="text-xs mt-0.5" style={{ color: continent.textColor }}>
          {continent.name}
        </div>
      </div>
      {owner && (
        <div className="text-xs text-slate-400">
          <span className="inline-block w-2 h-2 rounded-full mr-1"
            style={{ backgroundColor: playerColor(owner) }} />
          {owner.slice(0, 6)}…{owner.slice(-4)}
        </div>
      )}
      {state && state.totalStrength > 0n && (
        <div className="text-xs text-slate-300">
          ⚔ {state.totalStrength.toString()} strength
        </div>
      )}
      {action && (
        <div className="text-xs font-medium" style={{ color: '#e05252' }}>{action}</div>
      )}
    </div>
  );
}

// ── Main GameMap Component ────────────────────────────────────────────────────

export interface GameMapProps {
  territoryStates: Map<number, TerritoryState>;
  playerAddress: Address | undefined;
  selectedTerritory: number | null;
  attackStep: AttackStep;
  attackFrom: number | null;
  onSelectTerritory: (id: number) => void;
  className?: string;
}

export function GameMap({
  territoryStates,
  playerAddress,
  selectedTerritory,
  attackStep,
  attackFrom,
  onSelectTerritory,
  className,
}: GameMapProps) {
  const [hoveredId, setHoveredId] = useState<number | null>(null);
  const svgRef = useRef<SVGSVGElement>(null);

  const handleHover = useCallback((id: number | null) => setHoveredId(id), []);

  // Derive which territories are valid attack targets (adjacent to attackFrom,
  // not owned by current player, not in a NAP — handled off-chain for now)
  const validTargets = new Set<number>();
  if (attackStep === 'selectTo' && attackFrom !== null) {
    const from = TERRITORY_MAP.get(attackFrom);
    if (from) {
      [...from.adjacentIds, ...from.navalIds].forEach(id => {
        const ts = territoryStates.get(id);
        if (!ts || ts.owner !== playerAddress) validTargets.add(id);
      });
    }
  }

  const hoveredTerritory = hoveredId ? TERRITORY_MAP.get(hoveredId) : undefined;
  const hoveredState     = hoveredId ? territoryStates.get(hoveredId) : undefined;

  const attackTo = attackStep === 'selectTo'
    ? (hoveredId && validTargets.has(hoveredId) ? hoveredId : null)
    : null;

  return (
    <div className={cn('relative w-full h-full select-none', className)}>
      <svg
        ref={svgRef}
        viewBox={`0 0 ${SVG_W} ${SVG_H}`}
        className="w-full h-full"
        style={{ fontFamily: 'inherit' }}
      >
        <OceanBackground />

        {/* Connection lines drawn before hexagons */}
        <ConnectionLines
          attackFrom={attackFrom}
          attackTo={attackTo}
          attackStep={attackStep}
        />

        {/* Hexagons */}
        <g id="territories">
          {TERRITORIES.map(t => (
            <Hexagon
              key={t.id}
              territory={t}
              state={territoryStates.get(t.id)}
              isSelected={selectedTerritory === t.id}
              isHovered={hoveredId === t.id}
              isAttackFrom={attackFrom === t.id}
              isAttackTarget={attackTo === t.id}
              isValidTarget={validTargets.has(t.id)}
              attackStep={attackStep}
              onClick={onSelectTerritory}
              onHover={handleHover}
            />
          ))}
        </g>

        {/* Continent labels (always on top) */}
        <ContinentLabels />

        {/* Map border / vignette */}
        <rect
          x={0} y={0} width={SVG_W} height={SVG_H}
          fill="none"
          stroke="#1a2e47"
          strokeWidth={4}
          rx={8}
          pointerEvents="none"
        />
      </svg>

      {/* Tooltip overlay */}
      <Tooltip
        territory={hoveredTerritory}
        state={hoveredState}
        attackStep={attackStep}
      />
    </div>
  );
}
