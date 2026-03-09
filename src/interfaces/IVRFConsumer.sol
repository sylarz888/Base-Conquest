// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IVRFConsumer
/// @notice Interface for the Chainlink VRF v2.5 consumer used to resolve Base-Conquest combat.
/// @dev The VRFConsumer contract wraps Chainlink's VRFConsumerBaseV2Plus.
///      GameEngine calls `requestCombatRandomness` to initiate an attack.
///      Chainlink calls `fulfillRandomWords` (internal to the implementation) which then
///      calls back into `GameEngine.resolveCombat(vrfRequestId, randomWord)`.
///
///      Dice derivation from a single uint256 random word:
///        die[i] = uint8((randomWord >> (i * 16)) % 6) + 1   for i in [0..4]
///      Gives 5 independent dice (max needed: 3 attacker + 2 defender).
///
///      Safety guarantees:
///      - Each VRF request maps 1:1 to one combat (stored in `_pendingRequests`)
///      - If `fulfillRandomWords` is never called (LINK shortage, gas limit exceeded),
///        `cancelCombatRequest` allows the attacker to reclaim committed armies after 24h
///      - `callbackGasLimit` is set conservatively to cover `GameEngine.resolveCombat`
interface IVRFConsumer {
    // ─────────────────────────────────────────────────────────────────────────
    // Structs
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Metadata stored alongside each pending VRF request.
    /// @param attacker         Address who committed the attack.
    /// @param fromTerritory    Source territory token ID.
    /// @param toTerritory      Target territory token ID.
    /// @param attackingArmies  Number of army slots committed (1–4).
    /// @param requestedAt      Block timestamp of the request (for timeout checks).
    /// @param fulfilled        True once `fulfillRandomWords` has been called.
    struct CombatRequest {
        address attacker;
        uint256 fromTerritory;
        uint256 toTerritory;
        uint8 attackingArmies;
        uint48 requestedAt;
        bool fulfilled;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Emitted when a VRF randomness request is submitted to Chainlink.
    event CombatRandomnessRequested(
        uint256 indexed vrfRequestId,
        address indexed attacker,
        uint256 indexed fromTerritory,
        uint256 toTerritory
    );

    /// @notice Emitted when Chainlink fulfills the randomness and combat is resolved.
    event CombatRandomnessFulfilled(uint256 indexed vrfRequestId, uint256 randomWord);

    /// @notice Emitted when a timed-out request is cancelled.
    event CombatRequestCancelled(uint256 indexed vrfRequestId, address indexed attacker);

    // ─────────────────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────────────────

    error VRFConsumer__NotGameEngine(address caller);
    error VRFConsumer__RequestNotFound(uint256 vrfRequestId);
    error VRFConsumer__AlreadyFulfilled(uint256 vrfRequestId);
    error VRFConsumer__TimeoutNotReached(uint256 vrfRequestId, uint256 timeoutAt);
    error VRFConsumer__RequestAlreadyCancelled(uint256 vrfRequestId);

    // ─────────────────────────────────────────────────────────────────────────
    // Request & Cancel (GameEngine only)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Submits a Chainlink VRF request for one combat round.
    /// @dev Only callable by the GameEngine contract (GAME_ENGINE_ROLE).
    ///      Stores the CombatRequest keyed by the returned VRF request ID.
    ///      Uses the subscription-funded model (no direct LINK transfer per request).
    /// @param attacker         Address of the attacking player.
    /// @param fromTerritory    Token ID of the attacking territory.
    /// @param toTerritory      Token ID of the defending territory.
    /// @param attackingArmies  Number of committed armies (1–4).
    /// @return vrfRequestId    The Chainlink-assigned request ID for this combat.
    function requestCombatRandomness(
        address attacker,
        uint256 fromTerritory,
        uint256 toTerritory,
        uint8 attackingArmies
    ) external returns (uint256 vrfRequestId);

    /// @notice Cancels a VRF request that has timed out (>24 hours without fulfillment).
    /// @dev Only callable by GameEngine. Marks the request as cancelled so that
    ///      a late `fulfillRandomWords` callback is ignored.
    ///      GameEngine is responsible for returning committed armies after cancellation.
    /// @param vrfRequestId  The VRF request ID to cancel.
    function cancelCombatRequest(uint256 vrfRequestId) external;

    // ─────────────────────────────────────────────────────────────────────────
    // View Functions
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Returns the CombatRequest metadata for a given VRF request ID.
    function getCombatRequest(uint256 vrfRequestId) external view returns (CombatRequest memory);

    /// @notice Returns true if the VRF request has been fulfilled.
    function isFulfilled(uint256 vrfRequestId) external view returns (bool);

    /// @notice Returns true if the VRF request timed out (>24h) and has not been fulfilled.
    function isTimedOut(uint256 vrfRequestId) external view returns (bool);

    /// @notice Returns the Unix timestamp after which a request is considered timed out.
    /// @param vrfRequestId  The VRF request ID to check.
    function timeoutAt(uint256 vrfRequestId) external view returns (uint256);

    /// @notice Returns the Chainlink VRF subscription ID used by this contract.
    function subscriptionId() external view returns (uint256);

    /// @notice Returns the Chainlink VRF key hash (gas lane) configured for this contract.
    function keyHash() external view returns (bytes32);

    /// @notice Returns the gas limit passed to `fulfillRandomWords` callback.
    function callbackGasLimit() external view returns (uint32);

    /// @notice Returns the number of block confirmations required before VRF fulfillment.
    function requestConfirmations() external view returns (uint16);

    // ─────────────────────────────────────────────────────────────────────────
    // Combat Resolution Helper (pure — for testing and frontend simulation)
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Derives up to 5 dice values from a single VRF random word.
    /// @dev Formula: die[i] = uint8((randomWord >> (i * 16)) % 6) + 1
    /// @param randomWord      The uint256 random word from Chainlink VRF.
    /// @param numDice         How many dice to derive (1–5).
    /// @return dice           Array of `numDice` values, each in range [1, 6].
    function deriveDice(uint256 randomWord, uint8 numDice) external pure returns (uint8[] memory dice);

    /// @notice Resolves a classic Risk combat comparison from raw dice arrays.
    /// @dev Sorts attacker and defender dice descending. Compares highest vs highest,
    ///      then 2nd highest vs 2nd highest (if available). Ties go to defender.
    /// @param attackerDice  Attacker's dice values (1–4 elements).
    /// @param defenderDice  Defender's dice values (1–2 elements).
    /// @return attackerLosses  Number of attacker armies lost (0–2).
    /// @return defenderLosses  Number of defender armies lost (0–2).
    function resolveDice(uint8[] calldata attackerDice, uint8[] calldata defenderDice)
        external
        pure
        returns (uint8 attackerLosses, uint8 defenderLosses);
}
