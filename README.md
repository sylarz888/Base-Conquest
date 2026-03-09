# Base-Conquest

A persistent, on-chain territory strategy game on Base — inspired by Risk, redesigned for Web3.

---

## Overview

Base-Conquest is a decentralized strategy game where players own territories as NFTs, deploy army tokens, and conquer a shared map through provably fair, Chainlink VRF-powered combat. The world persists on-chain across competitive **Seasons**, with a treasury prize pool awarded to dominant players at the end of each season.

Unlike traditional blockchain games, Base-Conquest is designed around meaningful decisions, fair randomness, and economics that reward strategy over spending.

---

## The World: The Base Archipelago

The map is a fixed set of **42 territories** organized into **6 island chains** (continents). The map never changes between seasons — only ownership does. Each territory is an ERC-721 NFT minted at the start of every season.

| Island Chain       | Territories | Bonus Armies/Turn |
|--------------------|-------------|-------------------|
| The Northlands     | 9           | +5                |
| Merchant Straits   | 7           | +3                |
| Iron Coast         | 6           | +2                |
| The Barrens        | 12          | +7                |
| Verdant Isles      | 4           | +2                |
| The Deep Expanse   | 4           | +2                |

Controlling all territories in a chain grants a continent bonus — the single most important economic advantage in the game.

---

## Core Game Loop

Each turn has three phases, executed in order:

### 1. Reinforce
- Receive armies equal to `max(3, floor(territories_owned / 3))` + any continent bonuses
- Spend armies by deploying **Army Tokens** (ERC-1155) to any territory you own
- Players who turn in a set of **Territory Cards** receive a one-time bonus army grant

### 2. Attack
- Attack any adjacent territory you do not own
- Attacker commits up to **3 armies**; defender automatically defends with up to **2 armies**
- Chainlink VRF resolves all dice rolls — one request per attack, result delivered in callback
- Classic Risk resolution: compare highest dice, then second-highest; higher die wins; ties go to defender
- If defender loses all armies, attacker occupies the territory (minimum 1 army must advance)
- Attacker draws a **Territory Card** on any turn they capture at least one territory

### 3. Fortify
- Move any number of armies between two of your connected territories (one move per turn)
- Connection is determined by territory adjacency as defined in the map contract

---

## Army Units

Five unit types exist as ERC-1155 tokens. Each unit occupies one "army slot" but provides different modifiers:

| Unit       | Token ID | Cost (armies) | Effect                                                  |
|------------|----------|---------------|---------------------------------------------------------|
| Infantry   | 1        | 1             | Standard unit — counts as 1 die                        |
| Cavalry    | 2        | 3             | Counts as 3 Infantry; attackers reroll their lowest die |
| Artillery  | 3        | 5             | Counts as 5 Infantry; defenders reroll their lowest die |
| General    | 4        | 10            | Adds +1 attack die (max 4 dice for attacker)            |
| Admiral    | 5        | 10            | Enables naval attacks to non-adjacent island territories |

Cavalry and Artillery are minted by trading in Infantry tokens. Units are **burned on combat loss**, creating a constant deflationary sink.

---

## Territory Cards

Every time a player captures at least one territory in a turn, they draw one **Territory Card** (ERC-1155). Cards come in three types:

- **Infantry Card** — depicts a territory icon
- **Cavalry Card** — depicts a territory icon with horse sigil
- **Artillery Card** — depicts a territory icon with cannon sigil

**Turning in sets** for bonus armies (on your Reinforce phase):
- 3 Infantry Cards → 4 bonus armies
- 3 Cavalry Cards → 6 bonus armies
- 3 Artillery Cards → 8 bonus armies
- 1 of each type → 10 bonus armies
- If one of the 3 cards matches a territory you own → +2 additional armies to that territory

Bonus army values escalate as more sets are turned in globally (classic Risk escalation), adding late-game urgency.

---

## Alliance System

Players can form **on-chain alliances** using EIP-712 signed agreements:

- **Non-Aggression Pact (NAP)**: Both players sign; the GameEngine contract enforces it — attacks against a NAP partner revert for the agreed duration (measured in turns)
- **Army Sharing**: Allies can move armies through each other's connected territories during Fortify phase
- **Betrayal Cooldown**: After breaking a NAP early, the breaking player cannot form new alliances for 5 turns and takes a -1 penalty on all attack dice for 3 turns (encoded in contract state)
- **Alliance Victory**: If two allied players together control all 42 territories, they can call a shared victory — treasury is split proportionally by territory count

Alliances are public and on-chain. There are no hidden deals — strategy is transparent.

---

## Win Conditions

Base-Conquest supports two victory types per Season:

### 1. World Domination
- Control all 42 territories simultaneously at the end of your turn
- Instant victory; you claim the Season Prize Pool (80% of treasury)
- Remaining 20% rolls into the next Season

### 2. Season Timer Victory (if no Domination)
- Seasons last **90 days** (configurable by governance before each season starts)
- At the end of the season, the player with the most territories wins 60% of the treasury
- 2nd place: 25%, 3rd place: 15%
- In case of a tie, the player holding the longest-held territory wins the tiebreak

---

## Tokenomics

### CONQUEST Token (ERC-20)
- **Governance**: Vote on Season parameters (duration, map, unit costs, prize splits)
- **Protocol fees**: 2% of every territory NFT secondary sale goes to treasury; 5% of season entry fees converted to CONQUEST for distribution to long-term stakers
- **Supply**: Fixed cap of 100,000,000 CONQUEST
- **Emission**: 40% reserved for Season rewards over 10 years (decaying schedule), 30% team/treasury (4-year vest), 20% initial liquidity, 10% community grants
- **Burn mechanic**: 1% of all CONQUEST used for premium features (custom unit skins, map themes) is burned

### Territory NFTs (ERC-721)
- 42 minted fresh at the start of each Season
- Initial auction at Season start — proceeds go to Prize Pool treasury
- During a Season: territories can only change hands via in-game conquest (non-transferable)
- After a Season ends: territories unlock and become freely tradeable for 14 days before next Season mint
- Royalty: 5% on secondary sales (2% treasury, 3% to current season's prize pool)

### Army Tokens (ERC-1155)
- Minted when players spend reinforcement armies
- Burned when units die in combat
- No secondary market — purely in-game utility tokens (soulbound to game session)
- Prevents army hoarding and secondary market manipulation

### Territory Cards (ERC-1155)
- Burned when turned in for bonus armies
- Surplus cards after a Season can be redeemed for a small CONQUEST reward
- Tradeable between players during active Season (creates a card economy within the game)

---

## Player Types & Accessibility

| Player Type  | Strategy                                   | Entry Path                         |
|--------------|--------------------------------------------|------------------------------------|
| Strategist   | Focus on continent control for army bonuses | Buy 1–2 strategic territories at auction |
| Aggressor    | Rapid expansion, use General units          | Bid high on central territories    |
| Diplomat     | Build alliances, share in partner victories | Buy any territories; build alliances early |
| Speculator   | Trade territory NFTs between Seasons        | Buy distressed territories post-Season |
| Observer     | Watch, bet on outcomes via prediction market | No territory required              |

**Free-to-Play path**: Players can earn CONQUEST by completing protocol-defined **Bounties** (e.g., "Hold Iron Coast for 10 consecutive turns") without needing to buy territory NFTs at auction. Bounty rewards are funded by the protocol treasury.

---

## Season Flow

```
Season Auction (3 days)
  → Players bid ETH on the 42 Territory NFTs
  → Proceeds fill the Season Prize Pool

Season Active (90 days)
  → Turns are time-gated: 1 turn per 24 hours per player
  → Players execute Reinforce → Attack → Fortify each day
  → VRF resolves all combat asynchronously

Season End
  → Victory claimed or timer expires
  → Prize pool distributed
  → Territory NFTs unlock for 14-day trading window

Next Season
  → Territories relisted for new auction
  → Map is identical; ownership resets
```

---

## On-Chain vs Off-Chain Split

Not every action needs a transaction. The game is designed to minimize gas cost for casual play:

| Action                  | On-chain | Off-chain (signature) |
|-------------------------|----------|-----------------------|
| Deploy armies           | Yes      |                       |
| Commit attack           | Yes      |                       |
| VRF dice resolution     | Yes      |                       |
| Fortify armies          | Yes      |                       |
| Alliance NAP signing    | Yes (stored on-chain) | Signed off-chain, submitted once |
| Territory Card trade    | Yes (ERC-1155 transfer) | |
| Turn in cards for armies | Yes     |                       |
| View game state         |          | Read from RPC/subgraph |
| Chat / diplomacy chat   |          | Off-chain (XMTP or Farcaster frames) |

---

## Anti-Abuse & Fairness Rules

- **Turn time limit**: Players who miss 3 consecutive turns enter "Inactive" mode — their territories become capturable by anyone (no defense bonus) until they return
- **Sybil resistance**: Each wallet may own a maximum of 12 territories at Season start (~28% of the map); further acquisitions must come through in-game conquest
- **Whale cap**: No single player may receive more than 40% of the Season prize pool via World Domination if they held >35 territories at any point (excess goes to 2nd place)
- **VRF commitment window**: Players have 24 hours to reveal after committing an attack; after that the attack expires and committed armies are returned

---

## Technical Stack

| Layer          | Technology                                    |
|----------------|-----------------------------------------------|
| Blockchain     | Base (OP Stack L2)                            |
| Contracts      | Solidity 0.8.24, Foundry, OpenZeppelin 5.x    |
| Randomness     | Chainlink VRF v2.5                            |
| Indexing       | The Graph (subgraph for all game events)      |
| Frontend       | Next.js 14, wagmi v2, viem, Tailwind CSS      |
| Map rendering  | SVG-based interactive territory map           |
| Wallet support | MetaMask, Coinbase Wallet, WalletConnect      |
| State mgmt     | Zustand + React Query                         |
| Comms          | XMTP for in-game player messaging             |

---

## Roadmap

| Phase | Milestone                                              |
|-------|--------------------------------------------------------|
| 0     | Architecture design, agent system, game design doc     |
| 1     | Core contracts (Territory NFT, Army Token, GameEngine) |
| 2     | Chainlink VRF integration + full test suite            |
| 3     | Base Sepolia testnet deployment + The Graph subgraph   |
| 4     | Frontend MVP (map, wallet, combat UI)                  |
| 5     | Season 0 public beta (free entry, CONQUEST rewards)    |
| 6     | Security audit + Season 1 mainnet launch               |
| 7     | Governance activation + DAO transition                 |
