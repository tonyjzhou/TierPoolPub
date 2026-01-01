// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TierPool} from "../src/TierPool.sol";
import {TestSetup} from "./helpers/TestSetup.sol";

/// @title TierPoolAttestationTest
/// @notice Test file covering attestation functionality (T29-T34)
contract TierPoolAttestationTest is TestSetup {
    // Event signature must match contract
    event QuoteAttested(
        uint256 indexed poolId,
        uint8 tierIndex,
        address indexed vendor,
        uint256 validUntil,
        uint256 attestedAt,
        bytes32 commitmentHash
    );

    // ══════════════════════════════════════════════════════════════
    // ATTESTATION TESTS (T29-T34)
    // ══════════════════════════════════════════════════════════════

    /// @notice T29: Vendor can attest their tier
    function test_attestQuote_byVendor_succeeds() public {
        uint256 poolId = _createDefaultPool();

        TierPool.Pool memory p = pool.getPool(poolId);
        uint256 validUntil = p.deadline + p.cooldownDuration + DEFAULT_VALID_UNTIL;

        vm.prank(vendor1);
        pool.attestQuote(poolId, 1, validUntil);

        TierPool.Tier memory tier = pool.getTier(poolId, 1);
        assertEq(tier.attestedAt, block.timestamp);
        assertEq(tier.validUntil, validUntil);
        assertEq(uint256(pool.getAttestationStatus(poolId, 1)), uint256(TierPool.AttestationStatus.VALID));
    }

    /// @notice T30: Non-vendor cannot attest
    function test_attestQuote_notVendor_reverts() public {
        uint256 poolId = _createDefaultPool();

        TierPool.Pool memory p = pool.getPool(poolId);
        uint256 validUntil = p.deadline + p.cooldownDuration + DEFAULT_VALID_UNTIL;

        // vendor2 trying to attest tier 1 (which belongs to vendor1)
        vm.prank(vendor2);
        vm.expectRevert(TierPool.NotTierVendor.selector);
        pool.attestQuote(poolId, 1, validUntil);

        // Random address trying to attest
        vm.prank(address(0x999));
        vm.expectRevert(TierPool.NotTierVendor.selector);
        pool.attestQuote(poolId, 1, validUntil);
    }

    /// @notice T31: Attestation twice reverts
    function test_attestQuote_twice_reverts() public {
        uint256 poolId = _createDefaultPool();

        TierPool.Pool memory p = pool.getPool(poolId);
        uint256 validUntil = p.deadline + p.cooldownDuration + DEFAULT_VALID_UNTIL;

        vm.prank(vendor1);
        pool.attestQuote(poolId, 1, validUntil);

        vm.prank(vendor1);
        vm.expectRevert(TierPool.AlreadyAttested.selector);
        pool.attestQuote(poolId, 1, validUntil + 1 days);
    }

    /// @notice T32: Attestation with validUntil too early reverts
    function test_attestQuote_validUntilTooEarly_reverts() public {
        uint256 poolId = _createDefaultPool();

        TierPool.Pool memory p = pool.getPool(poolId);
        // Set validUntil to before deadline + cooldown
        uint256 tooEarlyValidUntil = p.deadline + p.cooldownDuration - 1;

        vm.prank(vendor1);
        vm.expectRevert(TierPool.ValidUntilTooEarly.selector);
        pool.attestQuote(poolId, 1, tooEarlyValidUntil);

        // Exactly at min is OK
        uint256 exactMinValidUntil = p.deadline + p.cooldownDuration;
        vm.prank(vendor1);
        pool.attestQuote(poolId, 1, exactMinValidUntil);
    }

    /// @notice T33: Attestation after deadline reverts
    function test_attestQuote_afterDeadline_reverts() public {
        uint256 poolId = _createDefaultPool();

        TierPool.Pool memory p = pool.getPool(poolId);
        uint256 validUntil = p.deadline + p.cooldownDuration + DEFAULT_VALID_UNTIL;

        // Advance past deadline
        vm.warp(p.deadline + 1);

        vm.prank(vendor1);
        vm.expectRevert(TierPool.PoolAlreadyActive.selector);
        pool.attestQuote(poolId, 1, validUntil);
    }

    /// @notice T34: Attestation emits commitment hash
    function test_attestQuote_emitsCommitmentHash() public {
        uint256 poolId = _createDefaultPool();

        TierPool.Pool memory p = pool.getPool(poolId);
        TierPool.Tier memory tier = pool.getTier(poolId, 1);
        uint256 validUntil = p.deadline + p.cooldownDuration + DEFAULT_VALID_UNTIL;

        // Compute expected commitment hash
        bytes32 expectedHash = keccak256(abi.encode(poolId, uint8(1), tier.threshold, tier.documentHash, p.recipient));

        // Expect the event with commitment hash
        vm.expectEmit(true, true, false, true);
        emit QuoteAttested(poolId, 1, vendor1, validUntil, block.timestamp, expectedHash);

        vm.prank(vendor1);
        pool.attestQuote(poolId, 1, validUntil);
    }

    // ══════════════════════════════════════════════════════════════
    // ADDITIONAL ATTESTATION EDGE CASES
    // ══════════════════════════════════════════════════════════════

    /// @notice Attestation status is MISSING before attestation
    function test_getAttestationStatus_missing() public {
        uint256 poolId = _createDefaultPool();
        assertEq(uint256(pool.getAttestationStatus(poolId, 1)), uint256(TierPool.AttestationStatus.MISSING));
        assertEq(uint256(pool.getAttestationStatus(poolId, 2)), uint256(TierPool.AttestationStatus.MISSING));
        assertEq(uint256(pool.getAttestationStatus(poolId, 3)), uint256(TierPool.AttestationStatus.MISSING));
    }

    /// @notice Attestation status transitions to EXPIRED
    function test_getAttestationStatus_expired() public {
        uint256 poolId = _createDefaultPool();

        TierPool.Pool memory p = pool.getPool(poolId);
        uint256 validUntil = p.deadline + p.cooldownDuration;

        vm.prank(vendor1);
        pool.attestQuote(poolId, 1, validUntil);

        // Initially VALID
        assertEq(uint256(pool.getAttestationStatus(poolId, 1)), uint256(TierPool.AttestationStatus.VALID));

        // Advance past validUntil
        vm.warp(validUntil + 1);

        // Now EXPIRED
        assertEq(uint256(pool.getAttestationStatus(poolId, 1)), uint256(TierPool.AttestationStatus.EXPIRED));
    }

    /// @notice Invalid tier index reverts
    function test_attestQuote_invalidTierIndex_reverts() public {
        uint256 poolId = _createDefaultPool();

        TierPool.Pool memory p = pool.getPool(poolId);
        uint256 validUntil = p.deadline + p.cooldownDuration + DEFAULT_VALID_UNTIL;

        // Tier 0 (invalid - 1-based indexing)
        vm.prank(vendor1);
        vm.expectRevert(TierPool.InvalidTierCount.selector);
        pool.attestQuote(poolId, 0, validUntil);

        // Tier 4 (pool only has 3 tiers)
        vm.prank(vendor1);
        vm.expectRevert(TierPool.InvalidTierCount.selector);
        pool.attestQuote(poolId, 4, validUntil);
    }

    /// @notice Multiple tiers can be attested by their respective vendors
    function test_attestQuote_multipleTiers() public {
        uint256 poolId = _createDefaultPool();

        TierPool.Pool memory p = pool.getPool(poolId);
        uint256 validUntil = p.deadline + p.cooldownDuration + DEFAULT_VALID_UNTIL;

        vm.prank(vendor1);
        pool.attestQuote(poolId, 1, validUntil);

        vm.prank(vendor2);
        pool.attestQuote(poolId, 2, validUntil);

        vm.prank(vendor3);
        pool.attestQuote(poolId, 3, validUntil);

        assertEq(uint256(pool.getAttestationStatus(poolId, 1)), uint256(TierPool.AttestationStatus.VALID));
        assertEq(uint256(pool.getAttestationStatus(poolId, 2)), uint256(TierPool.AttestationStatus.VALID));
        assertEq(uint256(pool.getAttestationStatus(poolId, 3)), uint256(TierPool.AttestationStatus.VALID));
    }
}
