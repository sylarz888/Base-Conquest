// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TerritoryNFT}  from "../src/tokens/TerritoryNFT.sol";
import {ArmyToken}     from "../src/tokens/ArmyToken.sol";
import {TerritoryCard} from "../src/tokens/TerritoryCard.sol";
import {VRFConsumer}   from "../src/vrf/VRFConsumer.sol";
import {TreasuryVault} from "../src/game/TreasuryVault.sol";
import {GameEngine}    from "../src/game/GameEngine.sol";

/// @title DeployScript
/// @notice Deploys all Base-Conquest contracts in dependency order and links them.
/// @dev Run with:
///   forge script script/Deploy.s.sol:DeployScript \
///     --rpc-url $BASE_SEPOLIA_RPC_URL \
///     --broadcast --verify --etherscan-api-key $BASESCAN_API_KEY -vvvv
contract DeployScript is Script {
    // ── Env vars ──────────────────────────────────────────────────────────────
    uint256 public deployerKey;
    address public deployer;
    address public adminMultisig;

    // VRF config
    address public vrfCoordinator;
    uint256 public vrfSubId;
    bytes32 public vrfKeyHash;
    uint32  public vrfCallbackGasLimit;

    // CONQUEST placeholder — deploy separately or set to existing address
    address public conquestToken;

    // ── Deployed addresses ────────────────────────────────────────────────────
    TerritoryNFT  public territoryNFT;
    ArmyToken     public armyToken;
    TerritoryCard public territoryCard;
    VRFConsumer   public vrfConsumer;
    TreasuryVault public treasuryVault;
    GameEngine    public gameEngine;

    function setUp() public {
        deployerKey      = vm.envUint("PRIVATE_KEY");
        deployer         = vm.addr(deployerKey);
        adminMultisig    = vm.envOr("ADMIN_MULTISIG", deployer);

        vrfCoordinator       = vm.envOr("VRF_COORDINATOR",       address(0));
        vrfSubId             = vm.envOr("VRF_SUBSCRIPTION_ID",   uint256(0));
        vrfKeyHash           = vm.envOr("VRF_KEY_HASH",          bytes32(0));
        vrfCallbackGasLimit  = uint32(vm.envOr("VRF_CALLBACK_GAS", uint256(500_000)));
        conquestToken        = vm.envOr("CONQUEST_TOKEN",         address(0));
    }

    function run() public {
        vm.startBroadcast(deployerKey);

        // ── 1. TreasuryVault ──────────────────────────────────────────────────
        treasuryVault = new TreasuryVault(adminMultisig);
        console2.log("TreasuryVault:", address(treasuryVault));

        // ── 2. TerritoryNFT ───────────────────────────────────────────────────
        territoryNFT = new TerritoryNFT(adminMultisig);
        console2.log("TerritoryNFT:", address(territoryNFT));

        // Initialize map (42 territories, 6 continents)
        territoryNFT.initializeMap();
        console2.log("Map initialized");

        // ── 3. ArmyToken ──────────────────────────────────────────────────────
        armyToken = new ArmyToken(
            adminMultisig,
            "https://base-conquest.io/army/{id}.json"
        );
        console2.log("ArmyToken:", address(armyToken));

        // ── 4. TerritoryCard ──────────────────────────────────────────────────
        uint256 redemptionRate = 10e18; // 10 CONQUEST per card
        territoryCard = new TerritoryCard(
            adminMultisig,
            "https://base-conquest.io/card/{id}.json",
            conquestToken != address(0) ? conquestToken : address(0),
            redemptionRate
        );
        console2.log("TerritoryCard:", address(territoryCard));

        // ── 5. GameEngine ─────────────────────────────────────────────────────
        gameEngine = new GameEngine(
            adminMultisig,
            address(territoryNFT),
            address(armyToken),
            address(territoryCard),
            address(treasuryVault)
        );
        console2.log("GameEngine:", address(gameEngine));

        // ── 6. VRFConsumer ────────────────────────────────────────────────────
        // Skip if no VRF coordinator configured (local dev / fork tests)
        if (vrfCoordinator != address(0) && vrfSubId != 0) {
            vrfConsumer = new VRFConsumer(
                vrfCoordinator,
                vrfSubId,
                vrfKeyHash,
                vrfCallbackGasLimit,
                address(gameEngine)
            );
            console2.log("VRFConsumer:", address(vrfConsumer));
            gameEngine.setVRFConsumer(address(vrfConsumer));
            console2.log("VRFConsumer linked to GameEngine");
        } else {
            console2.log("VRFConsumer: SKIPPED (no VRF_COORDINATOR set)");
        }

        // ── 7. Grant Roles ────────────────────────────────────────────────────
        bytes32 MINTER_ROLE      = keccak256("MINTER_ROLE");
        bytes32 GAME_ENGINE_ROLE = keccak256("GAME_ENGINE_ROLE");
        bytes32 DEPOSITOR_ROLE   = keccak256("DEPOSITOR_ROLE");
        bytes32 GAME_MASTER_ROLE = keccak256("GAME_MASTER_ROLE");

        // GameEngine can mint/burn territory NFTs (conquest transfers already use conquestTransfer)
        territoryNFT.grantRole(GAME_ENGINE_ROLE, address(gameEngine));
        // GameEngine can mint/burn army tokens
        armyToken.grantRole(GAME_ENGINE_ROLE, address(gameEngine));
        // GameEngine can draw/burn territory cards
        territoryCard.grantRole(GAME_ENGINE_ROLE, address(gameEngine));
        // GameEngine can distribute prizes
        treasuryVault.grantRole(GAME_ENGINE_ROLE, address(gameEngine));
        // GameEngine can receive auction proceeds
        // (Auction contract would be set as DEPOSITOR; for now grant to deployer)
        treasuryVault.grantRole(DEPOSITOR_ROLE, deployer);

        // Auction contract will need MINTER_ROLE on TerritoryNFT
        // Grant to deployer temporarily; replace with auction contract post-deploy
        territoryNFT.grantRole(MINTER_ROLE, deployer);

        console2.log("Roles granted");

        // ── 8. Transfer admin roles to multisig (if different from deployer) ──
        if (adminMultisig != deployer) {
            // Roles already granted to adminMultisig in constructors
            // Revoke deployer's admin roles for security
            bytes32 DEFAULT_ADMIN_ROLE = bytes32(0);
            // Note: Only revoke after confirming multisig has control
            // territoryNFT.revokeRole(DEFAULT_ADMIN_ROLE, deployer);
            // armyToken.revokeRole(DEFAULT_ADMIN_ROLE, deployer);
            // ... etc
            // Uncomment above lines after verifying multisig access
            console2.log("REMINDER: Revoke deployer admin roles after confirming multisig access");
        }

        vm.stopBroadcast();

        // ── 9. Write deployment artifacts ─────────────────────────────────────
        _writeDeployments();
    }

    function _writeDeployments() internal {
        string memory chainName = block.chainid == 8453 ? "base-mainnet" : "base-sepolia";
        string memory path      = string.concat("deployments/", chainName, ".json");

        string memory json = string.concat(
            '{\n',
            '  "network": "', chainName, '",\n',
            '  "chainId": ', vm.toString(block.chainid), ',\n',
            '  "deployer": "', vm.toString(deployer), '",\n',
            '  "adminMultisig": "', vm.toString(adminMultisig), '",\n',
            '  "contracts": {\n',
            '    "TerritoryNFT":  "', vm.toString(address(territoryNFT)),  '",\n',
            '    "ArmyToken":     "', vm.toString(address(armyToken)),     '",\n',
            '    "TerritoryCard": "', vm.toString(address(territoryCard)), '",\n',
            '    "GameEngine":    "', vm.toString(address(gameEngine)),    '",\n',
            '    "TreasuryVault": "', vm.toString(address(treasuryVault)), '",\n',
            '    "VRFConsumer":   "', vm.toString(address(vrfConsumer)),   '"\n',
            '  }\n',
            '}'
        );

        vm.writeFile(path, json);
        console2.log("Deployment written to", path);
    }
}
