// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IGameEngine} from "../interfaces/IGameEngine.sol";
import {ITerritoryNFT} from "../interfaces/ITerritoryNFT.sol";
import {IArmyToken} from "../interfaces/IArmyToken.sol";
import {ITerritoryCard} from "../interfaces/ITerritoryCard.sol";
import {IVRFConsumer} from "../interfaces/IVRFConsumer.sol";
import {ITreasuryVault} from "../interfaces/ITreasuryVault.sol";

/// @title GameEngine
/// @notice Central game contract for Base-Conquest.
/// @dev Implements the full Risk-inspired turn loop with Chainlink VRF combat.
///      Turn structure per player: Reinforce → Attack → Fortify → End
///      Players may take one turn per 24-hour window (no fixed turn order).
contract GameEngine is IGameEngine, AccessControl, Pausable, ReentrancyGuard {
    // ── Roles ─────────────────────────────────────────────────────────────────
    bytes32 public constant GAME_MASTER_ROLE = keccak256("GAME_MASTER_ROLE");
    bytes32 public constant VRF_CONSUMER_ROLE = keccak256("VRF_CONSUMER_ROLE");

    // ── Constants ─────────────────────────────────────────────────────────────
    uint256 public constant TOTAL_TERRITORIES   = 42;
    uint256 public constant TURN_COOLDOWN       = 24 hours;
    uint256 public constant AUCTION_DURATION    = 3 days;
    uint256 public constant ATTACK_TIMEOUT      = 24 hours;
    uint256 public constant MAX_PER_WALLET      = 12;
    uint256 public constant INACTIVE_THRESHOLD  = 3;   // missed turns → inactive
    uint256 public constant ABANDON_THRESHOLD   = 10;  // missed turns → territories claimable
    uint256 public constant MIN_NAP_DURATION    = 5;   // turns
    uint256 public constant NAP_PROPOSAL_TTL    = 3;   // turns to accept before proposal expires
    uint256 public constant BETRAYAL_COOLDOWN   = 5;   // turns
    uint256 public constant BETRAYAL_PENALTY    = 3;   // turns of -1 attack die

    // ── External Contracts ────────────────────────────────────────────────────
    ITerritoryNFT  public immutable territoryNFT;
    IArmyToken     public immutable armyToken;
    ITerritoryCard public immutable territoryCard;
    IVRFConsumer   public vrfConsumer;
    ITreasuryVault public treasuryVault;

    // ── Season State ──────────────────────────────────────────────────────────
    uint256 public override currentSeason;
    SeasonPhase public override seasonPhase;
    uint256 public override seasonEndsAt;
    uint256 public auctionEndsAt;
    uint256 public defaultSeasonDuration = 90 days;

    // ── Turn Tracking ─────────────────────────────────────────────────────────
    uint64  public override globalTurn;
    uint256 public setsRedeemedGlobally;

    // ── Per-Territory Army Storage ────────────────────────────────────────────
    // territoryId => unitType (1-5) => count
    mapping(uint256 => mapping(uint256 => uint256)) private _armiesAt;

    // ── Per-Player State ──────────────────────────────────────────────────────
    mapping(address => PlayerState)  private _playerState;
    mapping(address => TurnPhase)    private _turnPhase;
    mapping(address => uint256)      private _turnStartedAt;     // timestamp
    mapping(address => bool)         private _activeTurn;         // in progress
    mapping(address => bool)         private _conqueredThisTurn;  // drew card eligibility
    mapping(address => uint256)      private _peakTerritories;   // for whale cap
    mapping(address => bool)         private _fortifiedThisTurn;  // one fortify per turn

    // ── Pending Combat ────────────────────────────────────────────────────────
    mapping(uint256 => PendingCombat) private _pendingCombat;
    // territory → pending request (to prevent two concurrent attacks from same territory)
    mapping(uint256 => uint256) private _activeCombatByTerritory;

    // ── Alliance (NAP) System ─────────────────────────────────────────────────
    // key = keccak256(abi.encodePacked(sorted addresses))
    mapping(bytes32 => Alliance)    private _alliances;
    // proposer → target → proposal turn number
    mapping(address => mapping(address => uint64)) private _proposals;

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(
        address admin,
        address territoryNFT_,
        address armyToken_,
        address territoryCard_,
        address treasuryVault_
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GAME_MASTER_ROLE, admin);

        territoryNFT  = ITerritoryNFT(territoryNFT_);
        armyToken     = IArmyToken(armyToken_);
        territoryCard = ITerritoryCard(territoryCard_);
        treasuryVault = ITreasuryVault(payable(treasuryVault_));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin Setup
    // ─────────────────────────────────────────────────────────────────────────

    function setVRFConsumer(address consumer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        vrfConsumer = IVRFConsumer(consumer);
        _grantRole(VRF_CONSUMER_ROLE, consumer);
    }

    function setDefaultSeasonDuration(uint256 duration) external onlyRole(GAME_MASTER_ROLE) {
        defaultSeasonDuration = duration;
    }

    function pause()   external onlyRole(DEFAULT_ADMIN_ROLE) { _pause(); }
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) { _unpause(); }

    // ─────────────────────────────────────────────────────────────────────────
    // Season Management
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IGameEngine
    function startSeason() external onlyRole(GAME_MASTER_ROLE) whenNotPaused {
        if (seasonPhase != SeasonPhase.INACTIVE && seasonPhase != SeasonPhase.ENDED) {
            revert GameEngine__WrongSeasonPhase(seasonPhase, SeasonPhase.INACTIVE);
        }
        currentSeason++;
        seasonPhase  = SeasonPhase.AUCTION;
        auctionEndsAt = block.timestamp + AUCTION_DURATION;
        setsRedeemedGlobally = 0;

        emit SeasonStarted(currentSeason, auctionEndsAt);
    }

    /// @inheritdoc IGameEngine
    function activateSeason() external whenNotPaused {
        if (seasonPhase != SeasonPhase.AUCTION) {
            revert GameEngine__WrongSeasonPhase(seasonPhase, SeasonPhase.AUCTION);
        }
        if (block.timestamp < auctionEndsAt) revert GameEngine__WrongSeasonPhase(seasonPhase, SeasonPhase.ACTIVE);

        seasonPhase  = SeasonPhase.ACTIVE;
        seasonEndsAt = block.timestamp + defaultSeasonDuration;

        territoryNFT.lockForSeason(currentSeason);
        territoryCard.setSeasonActive(true);

        emit GameActivated(currentSeason, seasonEndsAt);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Turn: Start
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IGameEngine
    function startTurn() external nonReentrant whenNotPaused {
        _requireActiveGame();
        address player = msg.sender;

        // Enforce 24-hour cooldown
        uint256 lastTurn = _playerState[player].lastTurnTaken;
        if (lastTurn > 0 && block.timestamp < _turnStartedAt[player] + TURN_COOLDOWN) {
            revert GameEngine__TurnCooldownActive(player, _turnStartedAt[player] + TURN_COOLDOWN);
        }

        // Must own at least 1 territory to take a turn
        uint256 ownedCount = territoryNFT.territoriesOwnedBy(player);
        if (ownedCount == 0) return; // silently skip — no territories

        _activeTurn[player]        = true;
        _conqueredThisTurn[player] = false;
        _fortifiedThisTurn[player] = false;
        _turnPhase[player]         = TurnPhase.REINFORCE;
        _turnStartedAt[player]     = block.timestamp;

        // Reset inactivity streak
        _playerState[player].missedTurns = 0;
        _playerState[player].inactive    = false;

        // Calculate and grant reinforcement armies (as Infantry)
        uint256 reinforcements = _calculateReinforcements(player);
        armyToken.mint(player, 1 /*Infantry*/, reinforcements);

        globalTurn++;
        _playerState[player].lastTurnTaken = globalTurn;
        _playerState[player].territoriesOwned = uint32(ownedCount);

        // Track peak territory count for whale cap
        if (ownedCount > _peakTerritories[player]) {
            _peakTerritories[player] = ownedCount;
        }

        emit TurnStarted(player, currentSeason, globalTurn);
    }

    function _calculateReinforcements(address player) internal view returns (uint256) {
        uint256 ownedCount = territoryNFT.territoriesOwnedBy(player);
        uint256 base = ownedCount / 3;
        if (base < 3) base = 3;

        uint256 continentBonus;
        for (uint8 c = 1; c <= 6; ++c) {
            if (territoryNFT.controlsContinent(player, c)) {
                ITerritoryNFT.ContinentMeta memory meta = territoryNFT.getContinentMeta(c);
                continentBonus += meta.bonusArmies;
            }
        }
        return base + continentBonus;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Turn: Reinforce Phase
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IGameEngine
    function reinforce(uint256 territoryId, uint256[] calldata unitTypes, uint256[] calldata amounts)
        external
        nonReentrant
        whenNotPaused
    {
        address player = msg.sender;
        _requirePhase(player, TurnPhase.REINFORCE);
        _requireOwns(player, territoryId);

        uint256 len = unitTypes.length;
        for (uint256 i; i < len; ++i) {
            uint256 uType  = unitTypes[i];
            uint256 amount = amounts[i];
            if (amount == 0) continue;

            // Burn from player wallet
            armyToken.burn(player, uType, amount);

            // Assign to territory
            _armiesAt[territoryId][uType] += amount;

            emit ArmiesReinforced(player, territoryId, uType, amount);
        }
    }

    /// @inheritdoc IGameEngine
    function redeemCards(uint8[3] calldata cardTypes, uint256[3] calldata /*cardIds*/, uint256 bonusTerritoryId)
        external
        nonReentrant
        whenNotPaused
    {
        address player = msg.sender;
        _requirePhase(player, TurnPhase.REINFORCE);

        // Burn set and get bonus armies
        uint256 bonus = territoryCard.burnSet(player, cardTypes);
        setsRedeemedGlobally++;

        // +2 bonus if bonusTerritoryId is owned by player
        uint256 bonusToTerritory;
        if (
            bonusTerritoryId >= 1 &&
            bonusTerritoryId <= TOTAL_TERRITORIES &&
            territoryNFT.ownerOf(bonusTerritoryId) == player
        ) {
            bonusToTerritory = 2;
        }

        // Mint bonus armies as Infantry to player wallet for them to deploy
        armyToken.mint(player, 1 /*Infantry*/, bonus);
        if (bonusToTerritory > 0) {
            armyToken.mint(player, 1 /*Infantry*/, bonusToTerritory);
        }

        emit CardsRedeemed(player, cardTypes, bonus + bonusToTerritory, bonusTerritoryId);
    }

    /// @inheritdoc IGameEngine
    function beginAttackPhase() external whenNotPaused {
        _requirePhase(msg.sender, TurnPhase.REINFORCE);
        _turnPhase[msg.sender] = TurnPhase.ATTACK;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Turn: Attack Phase
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IGameEngine
    function commitAttack(uint256 fromTerritory, uint256 toTerritory, uint8 attackingArmies)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 vrfRequestId)
    {
        address player = msg.sender;
        _requirePhase(player, TurnPhase.ATTACK);
        _requireOwns(player, fromTerritory);

        // Target must NOT be owned by attacker
        address defender = territoryNFT.ownerOf(toTerritory);
        if (defender == player) revert GameEngine__AlreadyOwned(toTerritory);

        // Territories must be adjacent (or naval via Admiral)
        bool adjacent = territoryNFT.isAdjacent(fromTerritory, toTerritory);
        if (!adjacent) {
            // Check naval: only allowed if attacker has an Admiral in fromTerritory
            bool hasAdmiral = _armiesAt[fromTerritory][5] > 0;
            bool isNaval    = _isNavalTarget(fromTerritory, toTerritory);
            if (!hasAdmiral || !isNaval) {
                revert GameEngine__TerritoriesNotAdjacent(fromTerritory, toTerritory);
            }
        }

        // NAP check — cannot attack an ally
        if (hasActiveNAP(player, defender)) {
            revert GameEngine__AttackBlockedByNAP(player, defender);
        }

        // Validate attacking armies count
        uint256 totalStr = _totalStrengthAt(fromTerritory);
        if (totalStr < attackingArmies) {
            revert GameEngine__InsufficientArmies(totalStr, attackingArmies);
        }
        // Max attacking dice: 3, or 4 with General present
        uint8 maxDice = _armiesAt[fromTerritory][4] > 0 ? 4 : 3;
        // Apply betrayal penalty: -1 attack die
        if (globalTurn < _playerState[player].attackPenaltyUntilTurn && maxDice > 1) {
            maxDice--;
        }
        if (attackingArmies > maxDice) attackingArmies = maxDice;
        if (attackingArmies == 0) revert GameEngine__InsufficientArmies(0, 1);

        // Prevent double-attack from same territory while VRF pending
        if (_activeCombatByTerritory[fromTerritory] != 0) {
            revert GameEngine__VRFPending(_activeCombatByTerritory[fromTerritory]);
        }

        // Request VRF
        vrfRequestId = vrfConsumer.requestCombatRandomness(
            player, fromTerritory, toTerritory, attackingArmies
        );

        _pendingCombat[vrfRequestId] = PendingCombat({
            vrfRequestId:    vrfRequestId,
            attacker:        player,
            fromTerritory:   fromTerritory,
            toTerritory:     toTerritory,
            attackingArmies: attackingArmies,
            committedAt:     uint48(block.timestamp),
            resolved:        false
        });

        _activeCombatByTerritory[fromTerritory] = vrfRequestId;

        emit AttackCommitted(player, fromTerritory, toTerritory, attackingArmies, vrfRequestId);
    }

    /// @inheritdoc IGameEngine
    function cancelExpiredAttack(uint256 vrfRequestId) external nonReentrant whenNotPaused {
        PendingCombat storage combat = _pendingCombat[vrfRequestId];
        if (combat.attacker != msg.sender) revert GameEngine__NotTerritoryOwner(msg.sender, vrfRequestId);
        if (combat.resolved) revert GameEngine__AttackExpired(vrfRequestId);

        uint256 expiry = combat.committedAt + ATTACK_TIMEOUT;
        if (block.timestamp < expiry) revert GameEngine__AttackNotExpired(vrfRequestId, expiry);

        vrfConsumer.cancelCombatRequest(vrfRequestId);
        _activeCombatByTerritory[combat.fromTerritory] = 0;
        combat.resolved = true;

        emit AttackExpired(vrfRequestId, msg.sender);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VRF Callback — Combat Resolution
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Called by VRFConsumer when randomness is fulfilled.
    /// @dev Only callable by VRF_CONSUMER_ROLE.
    function resolveCombat(uint256 vrfRequestId, uint256 randomWord)
        external
        onlyRole(VRF_CONSUMER_ROLE)
        nonReentrant
    {
        PendingCombat storage combat = _pendingCombat[vrfRequestId];
        if (combat.resolved) return;
        combat.resolved = true;

        address attacker = combat.attacker;
        uint256 fromT    = combat.fromTerritory;
        uint256 toT      = combat.toTerritory;
        uint8   atkArmies = combat.attackingArmies;

        // Clear active combat lock
        _activeCombatByTerritory[fromT] = 0;

        // Get defender's defending armies (max 2 dice)
        uint256 defStrength = _totalStrengthAt(toT);
        uint8 defArmies = defStrength >= 2 ? 2 : uint8(defStrength);
        if (defArmies == 0) defArmies = 1; // always defend with at least 1 if territory is owned

        // Derive dice from random word: die[i] = ((randomWord >> (i*16)) % 6) + 1
        uint8[] memory atkDice = _deriveDice(randomWord, atkArmies);
        uint8[] memory defDice = _deriveDice(randomWord >> (atkArmies * 16), defArmies);

        // Apply unit effects
        // Cavalry in attacker territory → reroll attacker's lowest die
        if (_armiesAt[fromT][2] > 0 && atkDice.length > 1) {
            atkDice = _rerollLowest(atkDice, randomWord ^ 0xCAVALRY);
        }
        // Artillery in defender territory → reroll defender's lowest die
        if (_armiesAt[toT][3] > 0 && defDice.length > 1) {
            defDice = _rerollLowest(defDice, randomWord ^ 0xARTILLERY);
        }

        // Resolve: sort descending, compare pairs, ties → defender
        (uint8 atkLosses, uint8 defLosses) = _resolveDice(atkDice, defDice);

        emit CombatResolved(vrfRequestId, atkLosses, defLosses, defLosses > atkLosses);

        // Apply losses
        address defender = territoryNFT.ownerOf(toT);
        _applyLosses(fromT, atkLosses);
        _applyLosses(toT,   defLosses);

        // Check conquest
        if (_totalStrengthAt(toT) == 0) {
            // Attacker conquers — advance minimum 1 army
            uint256 advancing = atkArmies > 1 ? atkArmies - 1 : 1;
            // Safety: ensure fromT still has enough armies to leave 1 behind
            uint256 fromStrength = _totalStrengthAt(fromT);
            if (advancing >= fromStrength) advancing = fromStrength - 1;
            if (advancing == 0) advancing = 1;

            _moveArmies(fromT, toT, advancing);
            territoryNFT.conquestTransfer(defender, attacker, toT);
            _conqueredThisTurn[attacker] = true;

            // Update territory counts
            _playerState[attacker].territoriesOwned++;
            if (_playerState[defender].territoriesOwned > 0) {
                _playerState[defender].territoriesOwned--;
            }

            // Update peak territories
            uint256 newCount = _playerState[attacker].territoriesOwned;
            if (newCount > _peakTerritories[attacker]) {
                _peakTerritories[attacker] = newCount;
            }

            emit TerritoryConquered(toT, attacker, defender, advancing);

            // Check world domination
            if (_playerState[attacker].territoriesOwned == TOTAL_TERRITORIES) {
                _endSeason();
                treasuryVault.distributeDominationVictory(
                    currentSeason, attacker, defender, _peakTerritories[attacker]
                );
                emit VictoryDomination(attacker, currentSeason, 0);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Turn: Fortify Phase
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IGameEngine
    function beginFortifyPhase() external whenNotPaused {
        _requirePhase(msg.sender, TurnPhase.ATTACK);
        _turnPhase[msg.sender] = TurnPhase.FORTIFY;
    }

    /// @inheritdoc IGameEngine
    function fortify(uint256 fromTerritory, uint256 toTerritory, uint256 unitType, uint256 amount)
        external
        nonReentrant
        whenNotPaused
    {
        address player = msg.sender;
        _requirePhase(player, TurnPhase.FORTIFY);
        if (_fortifiedThisTurn[player]) revert GameEngine__WrongPhase(TurnPhase.FORTIFY, TurnPhase.ATTACK);

        _requireOwns(player, fromTerritory);
        _requireOwns(player, toTerritory);

        // Territories must be connected (adjacent — simplified: no path-finding through allies)
        if (!territoryNFT.isAdjacent(fromTerritory, toTerritory)) {
            revert GameEngine__TerritoriesNotAdjacent(fromTerritory, toTerritory);
        }

        uint256 available = _armiesAt[fromTerritory][unitType];
        if (available <= amount) revert GameEngine__InsufficientArmies(available, amount + 1); // must leave 1
        if (amount == 0) revert GameEngine__InsufficientArmies(0, 1);

        _armiesAt[fromTerritory][unitType] -= amount;
        _armiesAt[toTerritory][unitType]   += amount;
        _fortifiedThisTurn[player] = true;

        emit ArmiesFortified(player, fromTerritory, toTerritory, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Turn: End
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IGameEngine
    function endTurn() external nonReentrant whenNotPaused {
        address player = msg.sender;
        if (!_activeTurn[player]) revert GameEngine__NotYourTurn(player, player);

        bool drewCard = _conqueredThisTurn[player];
        if (drewCard) {
            // Draw card type derived from block data (low-security — VRF is used for combat;
            // card type is cosmetic and not exploitable for material gain)
            uint8 cardType = uint8((block.prevrandao ^ uint256(uint160(player))) % 3) + 1;
            territoryCard.draw(player, cardType, 0);
        }

        _activeTurn[player]    = false;
        _turnPhase[player]     = TurnPhase.REINFORCE;

        emit TurnEnded(player, globalTurn, drewCard);

        // Check season timer
        if (block.timestamp >= seasonEndsAt) {
            settleTimerVictory();
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Alliance (NAP) System
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IGameEngine
    function proposeAlliance(address ally, uint64 durationInTurns) external whenNotPaused {
        address player = msg.sender;
        _requireActiveGame();
        if (ally == player) revert GameEngine__AllianceNotFound(player, ally);
        if (durationInTurns < MIN_NAP_DURATION) durationInTurns = uint64(MIN_NAP_DURATION);

        // Check betrayal cooldown
        if (globalTurn < _playerState[player].betrayalCooldownUntilTurn) {
            revert GameEngine__AllianceCooldownActive(player, _playerState[player].betrayalCooldownUntilTurn);
        }
        // No existing active alliance
        bytes32 key = _allianceKey(player, ally);
        if (_alliances[key].active) revert GameEngine__AllianceAlreadyExists(player, ally);

        _proposals[player][ally] = globalTurn;
        _proposals[player][ally] = durationInTurns; // reuse for duration — store duration in upper bits
        // Simple storage: store proposal as a mapping with duration embedded
        _storeProposal(player, ally, durationInTurns);
    }

    /// @inheritdoc IGameEngine
    function acceptAlliance(address proposer) external whenNotPaused {
        address player = msg.sender;
        _requireActiveGame();

        // Check betrayal cooldown for acceptor too
        if (globalTurn < _playerState[player].betrayalCooldownUntilTurn) {
            revert GameEngine__AllianceCooldownActive(player, _playerState[player].betrayalCooldownUntilTurn);
        }

        (uint64 proposedAtTurn, uint64 duration) = _loadProposal(proposer, player);
        if (proposedAtTurn == 0) revert GameEngine__AllianceNotFound(proposer, player);
        if (globalTurn > proposedAtTurn + NAP_PROPOSAL_TTL) revert GameEngine__AllianceNotFound(proposer, player);

        bytes32 key = _allianceKey(proposer, player);
        _alliances[key] = Alliance({
            player1:       proposer,
            player2:       player,
            expiresAtTurn: globalTurn + duration,
            active:        true
        });

        _clearProposal(proposer, player);

        emit AllianceFormed(key, proposer, player, globalTurn + duration);
    }

    /// @inheritdoc IGameEngine
    function breakAlliance(address ally) external whenNotPaused {
        address player = msg.sender;
        bytes32 key    = _allianceKey(player, ally);
        Alliance storage a = _alliances[key];
        if (!a.active) revert GameEngine__AllianceNotFound(player, ally);

        a.active = false;

        // Apply betrayal penalties to the breaker
        _playerState[player].betrayalCooldownUntilTurn = globalTurn + BETRAYAL_COOLDOWN;
        _playerState[player].attackPenaltyUntilTurn    = globalTurn + BETRAYAL_PENALTY;

        emit AllianceBroken(key, player, ally);
    }

    /// @inheritdoc IGameEngine
    function getAlliance(address player1, address player2) external view returns (Alliance memory) {
        return _alliances[_allianceKey(player1, player2)];
    }

    /// @inheritdoc IGameEngine
    function hasActiveNAP(address player1, address player2) public view returns (bool) {
        Alliance storage a = _alliances[_allianceKey(player1, player2)];
        return a.active && globalTurn < a.expiresAtTurn;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Inactivity & Abandonment
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IGameEngine
    function flagInactive(address player) external whenNotPaused {
        _requireActiveGame();
        PlayerState storage state = _playerState[player];
        uint256 turnsSinceLast = globalTurn > state.lastTurnTaken
            ? globalTurn - state.lastTurnTaken
            : 0;

        if (turnsSinceLast < INACTIVE_THRESHOLD) revert GameEngine__PlayerNotInactive(player);

        state.missedTurns = uint8(turnsSinceLast < 255 ? turnsSinceLast : 255);
        state.inactive    = true;

        emit PlayerFlaggedInactive(player, currentSeason);
    }

    /// @inheritdoc IGameEngine
    function claimAbandoned(uint256 territoryId) external nonReentrant whenNotPaused {
        _requireActiveGame();
        address owner = territoryNFT.ownerOf(territoryId);
        PlayerState storage state = _playerState[owner];

        if (!state.inactive) revert GameEngine__PlayerNotInactive(owner);

        uint256 turnsSinceLast = globalTurn > state.lastTurnTaken
            ? globalTurn - state.lastTurnTaken
            : 0;
        if (turnsSinceLast < ABANDON_THRESHOLD) {
            revert GameEngine__NotAbandonedYet(owner, uint8(turnsSinceLast));
        }

        // Remove all armies
        for (uint256 t = 1; t <= 5; ++t) {
            _armiesAt[territoryId][t] = 0;
        }

        // Transfer territory to claimant (costs 1 infantry to establish presence)
        // Simplified: claimant gets territory for free; must reinforce on their next turn
        territoryNFT.conquestTransfer(owner, msg.sender, territoryId);
        _playerState[owner].territoriesOwned = state.territoriesOwned > 0 ? state.territoriesOwned - 1 : 0;
        _playerState[msg.sender].territoriesOwned++;

        emit TerritoryAbandoned(territoryId, msg.sender);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Victory Conditions
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IGameEngine
    function claimDomination() external nonReentrant whenNotPaused {
        _requireActiveGame();
        address player = msg.sender;
        if (territoryNFT.territoriesOwnedBy(player) < TOTAL_TERRITORIES) {
            revert GameEngine__WrongSeasonPhase(seasonPhase, SeasonPhase.ENDED);
        }
        _endSeason();
        treasuryVault.distributeDominationVictory(
            currentSeason, player, address(0), _peakTerritories[player]
        );
        emit VictoryDomination(player, currentSeason, 0);
    }

    /// @inheritdoc IGameEngine
    function claimAllianceVictory(address ally) external nonReentrant whenNotPaused {
        _requireActiveGame();
        address player = msg.sender;
        if (!hasActiveNAP(player, ally)) revert GameEngine__AllianceNotFound(player, ally);

        uint256 p1Count = territoryNFT.territoriesOwnedBy(player);
        uint256 p2Count = territoryNFT.territoriesOwnedBy(ally);
        if (p1Count + p2Count < TOTAL_TERRITORIES) {
            revert GameEngine__WrongSeasonPhase(seasonPhase, SeasonPhase.ENDED);
        }

        _endSeason();
        treasuryVault.distributeAllianceVictory(currentSeason, player, ally, p1Count, p2Count);
        emit VictoryAlliance(currentSeason, player, ally, 0, 0);
    }

    /// @inheritdoc IGameEngine
    function settleTimerVictory() public nonReentrant whenNotPaused {
        if (seasonPhase != SeasonPhase.ACTIVE) return;
        if (block.timestamp < seasonEndsAt) return;

        _endSeason();

        // Find top 3 players by territory count
        (address first, address second, address third,
         uint256 c1, uint256 c2, uint256 c3) = _findTop3();

        treasuryVault.distributeTimerVictory(currentSeason, first, second, third, c1, c2, c3);

        emit VictoryTimer(currentSeason, first, second, third, 0, 0, 0);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IGameEngine
    function getPlayerState(address player) external view returns (PlayerState memory) {
        return _playerState[player];
    }

    /// @inheritdoc IGameEngine
    function getPendingCombat(uint256 vrfRequestId) external view returns (PendingCombat memory) {
        return _pendingCombat[vrfRequestId];
    }

    /// @inheritdoc IGameEngine
    function armiesAt(uint256 territoryId, uint256 unitType) external view returns (uint256) {
        return _armiesAt[territoryId][unitType];
    }

    /// @inheritdoc IGameEngine
    function totalStrengthAt(uint256 territoryId) external view returns (uint256) {
        return _totalStrengthAt(territoryId);
    }

    /// @inheritdoc IGameEngine
    function currentPhase(address player) external view returns (TurnPhase) {
        return _turnPhase[player];
    }

    /// @inheritdoc IGameEngine
    function cardSetBonus(uint256 setsRedeemedGlobally_) external pure returns (uint256) {
        if (setsRedeemedGlobally_ >= 7) return 25;
        if (setsRedeemedGlobally_ == 6) return 20;
        if (setsRedeemedGlobally_ == 5) return 15;
        return 4 + setsRedeemedGlobally_ * 2; // base Infantry set, escalated
    }

    /// @inheritdoc IGameEngine
    function areAdjacent(uint256 fromTerritory, uint256 toTerritory) external view returns (bool) {
        return territoryNFT.isAdjacent(fromTerritory, toTerritory);
    }

    /// @inheritdoc IGameEngine
    function canTransfer(uint256 territoryId) external view returns (bool) {
        return territoryNFT.canTransfer(territoryId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal Helpers
    // ─────────────────────────────────────────────────────────────────────────

    function _requireActiveGame() internal view {
        if (seasonPhase != SeasonPhase.ACTIVE) {
            revert GameEngine__WrongSeasonPhase(seasonPhase, SeasonPhase.ACTIVE);
        }
    }

    function _requirePhase(address player, TurnPhase required) internal view {
        if (!_activeTurn[player]) revert GameEngine__NotYourTurn(player, player);
        if (_turnPhase[player] != required) {
            revert GameEngine__WrongPhase(_turnPhase[player], required);
        }
    }

    function _requireOwns(address player, uint256 territoryId) internal view {
        if (territoryNFT.ownerOf(territoryId) != player) {
            revert GameEngine__NotTerritoryOwner(player, territoryId);
        }
    }

    function _totalStrengthAt(uint256 territoryId) internal view returns (uint256 total) {
        // Infantry=1, Cavalry=3, Artillery=5, General=10, Admiral=10
        total  = _armiesAt[territoryId][1] * 1;
        total += _armiesAt[territoryId][2] * 3;
        total += _armiesAt[territoryId][3] * 5;
        total += _armiesAt[territoryId][4] * 10;
        total += _armiesAt[territoryId][5] * 10;
    }

    function _applyLosses(uint256 territoryId, uint8 losses) internal {
        // Remove armies cheapest-first: Infantry → Cavalry → Artillery → General → Admiral
        uint8 remaining = losses;
        for (uint256 t = 1; t <= 5 && remaining > 0; ++t) {
            uint256 available = _armiesAt[territoryId][t];
            if (available == 0) continue;
            uint256 remove = remaining < available ? remaining : available;
            _armiesAt[territoryId][t] -= remove;
            remaining -= uint8(remove);
        }
    }

    function _moveArmies(uint256 fromT, uint256 toT, uint256 count) internal {
        // Move cheapest-first
        uint256 remaining = count;
        for (uint256 t = 1; t <= 5 && remaining > 0; ++t) {
            uint256 available = _armiesAt[fromT][t];
            if (available == 0) continue;
            uint256 move = remaining < available ? remaining : available;
            _armiesAt[fromT][t] -= move;
            _armiesAt[toT][t]   += move;
            remaining -= move;
        }
    }

    function _deriveDice(uint256 seed, uint8 count) internal pure returns (uint8[] memory dice) {
        dice = new uint8[](count);
        for (uint8 i; i < count; ++i) {
            dice[i] = uint8((seed >> (i * 16)) % 6) + 1;
        }
    }

    function _rerollLowest(uint8[] memory dice, uint256 seed) internal pure returns (uint8[] memory) {
        uint8 minIdx;
        for (uint256 i = 1; i < dice.length; ++i) {
            if (dice[i] < dice[minIdx]) minIdx = uint8(i);
        }
        uint8 rerolled = uint8(seed % 6) + 1;
        if (rerolled > dice[minIdx]) dice[minIdx] = rerolled;
        return dice;
    }

    function _resolveDice(uint8[] memory atkDice, uint8[] memory defDice)
        internal
        pure
        returns (uint8 atkLosses, uint8 defLosses)
    {
        // Sort descending (insertion sort — max 4 elements)
        _sortDescMemory(atkDice);
        _sortDescMemory(defDice);

        uint256 comparisons = atkDice.length < defDice.length ? atkDice.length : defDice.length;
        for (uint256 i; i < comparisons; ++i) {
            if (atkDice[i] > defDice[i]) defLosses++;
            else atkLosses++; // tie → defender wins
        }
    }

    function _sortDescMemory(uint8[] memory arr) internal pure {
        for (uint256 i = 1; i < arr.length; ++i) {
            uint8 key = arr[i];
            int256 j  = int256(i) - 1;
            while (j >= 0 && arr[uint256(j)] < key) {
                arr[uint256(j + 1)] = arr[uint256(j)];
                j--;
            }
            arr[uint256(j + 1)] = key;
        }
    }

    function _isNavalTarget(uint256 fromT, uint256 toT) internal view returns (bool) {
        uint256[] memory navals = territoryNFT.navalTargetsOf(fromT);
        for (uint256 i; i < navals.length; ++i) {
            if (navals[i] == toT) return true;
        }
        return false;
    }

    function _endSeason() internal {
        seasonPhase = SeasonPhase.ENDED;
        territoryNFT.unlockAfterSeason(currentSeason);
        territoryCard.setSeasonActive(false);
    }

    function _allianceKey(address a, address b) internal pure returns (bytes32) {
        (address lo, address hi) = a < b ? (a, b) : (b, a);
        return keccak256(abi.encodePacked(lo, hi));
    }

    // Proposal storage: encode (proposedAtTurn, duration) into a single uint256
    mapping(address => mapping(address => uint256)) private _proposalData;

    function _storeProposal(address proposer, address target, uint64 duration) internal {
        _proposalData[proposer][target] = (uint256(globalTurn) << 64) | uint256(duration);
    }

    function _loadProposal(address proposer, address target)
        internal
        view
        returns (uint64 proposedAtTurn, uint64 duration)
    {
        uint256 data = _proposalData[proposer][target];
        duration      = uint64(data & type(uint64).max);
        proposedAtTurn = uint64(data >> 64);
    }

    function _clearProposal(address proposer, address target) internal {
        _proposalData[proposer][target] = 0;
    }

    /// @dev Naive O(n) scan over territory IDs to find top 3 holders.
    ///      With 42 territories this is acceptable.
    function _findTop3()
        internal
        view
        returns (
            address first, address second, address third,
            uint256 c1, uint256 c2, uint256 c3
        )
    {
        // Collect unique owners
        address[42] memory seen;
        uint256 seenCount;

        for (uint256 tid = 1; tid <= TOTAL_TERRITORIES; ++tid) {
            address owner;
            try territoryNFT.ownerOf(tid) returns (address o) { owner = o; }
            catch { continue; }
            if (owner == address(0)) continue;

            bool found;
            for (uint256 k; k < seenCount; ++k) {
                if (seen[k] == owner) { found = true; break; }
            }
            if (!found && seenCount < 42) seen[seenCount++] = owner;
        }

        // Count territories per owner and find top 3
        for (uint256 k; k < seenCount; ++k) {
            uint256 cnt = territoryNFT.territoriesOwnedBy(seen[k]);
            if (cnt > c1)       { third = second; c3 = c2; second = first; c2 = c1; first = seen[k]; c1 = cnt; }
            else if (cnt > c2)  { third = second; c3 = c2; second = seen[k]; c2 = cnt; }
            else if (cnt > c3)  { third = seen[k]; c3 = cnt; }
        }
    }
}
