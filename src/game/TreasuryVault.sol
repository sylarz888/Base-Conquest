// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ITreasuryVault} from "../interfaces/ITreasuryVault.sol";

/// @title TreasuryVault
/// @notice Holds ETH prize pools and distributes season winnings.
/// @dev Separates prize pool balance (season-specific) from protocol fees (royalties).
///      All ETH transfers use low-level call to handle smart contract wallets.
contract TreasuryVault is ITreasuryVault, AccessControl, ReentrancyGuard {
    // ── Roles ─────────────────────────────────────────────────────────────────
    bytes32 public constant GAME_ENGINE_ROLE = keccak256("GAME_ENGINE_ROLE");
    bytes32 public constant DEPOSITOR_ROLE   = keccak256("DEPOSITOR_ROLE");

    // ── Default split parameters ──────────────────────────────────────────────
    uint256 private constant _BPS = 10_000;
    uint256 private _dominationRolloverBps  = 2_000; // 20%
    uint256 private _whaleCapThreshold      = 35;    // territories
    uint256 private _whaleCapBps            = 4_000; // 40% max payout
    uint256[3] private _timerSplitBps       = [6_000, 2_500, 1_500]; // 60/25/15

    // ── Per-season prize pools ────────────────────────────────────────────────
    mapping(uint256 => SeasonPool) private _pools;
    mapping(uint256 => bool)       private _distributed;

    // ── Protocol fee balance (royalties, separate from prize pools) ───────────
    uint256 private _protocolFees;

    // ── Rollover staging (from domination 20%) ────────────────────────────────
    mapping(uint256 => uint256) private _pendingRollovers; // toSeasonId => amount

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Deposits
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc ITreasuryVault
    function receiveAuctionProceeds(uint256 seasonId) external payable onlyRole(DEPOSITOR_ROLE) {
        // Credit any pending rollover from prior season
        uint256 rollover = _pendingRollovers[seasonId];
        if (rollover > 0) {
            _pendingRollovers[seasonId] = 0;
            _pools[seasonId].totalDeposited += rollover;
        }

        _pools[seasonId].seasonId      = seasonId;
        _pools[seasonId].totalDeposited += msg.value;

        emit AuctionProceedsReceived(seasonId, msg.value, msg.sender);
    }

    /// @inheritdoc ITreasuryVault
    function receiveRoyalty(uint256 seasonId, uint256 territoryId) external payable onlyRole(DEPOSITOR_ROLE) {
        // Split: 2% treasury fee goes to protocol, 3% to season prize pool
        // msg.value here is already the 5% royalty amount; caller splits it correctly
        // For simplicity: GameEngine sends 100% here and we split internally
        uint256 toProtocol = msg.value * 2 / 5; // 40% of royalty = 2% of sale
        uint256 toPrize    = msg.value - toProtocol;

        _protocolFees += toProtocol;
        _pools[seasonId].totalDeposited += toPrize;

        emit RoyaltyReceived(seasonId, msg.value, territoryId);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Prize Distribution
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc ITreasuryVault
    function distributeDominationVictory(
        uint256 seasonId,
        address winner,
        address secondPlace,
        uint256 winnerPeakTerritories
    ) external onlyRole(GAME_ENGINE_ROLE) nonReentrant {
        _checkNotDistributed(seasonId);
        _distributed[seasonId] = true;

        SeasonPool storage pool = _pools[seasonId];
        uint256 total = pool.totalDeposited - pool.distributed;
        if (total == 0) revert TreasuryVault__SeasonPoolEmpty(seasonId);

        uint256 rolloverAmount = (total * _dominationRolloverBps) / _BPS;
        uint256 winnerAmount   = total - rolloverAmount;

        // Apply whale cap
        uint256 whaleCap = (total * _whaleCapBps) / _BPS;
        if (winnerPeakTerritories > _whaleCapThreshold && winnerAmount > whaleCap) {
            uint256 excess = winnerAmount - whaleCap;
            winnerAmount   = whaleCap;
            pool.distributed += excess;
            emit WhaleCapApplied(seasonId, winner, winnerAmount, excess);
            // Excess goes to second place
            if (secondPlace != address(0)) {
                pool.distributed += excess;
                _sendEth(secondPlace, excess, seasonId);
            } else {
                rolloverAmount += excess; // no second place → rollover
            }
        }

        pool.distributed  += winnerAmount;
        pool.rolledOver   += rolloverAmount;

        _pendingRollovers[seasonId + 1] += rolloverAmount;

        _sendEth(winner, winnerAmount, seasonId);

        emit DominationPrizePaid(seasonId, winner, winnerAmount);
        emit DominationRolledOver(seasonId, seasonId + 1, rolloverAmount);
    }

    /// @inheritdoc ITreasuryVault
    function distributeTimerVictory(
        uint256 seasonId,
        address first,
        address second,
        address third,
        uint256 firstTerritories,
        uint256 secondTerritories,
        uint256 thirdTerritories
    ) external onlyRole(GAME_ENGINE_ROLE) nonReentrant {
        _checkNotDistributed(seasonId);
        _distributed[seasonId] = true;

        SeasonPool storage pool = _pools[seasonId];
        uint256 total = pool.totalDeposited - pool.distributed;
        if (total == 0) revert TreasuryVault__SeasonPoolEmpty(seasonId);

        uint256 firstAmount  = (total * _timerSplitBps[0]) / _BPS;
        uint256 secondAmount = (total * _timerSplitBps[1]) / _BPS;
        uint256 thirdAmount  = total - firstAmount - secondAmount;

        pool.distributed += total;

        // Pay first (always present)
        _sendEth(first, firstAmount, seasonId);

        // Pay second (if exists, else rollover)
        if (second != address(0)) {
            _sendEth(second, secondAmount, seasonId);
        } else {
            _pendingRollovers[seasonId + 1] += secondAmount;
            pool.rolledOver += secondAmount;
        }

        // Pay third (if exists, else rollover)
        if (third != address(0)) {
            _sendEth(third, thirdAmount, seasonId);
        } else {
            _pendingRollovers[seasonId + 1] += thirdAmount;
            pool.rolledOver += thirdAmount;
        }

        emit TimerPrizePaid(seasonId, first, second, third, firstAmount, secondAmount, thirdAmount);
    }

    /// @inheritdoc ITreasuryVault
    function distributeAllianceVictory(
        uint256 seasonId,
        address player1,
        address player2,
        uint256 player1Territories,
        uint256 player2Territories
    ) external onlyRole(GAME_ENGINE_ROLE) nonReentrant {
        if (player1 == address(0) || player2 == address(0)) revert TreasuryVault__ZeroAddress();
        _checkNotDistributed(seasonId);
        _distributed[seasonId] = true;

        SeasonPool storage pool = _pools[seasonId];
        uint256 total = pool.totalDeposited - pool.distributed;
        if (total == 0) revert TreasuryVault__SeasonPoolEmpty(seasonId);

        uint256 totalTerritories = player1Territories + player2Territories;
        uint256 player1Amount    = totalTerritories > 0
            ? (total * player1Territories) / totalTerritories
            : total / 2;
        uint256 player2Amount    = total - player1Amount;

        pool.distributed += total;

        _sendEth(player1, player1Amount, seasonId);
        _sendEth(player2, player2Amount, seasonId);

        emit AlliancePrizePaid(seasonId, player1, player2, player1Amount, player2Amount);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc ITreasuryVault
    function withdrawProtocolFees(address to, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        if (to == address(0)) revert TreasuryVault__ZeroAddress();
        if (amount > _protocolFees) {
            revert TreasuryVault__InsufficientBalance(_protocolFees, amount);
        }
        _protocolFees -= amount;
        _sendEth(to, amount, 0);
        emit ProtocolFeeWithdrawn(to, amount);
    }

    function setDominationRolloverBps(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bps <= _BPS, "TreasuryVault: overflow");
        _dominationRolloverBps = bps;
    }

    function setWhaleCapThreshold(uint256 threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _whaleCapThreshold = threshold;
    }

    function setWhaleCapBps(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bps <= _BPS, "TreasuryVault: overflow");
        _whaleCapBps = bps;
    }

    function setTimerSplitBps(uint256[3] calldata splits) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(splits[0] + splits[1] + splits[2] == _BPS, "TreasuryVault: splits must sum to 10000");
        _timerSplitBps = splits;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc ITreasuryVault
    function getSeasonPool(uint256 seasonId) external view returns (SeasonPool memory) {
        return _pools[seasonId];
    }

    /// @inheritdoc ITreasuryVault
    function prizePoolBalance(uint256 seasonId) external view returns (uint256) {
        SeasonPool storage pool = _pools[seasonId];
        return pool.totalDeposited - pool.distributed;
    }

    /// @inheritdoc ITreasuryVault
    function totalBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @inheritdoc ITreasuryVault
    function protocolFeeBalance() external view returns (uint256) {
        return _protocolFees;
    }

    /// @inheritdoc ITreasuryVault
    function whaleCapThreshold() external view returns (uint256) { return _whaleCapThreshold; }

    /// @inheritdoc ITreasuryVault
    function whaleCapBps() external view returns (uint256) { return _whaleCapBps; }

    /// @inheritdoc ITreasuryVault
    function dominationRolloverBps() external view returns (uint256) { return _dominationRolloverBps; }

    /// @inheritdoc ITreasuryVault
    function timerVictorySplitBps() external view returns (uint256[3] memory) {
        return _timerSplitBps;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Internal
    // ─────────────────────────────────────────────────────────────────────────

    function _checkNotDistributed(uint256 seasonId) internal view {
        if (_distributed[seasonId]) revert TreasuryVault__AlreadyDistributed(seasonId);
    }

    function _sendEth(address to, uint256 amount, uint256 /*seasonId*/) internal {
        if (amount == 0) return;
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TreasuryVault__TransferFailed(to, amount);
    }

    receive() external payable {}
}
