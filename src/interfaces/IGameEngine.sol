// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IGameEngine
/// @notice Core game logic interface for Base-Conquest.
/// @dev Implements the Risk-inspired turn loop: Reinforce → Attack → Fortify.
///      Combat is resolved asynchronously via Chainlink VRF. Turns are time-gated
///      to one per 24 hours per player. Season lifecycle is managed here.
interface IGameEngine {
    // ─────────────────────────────────────────────────────────────────────────
    // Enums
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice The three ordered phases within a single player turn.
    enum TurnPhase {
        REINFORCE,
        ATTACK,
        FORTIFY
    }

    /// @notice Top-level season lifecycle state.
    enum SeasonPhase {
        INACTIVE, // Before the first auction
        AUCTION, // Territory NFTs are being auctioned (3 days)
        ACTIVE, // Game is live; turns are being taken
        ENDED // Season has concluded; winner claimed or timer expired
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Represents a pending combat awaiting VRF resolution.
    /// @param vrfRequestId   The Chainlink VRF request ID.
    /// @param attacker       Address of the attacking player.
    /// @param fromTerritory  Territory the attack originates from.
    /// @param toTerritory    Territory being attacked.
    /// @param attackingArmies Number of army slots committed to the attack (1-3).
    /// @param committedAt    Block timestamp of the attack commitment.
    /// @param resolved       True once VRF callback has resolved the combat.
    struct PendingCombat {
        uint256 vrfRequestId;
        address attacker;
        uint256 fromTerritory;
        uint256 toTerritory;
        uint8 attackingArmies;
        uint48 committedAt;
        bool resolved;
    }

    /// @notice Represents an on-chain Non-Aggression Pact between two players.
    /// @param player1        First signatory (proposer).
    /// @param player2        Second signatory (acceptor).
    /// @param expiresAtTurn  Global turn number at which the NAP expires naturally.
    /// @param active         False once the NAP is broken or expired.
    struct Alliance {
        address player1;
        address player2;
        uint64 expiresAtTurn;
        bool active;
    }

    /// @notice Per-player state for the current season.
    /// @param territoriesOwned  Count of territories currently owned.
    /// @param lastTurnTaken     Global turn number of the player's last completed turn.
    /// @param missedTurns       Consecutive turns missed (resets to 0 on activity).
    /// @param betrayalCooldownUntilTurn  Cannot form alliances until this global turn.
    /// @param attackPenaltyUntilTurn     -1 attack die applied until this global turn.
    /// @param drewCardThisTurn  True if the player already conquered a territory this turn.
    /// @param inactive          True if the player has missed 3+ consecutive turns.
    struct PlayerState {
        uint32 territoriesOwned;
        uint64 lastTurnTaken;
        uint8 missedTurns;
        uint64 betrayalCooldownUntilTurn;
        uint64 attackPenaltyUntilTurn;
        bool drewCardThisTurn;
        bool inactive;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when a new season auction begins.
    event SeasonStarted(uint256 indexed seasonId, uint256 auctionEndsAt);

    /// @notice Emitted when the auction phase ends and the game becomes active.
    event GameActivated(uint256 indexed seasonId, uint256 seasonEndsAt);

    /// @notice Emitted at the start of a player's turn.
    event TurnStarted(address indexed player, uint256 indexed seasonId, uint64 globalTurn);

    /// @notice Emitted when armies are deployed to a territory during Reinforce.
    event ArmiesReinforced(
        address indexed player, uint256 indexed territoryId, uint256 unitType, uint256 amount
    );

    /// @notice Emitted when a player redeems territory cards for bonus armies.
    event CardsRedeemed(
        address indexed player,
        uint8[3] cardTypes,
        uint256 bonusArmies,
        uint256 indexed bonusTerritoryId
    );

    /// @notice Emitted when a player commits an attack (before VRF resolves).
    event AttackCommitted(
        address indexed attacker,
        uint256 indexed fromTerritory,
        uint256 indexed toTerritory,
        uint8 attackingArmies,
        uint256 vrfRequestId
    );

    /// @notice Emitted when Chainlink VRF resolves a combat round.
    event CombatResolved(
        uint256 indexed vrfRequestId,
        uint8 attackerLosses,
        uint8 defenderLosses,
        bool attackerWon
    );

    /// @notice Emitted when an attacker captures a territory.
    event TerritoryConquered(
        uint256 indexed territoryId,
        address indexed newOwner,
        address indexed previousOwner,
        uint256 advancingArmies
    );

    /// @notice Emitted when an expired attack is cancelled and armies returned.
    event AttackExpired(uint256 indexed vrfRequestId, address indexed attacker);

    /// @notice Emitted when armies are moved during Fortify phase.
    event ArmiesFortified(
        address indexed player,
        uint256 indexed fromTerritory,
        uint256 indexed toTerritory,
        uint256 amount
    );

    /// @notice Emitted at the end of a player's turn.
    event TurnEnded(address indexed player, uint64 globalTurn, bool drewCard);

    /// @notice Emitted when a Non-Aggression Pact is formed.
    event AllianceFormed(
        bytes32 indexed allianceId, address indexed player1, address indexed player2, uint64 expiresAtTurn
    );

    /// @notice Emitted when a NAP is broken before its natural expiry.
    event AllianceBroken(bytes32 indexed allianceId, address indexed breaker, address indexed victim);

    /// @notice Emitted when a player is flagged inactive after 3 missed turns.
    event PlayerFlaggedInactive(address indexed player, uint256 indexed seasonId);

    /// @notice Emitted when an abandoned territory is claimed by another player.
    event TerritoryAbandoned(uint256 indexed territoryId, address indexed claimant);

    /// @notice Emitted when a player achieves World Domination.
    event VictoryDomination(address indexed winner, uint256 indexed seasonId, uint256 prizeAmount);

    /// @notice Emitted when the season timer expires and rankings determine payouts.
    event VictoryTimer(
        uint256 indexed seasonId,
        address indexed first,
        address indexed second,
        address third,
        uint256 firstPrize,
        uint256 secondPrize,
        uint256 thirdPrize
    );

    /// @notice Emitted when two allied players share a victory.
    event VictoryAlliance(
        uint256 indexed seasonId,
        address indexed player1,
        address indexed player2,
        uint256 player1Prize,
        uint256 player2Prize
    );

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error GameEngine__NotYourTurn(address caller, address expectedPlayer);
    error GameEngine__WrongPhase(TurnPhase current, TurnPhase required);
    error GameEngine__WrongSeasonPhase(SeasonPhase current, SeasonPhase required);
    error GameEngine__NotTerritoryOwner(address caller, uint256 territoryId);
    error GameEngine__TerritoriesNotAdjacent(uint256 from, uint256 to);
    error GameEngine__AlreadyOwned(uint256 territoryId);
    error GameEngine__InsufficientArmies(uint256 available, uint256 required);
    error GameEngine__AttackBlockedByNAP(address attacker, address defender);
    error GameEngine__AllianceCooldownActive(address player, uint64 cooldownUntilTurn);
    error GameEngine__VRFPending(uint256 vrfRequestId);
    error GameEngine__AttackExpired(uint256 vrfRequestId);
    error GameEngine__AttackNotExpired(uint256 vrfRequestId, uint256 expiresAt);
    error GameEngine__PlayerNotInactive(address player);
    error GameEngine__NotAbandonedYet(address player, uint8 missedTurns);
    error GameEngine__TurnCooldownActive(address player, uint256 nextTurnAt);
    error GameEngine__SeasonAlreadyEnded(uint256 seasonId);
    error GameEngine__MaxTerritoriesAtAuction(address player, uint256 cap);
    error GameEngine__InvalidCardSet(uint8[3] cardTypes);
    error GameEngine__AllianceAlreadyExists(address player1, address player2);
    error GameEngine__AllianceNotFound(address player1, address player2);
    error GameEngine__AdvancingArmiesBelowMinimum(uint256 provided, uint256 minimum);

    // ─────────────────────────────────────────────────────────────────────────
    // Season Management
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Starts a new season auction. Mints 42 territory NFTs for bidding.
    /// @dev Only callable by GAME_MASTER_ROLE. Reverts if a season is already active.
    function startSeason() external;

    /// @notice Transitions from AUCTION to ACTIVE once the auction window closes.
    /// @dev Callable by anyone after the auction deadline. Sets `seasonEndsAt`.
    function activateSeason() external;

    /// @notice Returns the current season ID (1-indexed).
    function currentSeason() external view returns (uint256);

    /// @notice Returns the current global turn number across all players.
    function globalTurn() external view returns (uint64);

    /// @notice Returns the current top-level season phase.
    function seasonPhase() external view returns (SeasonPhase);

    // ─────────────────────────────────────────────────────────────────────────
    // Turn Phases
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Begins the caller's turn. Calculates and grants reinforcement armies.
    /// @dev Reverts if the caller already took a turn in the last 24 hours.
    ///      Armies are calculated as max(3, floor(territoriesOwned / 3)) + continent bonuses.
    ///      Automatically awards bonus armies if pending card sets were auto-submitted.
    function startTurn() external;

    /// @notice Deploys army units from the caller's wallet to a territory they own.
    /// @dev Only callable during REINFORCE phase of the caller's active turn.
    ///      Army tokens are transferred from caller to the territory's on-chain escrow.
    /// @param territoryId  Territory to reinforce.
    /// @param unitTypes    Array of unit type IDs (1=Infantry, 2=Cavalry, 3=Artillery, 4=General, 5=Admiral).
    /// @param amounts      Corresponding amounts for each unit type.
    function reinforce(uint256 territoryId, uint256[] calldata unitTypes, uint256[] calldata amounts) external;

    /// @notice Redeems a set of three territory cards for bonus armies during Reinforce.
    /// @dev Burns the three cards. Applies global escalation to bonus armies.
    ///      If `bonusTerritoryId` matches a territory depicted on one of the cards and
    ///      the caller owns it, grants +2 additional armies to that territory.
    /// @param cardTypes         Three card type values (1=Infantry, 2=Cavalry, 3=Artillery).
    /// @param cardIds           Token IDs of the three cards to burn.
    /// @param bonusTerritoryId  Territory to receive the optional +2 bonus armies.
    function redeemCards(uint8[3] calldata cardTypes, uint256[3] calldata cardIds, uint256 bonusTerritoryId)
        external;

    /// @notice Advances the caller's turn from REINFORCE to ATTACK phase.
    function beginAttackPhase() external;

    /// @notice Commits an attack against an adjacent territory. Requests VRF randomness.
    /// @dev Caller must own `fromTerritory` and must NOT own `toTerritory`.
    ///      Territories must be adjacent (or naval via Admiral unit).
    ///      Attacks against NAP partners revert.
    ///      The committed armies are locked until VRF resolves or attack expires.
    /// @param fromTerritory   Territory initiating the attack.
    /// @param toTerritory     Territory being attacked.
    /// @param attackingArmies Number of army slots to commit (1–3, or up to 4 with General).
    /// @return vrfRequestId   The VRF request ID for tracking this combat.
    function commitAttack(uint256 fromTerritory, uint256 toTerritory, uint8 attackingArmies)
        external
        returns (uint256 vrfRequestId);

    /// @notice Cancels an attack whose VRF window has expired (>24 hours without callback).
    /// @dev Returns committed armies to the territory. Callable by the attacker only.
    /// @param vrfRequestId  The expired VRF request ID.
    function cancelExpiredAttack(uint256 vrfRequestId) external;

    /// @notice Advances the caller's turn from ATTACK to FORTIFY phase.
    function beginFortifyPhase() external;

    /// @notice Moves armies between two territories the caller owns that are connected.
    /// @dev Only one fortify move per turn. Allies' territories count as passable
    ///      for connection purposes if an active NAP exists.
    ///      At least 1 army must remain in `fromTerritory`.
    /// @param fromTerritory  Territory to move armies from.
    /// @param toTerritory    Territory to move armies to.
    /// @param unitType       Unit type to move.
    /// @param amount         Number of units to move.
    function fortify(uint256 fromTerritory, uint256 toTerritory, uint256 unitType, uint256 amount) external;

    /// @notice Ends the caller's turn. Issues a territory card if they conquered this turn.
    /// @dev Advances the global turn counter. Checks for inactivity on other players.
    function endTurn() external;

    // ─────────────────────────────────────────────────────────────────────────
    // Alliance (NAP) System
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Proposes a Non-Aggression Pact with another player.
    /// @dev Stores the proposal on-chain. The counterparty must call `acceptAlliance`
    ///      within 3 turns or the proposal expires.
    ///      Reverts if the caller is under a betrayal cooldown.
    /// @param ally              Address of the proposed ally.
    /// @param durationInTurns   How many global turns the NAP should last (minimum 5).
    function proposeAlliance(address ally, uint64 durationInTurns) external;

    /// @notice Accepts a pending alliance proposal from `proposer`.
    /// @dev Both players are now bound by the NAP for `durationInTurns`.
    /// @param proposer  Address who called `proposeAlliance`.
    function acceptAlliance(address proposer) external;

    /// @notice Breaks an active NAP before its natural expiry. Applies betrayal penalty.
    /// @dev The caller receives a 5-turn alliance cooldown and a -1 attack die
    ///      penalty for 3 turns.
    /// @param ally  Address of the NAP partner being betrayed.
    function breakAlliance(address ally) external;

    /// @notice Returns the Alliance struct for two players (order-independent).
    function getAlliance(address player1, address player2) external view returns (Alliance memory);

    /// @notice Returns true if an active NAP exists between the two players.
    function hasActiveNAP(address player1, address player2) external view returns (bool);

    // ─────────────────────────────────────────────────────────────────────────
    // Inactivity & Abandonment
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Flags a player as inactive after they miss 3 consecutive turns.
    /// @dev Callable by anyone. Reverts if the player has not missed 3+ turns.
    ///      Inactive players' territories lose their defense bonus.
    /// @param player  Address to flag.
    function flagInactive(address player) external;

    /// @notice Claims a territory from a player who has been inactive for 10+ turns.
    /// @dev Removes all armies from the territory. Territory becomes capturable by all.
    ///      Does not directly transfer ownership — leaves territory army-less and ownerless.
    /// @param territoryId  Territory to claim as abandoned.
    function claimAbandoned(uint256 territoryId) external;

    // ─────────────────────────────────────────────────────────────────────────
    // Victory Conditions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Claims World Domination victory. Caller must own all 42 territories.
    /// @dev Transfers 80% of prize pool to caller. Rolls 20% to next season.
    ///      Emits VictoryDomination and ends the season.
    function claimDomination() external;

    /// @notice Claims a shared alliance victory when allies together own all 42 territories.
    /// @dev Caller and `ally` must together own all territories and have an active NAP.
    ///      Prize is split proportionally by territory count.
    /// @param ally  The allied player sharing the victory.
    function claimAllianceVictory(address ally) external;

    /// @notice Settles the season by rank when the timer expires. Callable by anyone.
    /// @dev Distributes prize pool 60% / 25% / 15% to top 3 territory holders.
    ///      Tiebreak: longest-held territory wins.
    function settleTimerVictory() external;

    // ─────────────────────────────────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns the PlayerState for a given address in the current season.
    function getPlayerState(address player) external view returns (PlayerState memory);

    /// @notice Returns the PendingCombat struct for a given VRF request ID.
    function getPendingCombat(uint256 vrfRequestId) external view returns (PendingCombat memory);

    /// @notice Returns the number of army units of a given type stationed at a territory.
    function armiesAt(uint256 territoryId, uint256 unitType) external view returns (uint256);

    /// @notice Returns the total army strength (in Infantry equivalents) at a territory.
    function totalStrengthAt(uint256 territoryId) external view returns (uint256);

    /// @notice Returns the current phase of the caller's active turn.
    function currentPhase(address player) external view returns (TurnPhase);

    /// @notice Returns the Unix timestamp at which the current season ends.
    function seasonEndsAt() external view returns (uint256);

    /// @notice Returns the globally escalated bonus armies for the Nth card set redeemed.
    /// @param setsRedeemedGlobally  Total number of sets turned in across all players so far.
    function cardSetBonus(uint256 setsRedeemedGlobally) external pure returns (uint256 bonusArmies);

    /// @notice Returns true if `fromTerritory` and `toTerritory` are adjacent on the map.
    function areAdjacent(uint256 fromTerritory, uint256 toTerritory) external view returns (bool);

    /// @notice Returns true if `player` can transfer `territoryId` (used by TerritoryNFT._update).
    function canTransfer(uint256 territoryId) external view returns (bool);
}
