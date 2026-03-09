# Developer Setup

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- Git

## 1. Install Foundry

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

## 2. Clone and install dependencies

```bash
git clone https://github.com/sylarz888/Base-Conquest.git
cd Base-Conquest

# Install OpenZeppelin 5.x and Chainlink VRF as git submodules
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-commit
forge install smartcontractkit/chainlink --no-commit
```

## 3. Configure environment

```bash
cp .env.example .env
# Edit .env and fill in your PRIVATE_KEY, RPC URLs, and Chainlink VRF values
```

## 4. Build

```bash
forge build
```

## 5. Test

```bash
# All tests
forge test -vvv

# Unit tests only
forge test --match-path "test/unit/**" -vvv

# With gas report
forge test --gas-report

# Coverage
forge coverage --report lcov
```

## 6. Format

```bash
forge fmt
```

## 7. Run Slither (static analysis)

```bash
pip3 install slither-analyzer
slither . --exclude-dependencies --filter-paths lib/
```

## 8. Deploy to Base Sepolia

```bash
source .env

forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $BASE_SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $BASESCAN_API_KEY \
  -vvvv
```

## 9. Local development with Anvil

```bash
# Start local fork of Base Sepolia
anvil --fork-url $BASE_SEPOLIA_RPC_URL

# In another terminal, deploy to local fork
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url http://localhost:8545 \
  --broadcast \
  -vvvv
```

## Chainlink VRF Setup

1. Go to [https://vrf.chain.link/base-sepolia](https://vrf.chain.link/base-sepolia)
2. Create a new subscription
3. Fund it with testnet LINK (faucet: [https://faucets.chain.link](https://faucets.chain.link))
4. Copy your subscription ID into `.env` as `VRF_SUBSCRIPTION_ID`
5. After deployment, add the `VRFConsumer` contract address as a consumer on your subscription

## Directory Structure

```
Base-Conquest/
├── src/
│   ├── interfaces/          # Contract interfaces (written first)
│   │   ├── IGameEngine.sol
│   │   ├── ITerritoryNFT.sol
│   │   ├── IArmyToken.sol
│   │   └── ITerritoryCard.sol
│   ├── tokens/              # ERC-721 and ERC-1155 token contracts
│   │   ├── TerritoryNFT.sol
│   │   ├── ArmyToken.sol
│   │   └── TerritoryCard.sol
│   ├── game/                # Core game logic
│   │   ├── GameEngine.sol
│   │   └── TreasuryVault.sol
│   └── vrf/                 # Chainlink VRF integration
│       └── VRFConsumer.sol
├── test/
│   ├── unit/                # Per-contract unit tests
│   ├── integration/         # Multi-contract flow tests
│   ├── fuzz/                # Fuzz tests
│   ├── invariant/           # Invariant tests
│   └── mocks/               # Mock contracts (MockVRFCoordinator, etc.)
├── script/
│   └── Deploy.s.sol         # Deployment script
├── deployments/             # Deployed contract addresses per network
├── lib/                     # Forge submodule dependencies
├── foundry.toml
├── remappings.txt
├── .env.example
└── SETUP.md
```
