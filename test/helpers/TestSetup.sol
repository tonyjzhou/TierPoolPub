// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TierPool} from "../../src/TierPool.sol";
import {MockERC20} from "./MockERC20.sol";

/// @title TestSetup
/// @notice Shared test fixtures for TierPool tests
abstract contract TestSetup is Test {
    TierPool public pool;
    MockERC20 public mnee;

    address public organizer = address(0x1);
    address public vendor1 = address(0x2);
    address public vendor2 = address(0x3);
    address public vendor3 = address(0x4);
    address public recipient = address(0x5);
    address public contributor1 = address(0x6);
    address public contributor2 = address(0x7);
    address public contributor3 = address(0x8);

    uint256 public constant TIER1_THRESHOLD = 500e18;
    uint256 public constant TIER2_THRESHOLD = 1000e18;
    uint256 public constant TIER3_THRESHOLD = 2000e18;

    uint256 public constant DEFAULT_DEADLINE = 7 days;
    uint256 public constant DEFAULT_COOLDOWN = 1 days;
    uint256 public constant DEFAULT_VALID_UNTIL = 30 days;

    bytes32 public constant DOC_HASH_1 = keccak256("Quote Document 1");
    bytes32 public constant DOC_HASH_2 = keccak256("Quote Document 2");
    bytes32 public constant DOC_HASH_3 = keccak256("Quote Document 3");

    function setUp() public virtual {
        mnee = new MockERC20("MNEE", "MNEE", 18);
        pool = new TierPool(address(mnee));

        // Fund test accounts
        mnee.mint(contributor1, 10000e18);
        mnee.mint(contributor2, 10000e18);
        mnee.mint(contributor3, 10000e18);

        // Approve pool for all contributors
        vm.prank(contributor1);
        mnee.approve(address(pool), type(uint256).max);
        vm.prank(contributor2);
        mnee.approve(address(pool), type(uint256).max);
        vm.prank(contributor3);
        mnee.approve(address(pool), type(uint256).max);
    }

    /// @notice Create a pool with 3 tiers and default settings
    function _createDefaultPool() internal returns (uint256 poolId) {
        uint256[] memory thresholds = new uint256[](3);
        thresholds[0] = TIER1_THRESHOLD;
        thresholds[1] = TIER2_THRESHOLD;
        thresholds[2] = TIER3_THRESHOLD;

        bytes32[] memory docHashes = new bytes32[](3);
        docHashes[0] = DOC_HASH_1;
        docHashes[1] = DOC_HASH_2;
        docHashes[2] = DOC_HASH_3;

        address[] memory vendors = new address[](3);
        vendors[0] = vendor1;
        vendors[1] = vendor2;
        vendors[2] = vendor3;

        vm.prank(organizer);
        poolId = pool.createPool(
            recipient, block.timestamp + DEFAULT_DEADLINE, DEFAULT_COOLDOWN, thresholds, docHashes, vendors
        );
    }

    /// @notice Create a single-tier pool
    function _createSingleTierPool() internal returns (uint256 poolId) {
        uint256[] memory thresholds = new uint256[](1);
        thresholds[0] = TIER1_THRESHOLD;

        bytes32[] memory docHashes = new bytes32[](1);
        docHashes[0] = DOC_HASH_1;

        address[] memory vendors = new address[](1);
        vendors[0] = vendor1;

        vm.prank(organizer);
        poolId = pool.createPool(
            recipient, block.timestamp + DEFAULT_DEADLINE, DEFAULT_COOLDOWN, thresholds, docHashes, vendors
        );
    }

    /// @notice Attest tier 1 with default valid until
    function _attestTier1(uint256 poolId) internal {
        TierPool.Pool memory p = pool.getPool(poolId);
        uint256 validUntil = p.deadline + p.cooldownDuration + DEFAULT_VALID_UNTIL;

        vm.prank(vendor1);
        pool.attestQuote(poolId, 1, validUntil);
    }

    /// @notice Attest tier 2 with default valid until
    function _attestTier2(uint256 poolId) internal {
        TierPool.Pool memory p = pool.getPool(poolId);
        uint256 validUntil = p.deadline + p.cooldownDuration + DEFAULT_VALID_UNTIL;

        vm.prank(vendor2);
        pool.attestQuote(poolId, 2, validUntil);
    }

    /// @notice Attest tier 3 with default valid until
    function _attestTier3(uint256 poolId) internal {
        TierPool.Pool memory p = pool.getPool(poolId);
        uint256 validUntil = p.deadline + p.cooldownDuration + DEFAULT_VALID_UNTIL;

        vm.prank(vendor3);
        pool.attestQuote(poolId, 3, validUntil);
    }

    /// @notice Fund pool to tier 1 threshold
    function _fundToTier1(uint256 poolId) internal {
        vm.prank(contributor1);
        pool.contribute(poolId, TIER1_THRESHOLD);
    }

    /// @notice Fund pool to tier 2 threshold
    function _fundToTier2(uint256 poolId) internal {
        vm.prank(contributor1);
        pool.contribute(poolId, TIER2_THRESHOLD);
    }

    /// @notice Fund pool to tier 3 threshold
    function _fundToTier3(uint256 poolId) internal {
        vm.prank(contributor1);
        pool.contribute(poolId, TIER3_THRESHOLD);
    }

    /// @notice Advance time past the deadline
    function _advancePastDeadline(uint256 poolId) internal {
        TierPool.Pool memory p = pool.getPool(poolId);
        vm.warp(p.deadline + 1);
    }

    /// @notice Advance time past the cooldown
    function _advancePastCooldown(uint256 poolId) internal {
        TierPool.Pool memory p = pool.getPool(poolId);
        vm.warp(p.deadline + p.cooldownDuration + 1);
    }

    /// @notice Advance time to expire attestations
    function _advancePastAttestation(uint256 poolId, uint8 tierIndex) internal {
        TierPool.Tier memory t = pool.getTier(poolId, tierIndex);
        vm.warp(t.validUntil + 1);
    }
}
