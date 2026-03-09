import type { TerritoryMeta, ContinentMeta, ContinentId } from '@/types/game';

// ── Continent Definitions ─────────────────────────────────────────────────────

export const CONTINENTS: Record<ContinentId, ContinentMeta> = {
  1: {
    id: 1,
    name: 'The Northlands',
    bonusArmies: 5,
    color: '#1e4a8a',
    borderColor: '#4a90d9',
    textColor: '#93c5fd',
    description: 'Frozen highlands of the far north. Highest bonus, hardest to hold.',
  },
  2: {
    id: 2,
    name: 'Merchant Straits',
    bonusArmies: 3,
    color: '#0d5c52',
    borderColor: '#2ab5a0',
    textColor: '#6ee7b7',
    description: 'Prosperous trade routes. A gateway between north and south.',
  },
  3: {
    id: 3,
    name: 'Iron Coast',
    bonusArmies: 2,
    color: '#374151',
    borderColor: '#8a9bb0',
    textColor: '#cbd5e1',
    description: 'Rugged industrial shores. The eastern anchor of The Archipelago.',
  },
  4: {
    id: 4,
    name: 'The Barrens',
    bonusArmies: 7,
    color: '#6b3a0d',
    borderColor: '#d4a03a',
    textColor: '#fbbf24',
    description: 'Vast desert wastes. The largest continent — enormous bonus if tamed.',
  },
  5: {
    id: 5,
    name: 'Verdant Isles',
    bonusArmies: 2,
    color: '#14532d',
    borderColor: '#4aae6a',
    textColor: '#86efac',
    description: 'Lush island chain to the west. Easy to defend, hard to reach.',
  },
  6: {
    id: 6,
    name: 'The Deep Expanse',
    bonusArmies: 2,
    color: '#1e2d6b',
    borderColor: '#3a5fc4',
    textColor: '#93c5fd',
    description: 'Abyssal islands at the bottom of the world. Naval access required.',
  },
};

// ── Territory Positions & Connections ────────────────────────────────────────
// SVG viewport: 1100 × 760
// Hexagon radius: 38px (flat-top)

export const TERRITORIES: TerritoryMeta[] = [
  // ── The Northlands (1–9) ─────────────────────────────────────────────────
  { id:1,  name:'Stonehaven',   continentId:1, cx:130, cy:120, adjacentIds:[2,4],       navalIds:[] },
  { id:2,  name:'Frostpeak',    continentId:1, cx:210, cy:80,  adjacentIds:[1,3,5],     navalIds:[] },
  { id:3,  name:'Glacierhold',  continentId:1, cx:290, cy:120, adjacentIds:[2,6],       navalIds:[] },
  { id:4,  name:'Ironwarden',   continentId:1, cx:130, cy:200, adjacentIds:[1,5,7],     navalIds:[] },
  { id:5,  name:'Rimegate',     continentId:1, cx:210, cy:160, adjacentIds:[2,4,6,8],   navalIds:[] },
  { id:6,  name:'Iceholm',      continentId:1, cx:290, cy:200, adjacentIds:[3,5,9],     navalIds:[] },
  { id:7,  name:'Coldpass',     continentId:1, cx:130, cy:280, adjacentIds:[4,8,23],    navalIds:[] },
  { id:8,  name:'Blizzardrun',  continentId:1, cx:210, cy:240, adjacentIds:[5,7,9],     navalIds:[] },
  { id:9,  name:'Northwatch',   continentId:1, cx:290, cy:280, adjacentIds:[6,8,10],    navalIds:[] },

  // ── Merchant Straits (10–16) ─────────────────────────────────────────────
  { id:10, name:'Tradehaven',   continentId:2, cx:400, cy:200, adjacentIds:[9,11,13],       navalIds:[] },
  { id:11, name:'Saltbridge',   continentId:2, cx:480, cy:160, adjacentIds:[10,12,14],      navalIds:[] },
  { id:12, name:'Harborkeep',   continentId:2, cx:560, cy:200, adjacentIds:[11,15],         navalIds:[] },
  { id:13, name:'Coinwater',    continentId:2, cx:400, cy:280, adjacentIds:[10,14,23],      navalIds:[] },
  { id:14, name:'Marketpass',   continentId:2, cx:480, cy:240, adjacentIds:[11,13,15,16],   navalIds:[] },
  { id:15, name:'Spicedock',    continentId:2, cx:560, cy:280, adjacentIds:[12,14,16],      navalIds:[] },
  { id:16, name:'Merchantfall', continentId:2, cx:480, cy:320, adjacentIds:[14,15,17],      navalIds:[] },

  // ── Iron Coast (17–22) ───────────────────────────────────────────────────
  { id:17, name:'Ironcliff',    continentId:3, cx:600, cy:340, adjacentIds:[16,18,20],   navalIds:[] },
  { id:18, name:'Forgeharbor',  continentId:3, cx:680, cy:300, adjacentIds:[17,19],      navalIds:[] },
  { id:19, name:'Steelcove',    continentId:3, cx:680, cy:380, adjacentIds:[18,22],      navalIds:[] },
  { id:20, name:'Anviltide',    continentId:3, cx:600, cy:420, adjacentIds:[17,21,35],   navalIds:[] },
  { id:21, name:'Rustwater',    continentId:3, cx:680, cy:460, adjacentIds:[20,22],      navalIds:[] },
  { id:22, name:'Slagport',     continentId:3, cx:600, cy:500, adjacentIds:[19,34],      navalIds:[] },

  // ── The Barrens (23–34) ──────────────────────────────────────────────────
  { id:23, name:'Dustvault',    continentId:4, cx:290, cy:360, adjacentIds:[7,13,24,26],     navalIds:[] },
  { id:24, name:'Ashreach',     continentId:4, cx:370, cy:320, adjacentIds:[23,25,27],       navalIds:[] },
  { id:25, name:'Sandbarrow',   continentId:4, cx:450, cy:360, adjacentIds:[24,28],          navalIds:[] },
  { id:26, name:'Drypass',      continentId:4, cx:290, cy:440, adjacentIds:[23,27,29],       navalIds:[] },
  { id:27, name:'Bonecross',    continentId:4, cx:370, cy:400, adjacentIds:[24,26,28,30],    navalIds:[] },
  { id:28, name:'Saltflat',     continentId:4, cx:450, cy:440, adjacentIds:[25,27,31],       navalIds:[] },
  { id:29, name:'Mirage',       continentId:4, cx:290, cy:520, adjacentIds:[26,30,39],       navalIds:[] },
  { id:30, name:'Scorchfield',  continentId:4, cx:370, cy:480, adjacentIds:[27,29,31,32],    navalIds:[] },
  { id:31, name:'Cinderholm',   continentId:4, cx:450, cy:520, adjacentIds:[28,30,33],       navalIds:[] },
  { id:32, name:'Embervast',    continentId:4, cx:370, cy:560, adjacentIds:[30,33],          navalIds:[] },
  { id:33, name:'Dustcrown',    continentId:4, cx:450, cy:600, adjacentIds:[31,32,34],       navalIds:[] },
  { id:34, name:'Barrenkeep',   continentId:4, cx:530, cy:560, adjacentIds:[22,33],          navalIds:[] },

  // ── Verdant Isles (35–38) ────────────────────────────────────────────────
  { id:35, name:'Greenwatch',   continentId:5, cx:680, cy:540, adjacentIds:[20,36],   navalIds:[] },
  { id:36, name:'Bloomhaven',   continentId:5, cx:760, cy:500, adjacentIds:[35,37],   navalIds:[] },
  { id:37, name:'Ferncoast',    continentId:5, cx:760, cy:580, adjacentIds:[36,38],   navalIds:[] },
  { id:38, name:'Leafend',      continentId:5, cx:680, cy:640, adjacentIds:[37],      navalIds:[42] },

  // ── The Deep Expanse (39–42) ─────────────────────────────────────────────
  { id:39, name:'Abyssgate',    continentId:6, cx:290, cy:620, adjacentIds:[29,40],   navalIds:[] },
  { id:40, name:'Deepcurrent',  continentId:6, cx:370, cy:660, adjacentIds:[39,41],   navalIds:[] },
  { id:41, name:'Voidreach',    continentId:6, cx:460, cy:680, adjacentIds:[40,42],   navalIds:[] },
  { id:42, name:'Dreadhollow',  continentId:6, cx:560, cy:660, adjacentIds:[41],      navalIds:[38] },
];

export const TERRITORY_MAP = new Map(TERRITORIES.map(t => [t.id, t]));

/** All land + naval connections as undirected pairs (deduped). */
export const CONNECTIONS: [number, number][] = (() => {
  const seen = new Set<string>();
  const result: [number, number][] = [];
  for (const t of TERRITORIES) {
    for (const nid of t.adjacentIds) {
      const key = [Math.min(t.id, nid), Math.max(t.id, nid)].join('-');
      if (!seen.has(key)) { seen.add(key); result.push([t.id, nid]); }
    }
    for (const nid of t.navalIds) {
      const key = `n-${[Math.min(t.id, nid), Math.max(t.id, nid)].join('-')}`;
      if (!seen.has(key)) { seen.add(key); result.push([t.id, nid]); }
    }
  }
  return result;
})();

/** Pairs that are naval connections (for dashed rendering). */
export const NAVAL_PAIRS = new Set(
  TERRITORIES.flatMap(t => t.navalIds.map(nid =>
    [Math.min(t.id, nid), Math.max(t.id, nid)].join('-')
  ))
);
