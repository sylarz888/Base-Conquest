// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVRFCoordinatorV2Plus} from
    "@chainlink/contracts/src/v0.8/vrf/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/libraries/VRFV2PlusClient.sol";

/// @title MockVRFCoordinator
/// @notice Test double for Chainlink VRF v2.5 coordinator.
/// @dev Stores pending requests and allows tests to manually fulfill them
///      with a deterministic or arbitrary random word.
contract MockVRFCoordinator {
    uint256 private _nextRequestId = 1;

    struct PendingRequest {
        address consumer;
        uint256 subId;
        uint32  numWords;
        bool    fulfilled;
    }

    mapping(uint256 => PendingRequest) public pendingRequests;

    event RandomWordsRequested(uint256 indexed requestId, address indexed consumer, uint256 subId);
    event RandomWordsFulfilled(uint256 indexed requestId, uint256[] words);

    // ── IVRFCoordinatorV2Plus subset ──────────────────────────────────────────

    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata req)
        external
        returns (uint256 requestId)
    {
        requestId = _nextRequestId++;
        pendingRequests[requestId] = PendingRequest({
            consumer:  msg.sender,
            subId:     req.subId,
            numWords:  req.numWords,
            fulfilled: false
        });
        emit RandomWordsRequested(requestId, msg.sender, req.subId);
    }

    // ── Test helper: fulfill with a specific random word ─────────────────────

    function fulfillRandomWords(uint256 requestId, uint256 randomWord) external {
        PendingRequest storage req = pendingRequests[requestId];
        require(!req.fulfilled, "MockVRF: already fulfilled");
        req.fulfilled = true;

        uint256[] memory words = new uint256[](req.numWords);
        for (uint32 i; i < req.numWords; ++i) {
            words[i] = uint256(keccak256(abi.encodePacked(randomWord, i)));
        }
        words[0] = randomWord; // override first word with exact value for deterministic tests

        emit RandomWordsFulfilled(requestId, words);

        // Call back into the consumer's fulfillRandomWords
        (bool ok,) = req.consumer.call(
            abi.encodeWithSignature("rawFulfillRandomWords(uint256,uint256[])", requestId, words)
        );
        require(ok, "MockVRF: callback failed");
    }

    // ── Test helper: fulfill with a derived random word ───────────────────────

    function fulfillRandomWordsWithSeed(uint256 requestId, uint256 seed) external {
        this.fulfillRandomWords(requestId, uint256(keccak256(abi.encodePacked(seed))));
    }

    // ── Stubs for IVRFCoordinatorV2Plus methods not used in tests ─────────────

    function getSubscription(uint256)
        external
        pure
        returns (uint96, uint96, uint64, address, address[] memory)
    {
        return (1e18, 0, 0, address(0), new address[](0));
    }

    function addConsumer(uint256, address) external {}
    function removeConsumer(uint256, address) external {}
    function cancelSubscription(uint256, address) external {}
    function createSubscription() external returns (uint256) { return 1; }
    function fundSubscription(uint256, uint96) external {}
    function pendingRequestExists(uint256) external pure returns (bool) { return false; }
}
