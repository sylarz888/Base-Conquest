# CLAUDE.md — Base-Conquest Development Guide

## Project Overview

**Base-Conquest** (CryptoConquest) is a decentralized, blockchain-based strategy game
inspired by the classic board game Risk. Players own territories, armies, and collectible
cards as blockchain tokens (NFTs and fungible tokens) on the **Base** blockchain, enabling
true ownership, secure trading, and provably fair combat with verifiable on-chain randomness.

Core gameplay pillars:
- **Territorial conquest** — players capture and defend regions represented as NFTs
- **Resource management** — army tokens, reinforcements, and card-based bonuses
- **Alliance building** — player-to-player coordination in a persistent world
- **Provably fair combat** — on-chain randomness (e.g., Chainlink VRF or Base-native entropy)

---

## Repository Status

This project is in the **pre-implementation / planning phase**. The repository currently
contains only documentation. All architectural decisions below represent the intended
development direction.

---

## Expected Project Structure

Once development begins, the repository should follow this structure:

```
Base-Conquest/
├── contracts/               # Solidity smart contracts
│   ├── src/
│   │   ├── core/            # Core game logic contracts
│   │   │   ├── GameBoard.sol
│   │   │   ├── CombatEngine.sol
│   │   │   └── TurnManager.sol
│   │   ├── tokens/          # Token contracts
│   │   │   ├── Territory.sol    # ERC-721 territory NFTs
│   │   │   ├── Army.sol         # ERC-20 army/troop tokens
│   │   │   └── ConquestCard.sol # ERC-721 collectible cards
│   │   └── interfaces/      # Shared interfaces
│   ├── test/                # Foundry tests
│   ├── script/              # Deployment scripts
│   ├── lib/                 # Forge dependencies (git submodules)
│   ├── foundry.toml
│   └── remappings.txt
├── frontend/                # Web application
│   ├── src/
│   │   ├── components/      # React UI components
│   │   ├── hooks/           # Custom React hooks (contract interactions)
│   │   ├── pages/           # Route-level pages
│   │   ├── store/           # Global state (Zustand or Redux)
│   │   ├── lib/             # Utilities and helpers
│   │   └── types/           # TypeScript type definitions
│   ├── public/
│   ├── package.json
│   ├── tsconfig.json
│   └── vite.config.ts
├── subgraph/                # The Graph protocol subgraph (optional)
│   ├── src/
│   ├── schema.graphql
│   └── subgraph.yaml
├── .github/
│   └── workflows/           # CI/CD pipelines
├── CLAUDE.md                # This file
└── README.md
```

---

## Technology Stack

### Smart Contracts
- **Language:** Solidity `^0.8.20`
- **Framework:** [Foundry](https://book.getfoundry.sh/) (forge, cast, anvil)
- **Network:** Base Mainnet / Base Sepolia (testnet)
- **Token Standards:** ERC-721 (territories, cards), ERC-20 (army tokens)
- **Randomness:** Chainlink VRF v2+ or Base-native entropy for combat resolution
- **Upgradability:** OpenZeppelin Transparent Proxy or UUPS pattern (if needed)

### Frontend
- **Framework:** Next.js (App Router) or Vite + React
- **Language:** TypeScript (strict mode)
- **Web3:** wagmi v2 + viem for contract interactions
- **Wallet:** RainbowKit or ConnectKit
- **Styling:** Tailwind CSS
- **State:** Zustand for client state; React Query for server/chain data

### Testing
- **Contracts:** Foundry (`forge test`)
- **Frontend:** Vitest + React Testing Library
- **E2E:** Playwright

---

## Development Workflows

### Smart Contract Development

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Build contracts
forge build

# Run all contract tests
forge test

# Run tests with verbosity
forge test -vvv

# Run a specific test file
forge test --match-path test/CombatEngine.t.sol

# Run a specific test function
forge test --match-test test_AttackerWinsWithHigherRoll

# Check gas snapshots
forge snapshot

# Format Solidity code
forge fmt

# Deploy to Base Sepolia
forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --verify

# Deploy to Base Mainnet (requires explicit confirmation)
forge script script/Deploy.s.sol --rpc-url base_mainnet --broadcast --verify
```

### Frontend Development

```bash
cd frontend

# Install dependencies
npm install

# Start dev server
npm run dev

# Type check
npm run typecheck

# Lint
npm run lint

# Run tests
npm run test

# Build for production
npm run build
```

### Environment Variables

```bash
# contracts/.env
PRIVATE_KEY=0x...
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
BASE_MAINNET_RPC_URL=https://mainnet.base.org
ETHERSCAN_API_KEY=...
CHAINLINK_VRF_SUBSCRIPTION_ID=...

# frontend/.env.local
NEXT_PUBLIC_CHAIN_ID=84532          # Base Sepolia
NEXT_PUBLIC_GAME_CONTRACT_ADDRESS=0x...
NEXT_PUBLIC_TERRITORY_NFT_ADDRESS=0x...
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=...
```

---

## Smart Contract Conventions

### File Organization
- One contract per file; filename must match contract name
- Interfaces prefixed with `I` (e.g., `ICombatEngine.sol`)
- Abstract base contracts prefixed with `Base` or placed in `abstract/`

### Solidity Style
- Follow the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- NatSpec comments on all `external` and `public` functions
- Use custom errors instead of `require` strings: `error InsufficientArmies(uint256 have, uint256 need);`
- Constants and immutables in `SCREAMING_SNAKE_CASE`
- Storage variables in `camelCase`; avoid unneeded prefixes (`s_` only if mixing is confusing)
- Emit events for every state-changing action (needed for subgraph/frontend indexing)
- Use `SafeERC20` for all ERC-20 transfers
- Mark functions `external` over `public` when not called internally

### Security Rules
- **Never use `tx.origin`** for authorization; always use `msg.sender`
- **Checks-Effects-Interactions** pattern strictly enforced — state changes before external calls
- **Reentrancy guards** (`ReentrancyGuard`) on all functions that transfer ETH or tokens
- **Access control** via OpenZeppelin `Ownable` or `AccessControl`; no ad-hoc `require(msg.sender == owner)`
- All randomness must come from Chainlink VRF or equivalent — never use block hashes alone
- Run `forge test` and `slither` before any deployment

### Testing Requirements
- Every contract function must have at least one test
- Use fuzz testing (`forge test` supports it natively) for math-heavy functions
- Test files mirror source structure: `test/core/CombatEngine.t.sol` for `src/core/CombatEngine.sol`
- Use `vm.expectRevert` to test all revert paths
- Achieve ≥90% line coverage before deployment

---

## Frontend Conventions

### TypeScript
- Strict mode enabled (`"strict": true` in tsconfig)
- No `any` types — use `unknown` and narrow where needed
- Generate ABI types with `wagmi generate` or `typechain`

### Component Structure
```
components/
  GameBoard/
    GameBoard.tsx         # Main component
    GameBoard.test.tsx    # Co-located tests
    useGameBoard.ts       # Component-specific hook
    index.ts              # Re-export
```

### Contract Interactions
- All contract reads via `useReadContract` / `useContractReads` (wagmi)
- All contract writes via `useWriteContract` with proper loading/error states
- Never hardcode addresses — import from a `constants/addresses.ts` keyed by chain ID
- Handle `insufficient funds`, `user rejected`, and `reverted` errors gracefully

---

## Game Logic Reference

### Territory System
- The game map is divided into regions, each a unique ERC-721 token
- Owning a territory grants the right to deploy armies and launch attacks
- Territories may belong to continents; holding a full continent grants a bonus

### Combat Resolution
- Attacker rolls up to 3 dice; defender rolls up to 2 dice
- Dice are resolved via on-chain randomness (VRF request/fulfill pattern)
- Highest attacker die vs. highest defender die; second-highest if available
- Ties go to the defender
- Results are emitted as events and indexed for the frontend

### Turn Phases
1. **Reinforce** — receive armies based on territories + continent bonuses + cards
2. **Attack** — optional; attack adjacent enemy territories
3. **Fortify** — optional; move armies along a connected path you control

### Card System
- Players earn one card per turn in which they conquered at least one territory
- Sets of 3 cards (Infantry, Cavalry, Artillery) can be traded for bonus armies
- Cards are ERC-721 tokens transferred to the game contract upon trade-in

---

## Git Workflow

### Branching
- `main` / `master` — stable, deployed code
- `develop` — integration branch for features
- `feature/<short-description>` — individual feature branches
- `fix/<issue-id>-description` — bug fix branches
- `claude/<task-id>` — AI-assisted development branches

### Commit Messages
Follow Conventional Commits:
```
feat(combat): add VRF-based dice resolution
fix(territory): correct adjacency check for island regions
test(board): add fuzz tests for army placement
docs: update deployment instructions
```

### Pull Requests
- Must pass all CI checks (forge test, lint, typecheck)
- Require at least one human review for contract changes
- Include test coverage report for contract PRs
- Link to the relevant issue or task

---

## Deployment Checklist

Before deploying to Base Mainnet:

- [ ] All `forge test` pass with `-vvv`
- [ ] `forge snapshot` run and gas report reviewed
- [ ] Static analysis with `slither` shows no high/critical issues
- [ ] Contracts audited (or audit waived with documented risk acceptance)
- [ ] Multisig wallet set as contract owner (not an EOA)
- [ ] VRF subscription funded with LINK
- [ ] Contract addresses updated in frontend `constants/addresses.ts`
- [ ] Subgraph deployed and synced
- [ ] Frontend environment variables set for mainnet

---

## Useful Resources

- [Base Documentation](https://docs.base.org)
- [Foundry Book](https://book.getfoundry.sh)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts)
- [Chainlink VRF on Base](https://docs.chain.link/vrf)
- [wagmi v2 Docs](https://wagmi.sh)
- [ERC-721 Standard](https://eips.ethereum.org/EIPS/eip-721)
- [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
