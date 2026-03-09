// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ITreasuryVault
/// @notice Interface for the Base-Conquest prize pool and protocol treasury.
/// @dev Holds ETH collected from season territory auctions and distributes prizes.
///
///      Prize pool funding:
///      - Territory NFT auction proceeds are sent via `receiveAuctionProceeds`
///      - 2% royalty on secondary territory NFT sales is routed here
///
///      Prize distribution:
///      - World Domination victory: 80% to winner, 20% rolls to next season
///      - Season timer victory: 60% / 25% / 15% to top 3 territory holders
///      - Alliance victory: split proportionally by territory count between two allies
///
///      Whale cap: if a domination winner held >35 territories at any point in the season,
///      their payout is capped at 40% of the prize pool; excess goes to 2nd place holder.
///
///      All ETH movements emit events for The Graph indexing.
interface ITreasuryVault {
    // ─────────────────────────────────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Tracks the prize pool balance per season.
    /// @param seasonId        The season ID this pool belongs to.
    /// @param totalDeposited  Total ETH deposited (auction proceeds + rollovers).
    /// @param distributed     Total ETH distributed to winners.
    /// @param rolledOver      Amount rolled over to the next season (domination 20% share).
    struct SeasonPool {
        uint256 seasonId;
        uint256 totalDeposited;
        uint256 distributed;
        uint256 rolledOver;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when ETH from an auction sale is deposited into the prize pool.
    event AuctionProceedsReceived(uint256 indexed seasonId, uint256 amount, address indexed from);

    /// @notice Emitted when royalty ETH is deposited into the treasury.
    event RoyaltyReceived(uint256 indexed seasonId, uint256 amount, uint256 indexed territoryId);

    /// @notice Emitted when the domination winner is paid.
    event DominationPrizePaid(uint256 indexed seasonId, address indexed winner, uint256 amount);

    /// @notice Emitted when the 20% domination rollover is credited to the next season.
    event DominationRolledOver(uint256 indexed fromSeason, uint256 indexed toSeason, uint256 amount);

    /// @notice Emitted when timer victory prizes are distributed.
    event TimerPrizePaid(
        uint256 indexed seasonId,
        address indexed first,
        address indexed second,
        address third,
        uint256 firstAmount,
        uint256 secondAmount,
        uint256 thirdAmount
    );

    /// @notice Emitted when an alliance victory prize is split.
    event AlliancePrizePaid(
        uint256 indexed seasonId,
        address indexed player1,
        address indexed player2,
        uint256 player1Amount,
        uint256 player2Amount
    );

    /// @notice Emitted when a whale cap reduces a domination payout.
    event WhaleCapApplied(
        uint256 indexed seasonId,
        address indexed winner,
        uint256 cappedAmount,
        uint256 excessTo2ndPlace
    );

    /// @notice Emitted when the protocol fee is withdrawn by the admin multisig.
    event ProtocolFeeWithdrawn(address indexed to, uint256 amount);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error TreasuryVault__NotGameEngine(address caller);
    error TreasuryVault__NotAdmin(address caller);
    error TreasuryVault__SeasonPoolEmpty(uint256 seasonId);
    error TreasuryVault__AlreadyDistributed(uint256 seasonId);
    error TreasuryVault__ZeroAddress();
    error TreasuryVault__TransferFailed(address to, uint256 amount);
    error TreasuryVault__InsufficientBalance(uint256 available, uint256 required);

    // ─────────────────────────────────────────────────────────────────────────
    // Deposits (called by auction contract and royalty router)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Deposits ETH auction proceeds into the current season's prize pool.
    /// @dev Only callable by the Auction contract (DEPOSITOR_ROLE).
    ///      ETH is sent as `msg.value`. Emits AuctionProceedsReceived.
    /// @param seasonId  The season this deposit belongs to.
    function receiveAuctionProceeds(uint256 seasonId) external payable;

    /// @notice Deposits ETH from a territory NFT secondary sale royalty.
    /// @dev Only callable by the royalty router (DEPOSITOR_ROLE).
    ///      2% of sale price flows here. ETH sent as `msg.value`.
    /// @param seasonId    Current active season.
    /// @param territoryId Territory whose secondary sale generated this royalty.
    function receiveRoyalty(uint256 seasonId, uint256 territoryId) external payable;

    // ─────────────────────────────────────────────────────────────────────────
    // Prize Distribution (GameEngine only)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Distributes the prize pool for a World Domination victory.
    /// @dev Only callable by GameEngine (GAME_ENGINE_ROLE).
    ///      Pays 80% to `winner` (subject to whale cap) and rolls 20% to next season.
    ///      If whale cap applies (winner held >35 territories), excess goes to `secondPlace`.
    ///      Reverts if the pool has already been distributed for this season.
    /// @param seasonId         The season being settled.
    /// @param winner           Address of the domination winner.
    /// @param secondPlace      Address of the 2nd place holder (receives excess if whale cap applies).
    /// @param winnerPeakTerritories  Max territories the winner held at any point this season.
    function distributeDominationVictory(
        uint256 seasonId,
        address winner,
        address secondPlace,
        uint256 winnerPeakTerritories
    ) external;

    /// @notice Distributes the prize pool for a Season Timer victory.
    /// @dev Only callable by GameEngine. Pays 60% / 25% / 15% to top 3.
    ///      Any of second/third may be address(0) if fewer than 3 players participated;
    ///      their share is rolled to the next season in that case.
    /// @param seasonId            The season being settled.
    /// @param first               1st place address (most territories).
    /// @param second              2nd place address.
    /// @param third               3rd place address.
    /// @param firstTerritories    Territory count for 1st place (used for proportional logging).
    /// @param secondTerritories   Territory count for 2nd place.
    /// @param thirdTerritories    Territory count for 3rd place.
    function distributeTimerVictory(
        uint256 seasonId,
        address first,
        address second,
        address third,
        uint256 firstTerritories,
        uint256 secondTerritories,
        uint256 thirdTerritories
    ) external;

    /// @notice Distributes the prize pool for a shared Alliance victory.
    /// @dev Only callable by GameEngine. Splits proportionally by territory count.
    ///      Neither address may be address(0).
    /// @param seasonId           The season being settled.
    /// @param player1            First ally.
    /// @param player2            Second ally.
    /// @param player1Territories Territories held by player1 at time of victory claim.
    /// @param player2Territories Territories held by player2 at time of victory claim.
    function distributeAllianceVictory(
        uint256 seasonId,
        address player1,
        address player2,
        uint256 player1Territories,
        uint256 player2Territories
    ) external;

    // ─────────────────────────────────────────────────────────────────────────
    // Admin Functions (DEFAULT_ADMIN_ROLE / multisig)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Withdraws accumulated protocol fees (royalty share) to the admin multisig.
    /// @dev Only callable by DEFAULT_ADMIN_ROLE. Does not touch the prize pool balance.
    /// @param to      Destination address (should be Gnosis Safe).
    /// @param amount  ETH amount to withdraw.
    function withdrawProtocolFees(address to, uint256 amount) external;

    // ─────────────────────────────────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns the SeasonPool struct for a given season ID.
    function getSeasonPool(uint256 seasonId) external view returns (SeasonPool memory);

    /// @notice Returns the current undistributed prize pool balance for a season.
    function prizePoolBalance(uint256 seasonId) external view returns (uint256);

    /// @notice Returns the total ETH held in the contract (prize pool + protocol fees).
    function totalBalance() external view returns (uint256);

    /// @notice Returns the protocol fee balance (royalties not yet withdrawn).
    function protocolFeeBalance() external view returns (uint256);

    /// @notice Returns the whale cap threshold (territories). Default: 35.
    function whaleCapThreshold() external view returns (uint256);

    /// @notice Returns the whale cap maximum prize percentage (basis points). Default: 4000 (40%).
    function whaleCapBps() external view returns (uint256);

    /// @notice Returns the domination rollover percentage in basis points. Default: 2000 (20%).
    function dominationRolloverBps() external view returns (uint256);

    /// @notice Returns the timer victory split in basis points: [first, second, third].
    function timerVictorySplitBps() external view returns (uint256[3] memory);
}
