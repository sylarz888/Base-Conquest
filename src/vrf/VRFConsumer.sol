// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/libraries/VRFV2PlusClient.sol";
import {IVRFConsumer} from "../interfaces/IVRFConsumer.sol";

/// @title VRFConsumer
/// @notice Wraps Chainlink VRF v2.5 for Base-Conquest combat randomness.
/// @dev One VRF request per attack. The returned uint256 is used to derive up to 5 dice:
///        die[i] = uint8((randomWord >> (i * 16)) % 6) + 1   for i in [0..4]
///
///      On fulfillment, calls back into GameEngine.resolveCombat(requestId, randomWord).
///
///      If VRF never fulfills (LINK shortage or gas limit exceeded), the attacker may
///      call GameEngine.cancelExpiredAttack after a 24-hour timeout.
contract VRFConsumer is IVRFConsumer, VRFConsumerBaseV2Plus {
    // ── Constants ─────────────────────────────────────────────────────────────
    uint256 public constant TIMEOUT_DURATION = 24 hours;
    uint16  public constant REQUEST_CONFIRMATIONS = 3;
    uint32  public constant NUM_WORDS = 1; // one uint256 → 5 dice

    // ── Config ────────────────────────────────────────────────────────────────
    uint256 private immutable _subscriptionId;
    bytes32 private immutable _keyHash;
    uint32  private _callbackGasLimit;

    // ── GameEngine reference ──────────────────────────────────────────────────
    address private _gameEngine;

    // ── Pending requests ──────────────────────────────────────────────────────
    mapping(uint256 => CombatRequest) private _requests;
    mapping(uint256 => bool) private _cancelled;

    // ── Interface for calling back into GameEngine ────────────────────────────
    // We define a minimal callback interface to avoid a circular import
    interface IGameEngineCallback {
        function resolveCombat(uint256 vrfRequestId, uint256 randomWord) external;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────

    constructor(
        address vrfCoordinator,
        uint256 subscriptionId_,
        bytes32 keyHash_,
        uint32  callbackGasLimit_,
        address gameEngine_
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        _subscriptionId   = subscriptionId_;
        _keyHash          = keyHash_;
        _callbackGasLimit = callbackGasLimit_;
        _gameEngine       = gameEngine_;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Request (GameEngine only)
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IVRFConsumer
    function requestCombatRandomness(
        address attacker,
        uint256 fromTerritory,
        uint256 toTerritory,
        uint8   attackingArmies
    ) external returns (uint256 vrfRequestId) {
        if (msg.sender != _gameEngine) revert VRFConsumer__NotGameEngine(msg.sender);

        vrfRequestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash:             _keyHash,
                subId:               _subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit:    _callbackGasLimit,
                numWords:            NUM_WORDS,
                extraArgs:           VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );

        _requests[vrfRequestId] = CombatRequest({
            attacker:        attacker,
            fromTerritory:   fromTerritory,
            toTerritory:     toTerritory,
            attackingArmies: attackingArmies,
            requestedAt:     uint48(block.timestamp),
            fulfilled:       false
        });

        emit CombatRandomnessRequested(vrfRequestId, attacker, fromTerritory, toTerritory);
    }

    /// @inheritdoc IVRFConsumer
    function cancelCombatRequest(uint256 vrfRequestId) external {
        if (msg.sender != _gameEngine) revert VRFConsumer__NotGameEngine(msg.sender);
        CombatRequest storage req = _requests[vrfRequestId];
        if (req.requestedAt == 0) revert VRFConsumer__RequestNotFound(vrfRequestId);
        if (req.fulfilled) revert VRFConsumer__AlreadyFulfilled(vrfRequestId);
        if (_cancelled[vrfRequestId]) revert VRFConsumer__RequestAlreadyCancelled(vrfRequestId);

        uint256 expiry = req.requestedAt + TIMEOUT_DURATION;
        if (block.timestamp < expiry) revert VRFConsumer__TimeoutNotReached(vrfRequestId, expiry);

        _cancelled[vrfRequestId] = true;
        emit CombatRequestCancelled(vrfRequestId, req.attacker);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Chainlink Callback (called by VRF Coordinator)
    // ─────────────────────────────────────────────────────────────────────────

    /// @dev Chainlink calls this once randomness is available.
    ///      If the request was cancelled (timeout), silently ignores the fulfillment.
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        if (_cancelled[requestId]) return; // timed-out request — ignore

        CombatRequest storage req = _requests[requestId];
        if (req.requestedAt == 0) return; // unknown request — ignore safely
        if (req.fulfilled) return;        // already fulfilled — ignore

        req.fulfilled = true;
        uint256 randomWord = randomWords[0];

        emit CombatRandomnessFulfilled(requestId, randomWord);

        // Callback into GameEngine to resolve combat
        IGameEngineCallback(_gameEngine).resolveCombat(requestId, randomWord);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Admin
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Updates the callback gas limit. Called by admin if gas costs change.
    function setCallbackGasLimit(uint32 limit) external onlyOwner {
        _callbackGasLimit = limit;
    }

    /// @notice Updates the GameEngine address (e.g., after a contract upgrade).
    function setGameEngine(address gameEngine_) external onlyOwner {
        _gameEngine = gameEngine_;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IVRFConsumer
    function getCombatRequest(uint256 vrfRequestId) external view returns (CombatRequest memory) {
        return _requests[vrfRequestId];
    }

    /// @inheritdoc IVRFConsumer
    function isFulfilled(uint256 vrfRequestId) external view returns (bool) {
        return _requests[vrfRequestId].fulfilled;
    }

    /// @inheritdoc IVRFConsumer
    function isTimedOut(uint256 vrfRequestId) external view returns (bool) {
        CombatRequest storage req = _requests[vrfRequestId];
        if (req.fulfilled || _cancelled[vrfRequestId]) return false;
        return block.timestamp >= req.requestedAt + TIMEOUT_DURATION;
    }

    /// @inheritdoc IVRFConsumer
    function timeoutAt(uint256 vrfRequestId) external view returns (uint256) {
        return _requests[vrfRequestId].requestedAt + TIMEOUT_DURATION;
    }

    /// @inheritdoc IVRFConsumer
    function subscriptionId() external view returns (uint256) { return _subscriptionId; }

    /// @inheritdoc IVRFConsumer
    function keyHash() external view returns (bytes32) { return _keyHash; }

    /// @inheritdoc IVRFConsumer
    function callbackGasLimit() external view returns (uint32) { return _callbackGasLimit; }

    /// @inheritdoc IVRFConsumer
    function requestConfirmations() external pure returns (uint16) { return REQUEST_CONFIRMATIONS; }

    // ─────────────────────────────────────────────────────────────────────────
    // Pure Helpers (dice derivation and resolution — usable by tests/frontend)
    // ─────────────────────────────────────────────────────────────────────────

    /// @inheritdoc IVRFConsumer
    /// @dev die[i] = uint8((randomWord >> (i * 16)) % 6) + 1
    function deriveDice(uint256 randomWord, uint8 numDice)
        external
        pure
        returns (uint8[] memory dice)
    {
        require(numDice > 0 && numDice <= 5, "VRFConsumer: numDice out of range");
        dice = new uint8[](numDice);
        for (uint8 i; i < numDice; ++i) {
            dice[i] = uint8((randomWord >> (i * 16)) % 6) + 1;
        }
    }

    /// @inheritdoc IVRFConsumer
    /// @dev Sorts each array descending, then compares pair-by-pair. Ties → defender.
    function resolveDice(uint8[] calldata attackerDice, uint8[] calldata defenderDice)
        external
        pure
        returns (uint8 attackerLosses, uint8 defenderLosses)
    {
        // Sort descending (max 4 attacker, 2 defender — insertion sort is fine)
        uint8[] memory atk = _sortDesc(attackerDice);
        uint8[] memory def = _sortDesc(defenderDice);

        uint256 comparisons = atk.length < def.length ? atk.length : def.length;
        for (uint256 i; i < comparisons; ++i) {
            if (atk[i] > def[i]) {
                defenderLosses++;
            } else {
                // Tie goes to defender
                attackerLosses++;
            }
        }
    }

    function _sortDesc(uint8[] calldata arr) internal pure returns (uint8[] memory sorted) {
        sorted = new uint8[](arr.length);
        for (uint256 i; i < arr.length; ++i) sorted[i] = arr[i];
        // Insertion sort (array length ≤ 4)
        for (uint256 i = 1; i < sorted.length; ++i) {
            uint8 key = sorted[i];
            int256 j = int256(i) - 1;
            while (j >= 0 && sorted[uint256(j)] < key) {
                sorted[uint256(j + 1)] = sorted[uint256(j)];
                j--;
            }
            sorted[uint256(j + 1)] = key;
        }
    }
}
