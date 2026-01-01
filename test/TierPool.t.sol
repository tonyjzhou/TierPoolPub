// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TierPool} from "../src/TierPool.sol";
import {TestSetup} from "./helpers/TestSetup.sol";
import {MockFeeOnTransferToken} from "./helpers/MockFeeOnTransferToken.sol";

/// @title TierPoolTest
/// @notice Main test file covering pool creation, state machine, contributions, exit, finalization, and refunds
contract TierPoolTest is TestSetup {
    // ══════════════════════════════════════════════════════════════
    // POOL CREATION TESTS (T01-T03)
    // ══════════════════════════════════════════════════════════════

    /// @notice T01: Valid pool creation with 3 tiers
    function test_createPool_valid() public {
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
        uint256 poolId = pool.createPool(
            recipient, block.timestamp + DEFAULT_DEADLINE, DEFAULT_COOLDOWN, thresholds, docHashes, vendors
        );

        assertEq(poolId, 0);

        TierPool.Pool memory p = pool.getPool(poolId);
        assertEq(p.organizer, organizer);
        assertEq(p.recipient, recipient);
        assertEq(p.deadline, block.timestamp + DEFAULT_DEADLINE);
        assertEq(p.cooldownDuration, DEFAULT_COOLDOWN);
        assertEq(p.totalRaised, 0);
        assertEq(p.finalized, false);

        assertEq(pool.getTierCount(poolId), 3);

        TierPool.Tier[] memory tiers = pool.getTiers(poolId);
        assertEq(tiers[0].threshold, TIER1_THRESHOLD);
        assertEq(tiers[0].vendor, vendor1);
        assertEq(tiers[0].documentHash, DOC_HASH_1);
        assertEq(tiers[1].threshold, TIER2_THRESHOLD);
        assertEq(tiers[2].threshold, TIER3_THRESHOLD);
    }

    /// @notice T02: Pool creation with invalid recipient reverts
    function test_createPool_invalidRecipient_reverts() public {
        (uint256[] memory t, bytes32[] memory h, address[] memory v) = _getSingleTierParams();
        vm.prank(organizer);
        vm.expectRevert(TierPool.InvalidRecipient.selector);
        pool.createPool(address(0), block.timestamp + 1 days, 1 hours, t, h, v);
    }

    function test_createPool_deadlineInPast_reverts() public {
        (uint256[] memory t, bytes32[] memory h, address[] memory v) = _getSingleTierParams();
        vm.prank(organizer);
        vm.expectRevert(TierPool.DeadlineMustBeFuture.selector);
        pool.createPool(recipient, block.timestamp - 1, 1 hours, t, h, v);
    }

    function test_createPool_zeroCooldown_reverts() public {
        (uint256[] memory t, bytes32[] memory h, address[] memory v) = _getSingleTierParams();
        vm.prank(organizer);
        vm.expectRevert(TierPool.CooldownRequired.selector);
        pool.createPool(recipient, block.timestamp + 1 days, 0, t, h, v);
    }

    function test_createPool_emptyTiers_reverts() public {
        uint256[] memory emptyT = new uint256[](0);
        bytes32[] memory emptyH = new bytes32[](0);
        address[] memory emptyV = new address[](0);
        vm.prank(organizer);
        vm.expectRevert(TierPool.InvalidTierCount.selector);
        pool.createPool(recipient, block.timestamp + 1 days, 1 hours, emptyT, emptyH, emptyV);
    }

    function test_createPool_tooManyTiers_reverts() public {
        uint256[] memory t = new uint256[](4);
        t[0] = 100e18;
        t[1] = 200e18;
        t[2] = 300e18;
        t[3] = 400e18;
        bytes32[] memory h = new bytes32[](4);
        h[0] = DOC_HASH_1;
        h[1] = DOC_HASH_2;
        h[2] = DOC_HASH_3;
        h[3] = keccak256("doc4");
        address[] memory v = new address[](4);
        v[0] = vendor1;
        v[1] = vendor2;
        v[2] = vendor3;
        v[3] = address(0x9);
        vm.prank(organizer);
        vm.expectRevert(TierPool.InvalidTierCount.selector);
        pool.createPool(recipient, block.timestamp + 1 days, 1 hours, t, h, v);
    }

    function test_createPool_nonAscendingThresholds_reverts() public {
        uint256[] memory t = new uint256[](2);
        t[0] = 200e18;
        t[1] = 100e18;
        bytes32[] memory h = new bytes32[](2);
        h[0] = DOC_HASH_1;
        h[1] = DOC_HASH_2;
        address[] memory v = new address[](2);
        v[0] = vendor1;
        v[1] = vendor2;
        vm.prank(organizer);
        vm.expectRevert(TierPool.TiersMustBeAscending.selector);
        pool.createPool(recipient, block.timestamp + 1 days, 1 hours, t, h, v);
    }

    function test_createPool_zeroThreshold_reverts() public {
        uint256[] memory t = new uint256[](1);
        t[0] = 0;
        bytes32[] memory h = new bytes32[](1);
        h[0] = DOC_HASH_1;
        address[] memory v = new address[](1);
        v[0] = vendor1;
        vm.prank(organizer);
        vm.expectRevert(TierPool.ThresholdMustBePositive.selector);
        pool.createPool(recipient, block.timestamp + 1 days, 1 hours, t, h, v);
    }

    function test_createPool_zeroVendor_reverts() public {
        uint256[] memory t = new uint256[](1);
        t[0] = TIER1_THRESHOLD;
        bytes32[] memory h = new bytes32[](1);
        h[0] = DOC_HASH_1;
        address[] memory v = new address[](1);
        v[0] = address(0);
        vm.prank(organizer);
        vm.expectRevert(TierPool.InvalidVendor.selector);
        pool.createPool(recipient, block.timestamp + 1 days, 1 hours, t, h, v);
    }

    function test_createPool_zeroDocHash_reverts() public {
        uint256[] memory t = new uint256[](1);
        t[0] = TIER1_THRESHOLD;
        bytes32[] memory h = new bytes32[](1);
        h[0] = bytes32(0);
        address[] memory v = new address[](1);
        v[0] = vendor1;
        vm.prank(organizer);
        vm.expectRevert(TierPool.InvalidDocumentHash.selector);
        pool.createPool(recipient, block.timestamp + 1 days, 1 hours, t, h, v);
    }

    function _getSingleTierParams() internal view returns (uint256[] memory t, bytes32[] memory h, address[] memory v) {
        t = new uint256[](1);
        t[0] = TIER1_THRESHOLD;
        h = new bytes32[](1);
        h[0] = DOC_HASH_1;
        v = new address[](1);
        v[0] = vendor1;
    }

    /// @notice T03: Pool creation with cooldown > 30 days reverts
    function test_createPool_cooldownTooLong_reverts() public {
        uint256[] memory thresholds = new uint256[](1);
        thresholds[0] = TIER1_THRESHOLD;

        bytes32[] memory docHashes = new bytes32[](1);
        docHashes[0] = DOC_HASH_1;

        address[] memory vendors = new address[](1);
        vendors[0] = vendor1;

        uint256 tooLongCooldown = 31 days;

        vm.prank(organizer);
        vm.expectRevert(TierPool.CooldownTooLong.selector);
        pool.createPool(recipient, block.timestamp + DEFAULT_DEADLINE, tooLongCooldown, thresholds, docHashes, vendors);
    }

    // ══════════════════════════════════════════════════════════════
    // STATE MACHINE TESTS (T04-T11)
    // ══════════════════════════════════════════════════════════════

    /// @notice T04: State is PENDING before attestation
    function test_getState_pendingBeforeAttestation() public {
        uint256 poolId = _createDefaultPool();
        assertEq(uint256(pool.getState(poolId)), uint256(TierPool.State.PENDING));
    }

    /// @notice T05: State is ACTIVE after Tier 1 attestation
    function test_getState_activeAfterTier1Attestation() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);
        assertEq(uint256(pool.getState(poolId)), uint256(TierPool.State.ACTIVE));
    }

    /// @notice T06: State is COOLDOWN after deadline (with payable tier)
    function test_getState_cooldownAfterDeadline() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);
        _fundToTier1(poolId);
        _advancePastDeadline(poolId);

        assertEq(uint256(pool.getState(poolId)), uint256(TierPool.State.COOLDOWN));
    }

    /// @notice T07: State is PAYABLE after cooldown
    function test_getState_payableAfterCooldown() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);
        _fundToTier1(poolId);
        _advancePastCooldown(poolId);

        assertEq(uint256(pool.getState(poolId)), uint256(TierPool.State.PAYABLE));
    }

    /// @notice T08: State is PAID after finalize
    function test_getState_paidAfterFinalize() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);
        _fundToTier1(poolId);
        _advancePastCooldown(poolId);

        pool.finalize(poolId);

        assertEq(uint256(pool.getState(poolId)), uint256(TierPool.State.PAID));
    }

    /// @notice T09: State is REFUNDING when no payable tier (unfunded)
    function test_getState_refundingNoPayableTier() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);
        // Don't fund - under tier 1 threshold
        vm.prank(contributor1);
        pool.contribute(poolId, 100e18); // Less than TIER1_THRESHOLD

        _advancePastDeadline(poolId);

        assertEq(uint256(pool.getState(poolId)), uint256(TierPool.State.REFUNDING));
    }

    /// @notice T10: State transitions from COOLDOWN to REFUNDING on attestation expiry
    function test_getState_refundingOnAttestationExpiry() public {
        uint256 poolId = _createSingleTierPool();

        // Attest with minimal valid until
        TierPool.Pool memory p = pool.getPool(poolId);
        uint256 minValidUntil = p.deadline + p.cooldownDuration;

        vm.prank(vendor1);
        pool.attestQuote(poolId, 1, minValidUntil);

        _fundToTier1(poolId);
        _advancePastDeadline(poolId);

        // Still in cooldown, but attestation hasn't expired yet
        assertEq(uint256(pool.getState(poolId)), uint256(TierPool.State.COOLDOWN));

        // Advance past attestation validity
        vm.warp(minValidUntil + 1);

        // Now should be REFUNDING because attestation expired
        assertEq(uint256(pool.getState(poolId)), uint256(TierPool.State.REFUNDING));
    }

    /// @notice T11: State is dynamically recalculated
    function test_getState_dynamicRecalculation() public {
        uint256 poolId = _createDefaultPool();

        // PENDING -> ACTIVE
        assertEq(uint256(pool.getState(poolId)), uint256(TierPool.State.PENDING));
        _attestTier1(poolId);
        assertEq(uint256(pool.getState(poolId)), uint256(TierPool.State.ACTIVE));

        // Fund and advance
        _fundToTier1(poolId);
        _advancePastDeadline(poolId);
        assertEq(uint256(pool.getState(poolId)), uint256(TierPool.State.COOLDOWN));

        _advancePastCooldown(poolId);
        assertEq(uint256(pool.getState(poolId)), uint256(TierPool.State.PAYABLE));
    }

    // ══════════════════════════════════════════════════════════════
    // CONTRIBUTIONS TESTS (T12-T16)
    // ══════════════════════════════════════════════════════════════

    /// @notice T12: Contribute requires Tier 1 attestation
    function test_contribute_requiresTier1Attestation() public {
        uint256 poolId = _createDefaultPool();

        vm.prank(contributor1);
        vm.expectRevert(TierPool.Tier1NotAttested.selector);
        pool.contribute(poolId, 100e18);
    }

    /// @notice T13: Contribute after attestation succeeds
    function test_contribute_afterAttestation_succeeds() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);

        uint256 amount = 250e18;
        uint256 balanceBefore = mnee.balanceOf(contributor1);

        vm.prank(contributor1);
        pool.contribute(poolId, amount);

        assertEq(pool.getContribution(poolId, contributor1), amount);
        assertEq(mnee.balanceOf(contributor1), balanceBefore - amount);

        TierPool.Pool memory p = pool.getPool(poolId);
        assertEq(p.totalRaised, amount);
    }

    /// @notice T14: Balance-delta accounting is correct
    function test_contribute_balanceDeltaAccounting() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);

        uint256 amount1 = 200e18;
        uint256 amount2 = 300e18;

        vm.prank(contributor1);
        pool.contribute(poolId, amount1);

        vm.prank(contributor2);
        pool.contribute(poolId, amount2);

        assertEq(pool.getContribution(poolId, contributor1), amount1);
        assertEq(pool.getContribution(poolId, contributor2), amount2);

        TierPool.Pool memory p = pool.getPool(poolId);
        assertEq(p.totalRaised, amount1 + amount2);
    }

    /// @notice T15: Contribute outside ACTIVE state reverts
    function test_contribute_outsideActive_reverts() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);
        _fundToTier1(poolId);
        _advancePastDeadline(poolId);

        // COOLDOWN state
        vm.prank(contributor2);
        vm.expectRevert(TierPool.NotInActiveState.selector);
        pool.contribute(poolId, 100e18);

        // PAYABLE state
        _advancePastCooldown(poolId);
        vm.prank(contributor2);
        vm.expectRevert(TierPool.NotInActiveState.selector);
        pool.contribute(poolId, 100e18);
    }

    /// @notice T16: Fee-on-transfer token accounting (balance-delta pattern)
    function test_contribute_feeOnTransfer_accounting() public {
        // Deploy pool with FOT token
        MockFeeOnTransferToken fotToken = new MockFeeOnTransferToken("FOT", "FOT", 18);
        TierPool fotPool = new TierPool(address(fotToken));

        // Fund contributor
        fotToken.mint(contributor1, 10000e18);
        vm.prank(contributor1);
        fotToken.approve(address(fotPool), type(uint256).max);

        // Create pool
        uint256[] memory thresholds = new uint256[](1);
        thresholds[0] = 450e18; // Set below expected net amount

        bytes32[] memory docHashes = new bytes32[](1);
        docHashes[0] = DOC_HASH_1;

        address[] memory vendors = new address[](1);
        vendors[0] = vendor1;

        vm.prank(organizer);
        uint256 poolId = fotPool.createPool(
            recipient, block.timestamp + DEFAULT_DEADLINE, DEFAULT_COOLDOWN, thresholds, docHashes, vendors
        );

        // Attest
        TierPool.Pool memory p = fotPool.getPool(poolId);
        vm.prank(vendor1);
        fotPool.attestQuote(poolId, 1, p.deadline + p.cooldownDuration + DEFAULT_VALID_UNTIL);

        // Contribute 500e18, expect 1% fee = 495e18 received
        uint256 contributeAmount = 500e18;
        uint256 expectedReceived = contributeAmount - (contributeAmount / 100); // 495e18

        vm.prank(contributor1);
        fotPool.contribute(poolId, contributeAmount);

        // Verify balance-delta captured net amount
        assertEq(fotPool.getContribution(poolId, contributor1), expectedReceived);

        TierPool.Pool memory pAfter = fotPool.getPool(poolId);
        assertEq(pAfter.totalRaised, expectedReceived);
    }

    // ══════════════════════════════════════════════════════════════
    // EXIT WINDOW TESTS (T17-T20)
    // ══════════════════════════════════════════════════════════════

    /// @notice T17: Exit during cooldown succeeds
    function test_exit_duringCooldown_succeeds() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);

        // Three contributors fund well past tier 1 so exit doesn't drop below threshold
        vm.prank(contributor1);
        pool.contribute(poolId, 300e18);
        vm.prank(contributor2);
        pool.contribute(poolId, 300e18);
        vm.prank(contributor3);
        pool.contribute(poolId, 300e18); // Total: 900e18, above TIER1_THRESHOLD (500e18)

        _advancePastDeadline(poolId);

        // Contributor1 exits - 600e18 remains, still above tier 1
        uint256 balanceBefore = mnee.balanceOf(contributor1);

        vm.prank(contributor1);
        pool.exit(poolId);

        assertEq(pool.getContribution(poolId, contributor1), 0);
        assertEq(mnee.balanceOf(contributor1), balanceBefore + 300e18);

        TierPool.Pool memory p = pool.getPool(poolId);
        assertEq(p.totalRaised, 600e18);
    }

    /// @notice T18: Exit outside cooldown reverts
    function test_exit_outsideCooldown_reverts() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);
        _fundToTier1(poolId);

        // ACTIVE state
        vm.prank(contributor1);
        vm.expectRevert(TierPool.NotInCooldownState.selector);
        pool.exit(poolId);

        // PAYABLE state
        _advancePastCooldown(poolId);
        vm.prank(contributor1);
        vm.expectRevert(TierPool.NotInCooldownState.selector);
        pool.exit(poolId);
    }

    /// @notice T19: Exit reduces totalRaised
    function test_exit_reducesTotalRaised() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);

        // Fund above threshold so exit doesn't cause refunding
        vm.prank(contributor1);
        pool.contribute(poolId, 300e18);
        vm.prank(contributor2);
        pool.contribute(poolId, 300e18);
        vm.prank(contributor3);
        pool.contribute(poolId, 300e18); // Total: 900e18

        _advancePastDeadline(poolId);

        TierPool.Pool memory pBefore = pool.getPool(poolId);
        assertEq(pBefore.totalRaised, 900e18);

        // Exit contributor1 - leaves 600e18 still above tier 1
        vm.prank(contributor1);
        pool.exit(poolId);

        TierPool.Pool memory pAfter = pool.getPool(poolId);
        assertEq(pAfter.totalRaised, 600e18);
    }

    /// @notice T20: Exit that causes REFUNDING transitions pool state
    /// @dev Changed behavior: exits can now trigger COOLDOWN→REFUNDING transition
    function test_exit_causesRefunding_succeeds() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);

        // Contribute exactly tier 1 threshold
        _fundToTier1(poolId);

        _advancePastDeadline(poolId);

        // Verify in COOLDOWN state
        assertEq(uint256(pool.getState(poolId)), uint256(TierPool.State.COOLDOWN));

        uint256 balanceBefore = mnee.balanceOf(contributor1);

        // Exit should succeed, even though it drops payable tier to 0
        vm.prank(contributor1);
        pool.exit(poolId);

        // Contributor received their funds back
        assertEq(mnee.balanceOf(contributor1) - balanceBefore, TIER1_THRESHOLD);
        assertEq(pool.getContribution(poolId, contributor1), 0);

        // Pool should now be in REFUNDING state
        assertEq(uint256(pool.getState(poolId)), uint256(TierPool.State.REFUNDING));
    }

    // ══════════════════════════════════════════════════════════════
    // FINALIZATION TESTS (T21-T24)
    // ══════════════════════════════════════════════════════════════

    /// @notice T21: Finalize pays recipient
    function test_finalize_paysRecipient() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);
        _fundToTier1(poolId);
        _advancePastCooldown(poolId);

        uint256 recipientBalanceBefore = mnee.balanceOf(recipient);

        pool.finalize(poolId);

        assertEq(mnee.balanceOf(recipient), recipientBalanceBefore + TIER1_THRESHOLD);
    }

    /// @notice T22: Finalize uses highest payable tier
    function test_finalize_usesHighestPayableTier() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);
        _attestTier2(poolId);

        // Fund to tier 2 threshold
        _fundToTier2(poolId);

        _advancePastCooldown(poolId);

        // Check payable tier
        assertEq(pool.getPayableTier(poolId), 2);

        // Check unlocked tier (should also be 2)
        assertEq(pool.getUnlockedTier(poolId), 2);

        pool.finalize(poolId);

        TierPool.Pool memory p = pool.getPool(poolId);
        assertEq(p.finalized, true);
    }

    /// @notice T23: Finalize when not PAYABLE reverts
    function test_finalize_notPayable_reverts() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);
        _fundToTier1(poolId);

        // ACTIVE state
        vm.expectRevert(TierPool.CannotFinalizeYet.selector);
        pool.finalize(poolId);

        // COOLDOWN state
        _advancePastDeadline(poolId);
        vm.expectRevert(TierPool.CannotFinalizeYet.selector);
        pool.finalize(poolId);
    }

    /// @notice T24: Finalize twice reverts
    function test_finalize_twice_reverts() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);
        _fundToTier1(poolId);
        _advancePastCooldown(poolId);

        pool.finalize(poolId);

        // After fix: AlreadyFinalized is checked before getState (which would return PAID)
        vm.expectRevert(TierPool.AlreadyFinalized.selector);
        pool.finalize(poolId);
    }

    // ══════════════════════════════════════════════════════════════
    // REFUNDS TESTS (T25-T28)
    // ══════════════════════════════════════════════════════════════

    /// @notice T25: Refund without finalize required
    function test_claimRefund_noFinalizeRequired() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);

        // Contribute under tier 1 threshold
        vm.prank(contributor1);
        pool.contribute(poolId, 100e18);

        _advancePastDeadline(poolId);

        // State should be REFUNDING (no finalize needed)
        assertEq(uint256(pool.getState(poolId)), uint256(TierPool.State.REFUNDING));

        uint256 balanceBefore = mnee.balanceOf(contributor1);

        vm.prank(contributor1);
        pool.claimRefund(poolId);

        assertEq(mnee.balanceOf(contributor1), balanceBefore + 100e18);
    }

    /// @notice T26: Refund returns exact contributed amount
    function test_claimRefund_exactAmount() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);

        uint256 amount1 = 150e18;
        uint256 amount2 = 200e18;

        vm.prank(contributor1);
        pool.contribute(poolId, amount1);
        vm.prank(contributor2);
        pool.contribute(poolId, amount2);

        _advancePastDeadline(poolId);

        vm.prank(contributor1);
        pool.claimRefund(poolId);
        assertEq(pool.getContribution(poolId, contributor1), 0);

        vm.prank(contributor2);
        pool.claimRefund(poolId);
        assertEq(pool.getContribution(poolId, contributor2), 0);
    }

    /// @notice T27: Refund twice reverts
    function test_claimRefund_twice_reverts() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);

        vm.prank(contributor1);
        pool.contribute(poolId, 100e18);

        _advancePastDeadline(poolId);

        vm.prank(contributor1);
        pool.claimRefund(poolId);

        vm.prank(contributor1);
        vm.expectRevert(TierPool.NothingToClaim.selector);
        pool.claimRefund(poolId);
    }

    /// @notice T28: Refund when not REFUNDING reverts
    function test_claimRefund_notRefunding_reverts() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);
        _fundToTier1(poolId);

        // ACTIVE state
        vm.prank(contributor1);
        vm.expectRevert(TierPool.NotInRefundingState.selector);
        pool.claimRefund(poolId);

        // COOLDOWN state (with payable tier)
        _advancePastDeadline(poolId);
        vm.prank(contributor1);
        vm.expectRevert(TierPool.NotInRefundingState.selector);
        pool.claimRefund(poolId);

        // PAYABLE state
        _advancePastCooldown(poolId);
        vm.prank(contributor1);
        vm.expectRevert(TierPool.NotInRefundingState.selector);
        pool.claimRefund(poolId);
    }
}
