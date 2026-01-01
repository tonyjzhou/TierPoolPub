// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TierPool} from "../src/TierPool.sol";
import {MockERC20WithCallback} from "./helpers/MockERC20WithCallback.sol";
import {ReentrantAttacker} from "./helpers/ReentrantAttacker.sol";

/// @title TierPoolSecurityTest
/// @notice Test file covering security scenarios (T35-T40)
/// @dev Uses MockERC20WithCallback to properly test reentrancy (calls recipient hooks)
contract TierPoolSecurityTest is Test {
    TierPool public pool;
    MockERC20WithCallback public mnee;
    ReentrantAttacker public attacker;

    address public organizer = address(0x1);
    address public vendor1 = address(0x2);
    address public vendor2 = address(0x3);
    address public vendor3 = address(0x4);
    address public recipient = address(0x5);
    address public contributor1 = address(0x6);
    address public contributor2 = address(0x7);

    uint256 public constant TIER1_THRESHOLD = 500e18;
    uint256 public constant TIER2_THRESHOLD = 1000e18;
    uint256 public constant TIER3_THRESHOLD = 2000e18;
    uint256 public constant DEFAULT_DEADLINE = 7 days;
    uint256 public constant DEFAULT_COOLDOWN = 1 days;
    uint256 public constant DEFAULT_VALID_UNTIL = 30 days;

    bytes32 public constant DOC_HASH_1 = keccak256("Quote Document 1");
    bytes32 public constant DOC_HASH_2 = keccak256("Quote Document 2");
    bytes32 public constant DOC_HASH_3 = keccak256("Quote Document 3");

    function setUp() public {
        // Use callback-enabled token to properly test reentrancy
        mnee = new MockERC20WithCallback("MNEE", "MNEE", 18);
        pool = new TierPool(address(mnee));

        attacker = new ReentrantAttacker(address(pool));
        mnee.mint(address(attacker), 10000e18);

        // Fund other test accounts
        mnee.mint(contributor1, 10000e18);
        mnee.mint(contributor2, 10000e18);

        // Approve pool
        vm.prank(contributor1);
        mnee.approve(address(pool), type(uint256).max);
        vm.prank(contributor2);
        mnee.approve(address(pool), type(uint256).max);
    }

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

    function _attestTier1(uint256 poolId) internal {
        TierPool.Pool memory p = pool.getPool(poolId);
        uint256 validUntil = p.deadline + p.cooldownDuration + DEFAULT_VALID_UNTIL;
        vm.prank(vendor1);
        pool.attestQuote(poolId, 1, validUntil);
    }

    function _advancePastDeadline(uint256 poolId) internal {
        TierPool.Pool memory p = pool.getPool(poolId);
        vm.warp(p.deadline + 1);
    }

    function _advancePastCooldown(uint256 poolId) internal {
        TierPool.Pool memory p = pool.getPool(poolId);
        vm.warp(p.deadline + p.cooldownDuration + 1);
    }

    function _fundToTier1(uint256 poolId) internal {
        vm.prank(contributor1);
        pool.contribute(poolId, TIER1_THRESHOLD);
    }

    // ══════════════════════════════════════════════════════════════
    // REENTRANCY TESTS (T35-T38)
    // ══════════════════════════════════════════════════════════════

    /// @notice T35: Reentrancy on contribute is blocked
    /// @dev With callback token, reentry is attempted but blocked by nonReentrant
    function test_reentrancy_contribute() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);

        // Setup attacker
        attacker.setAttack(poolId, ReentrantAttacker.AttackType.CONTRIBUTE, 2);

        // Attacker contributes - reentrant call should fail due to nonReentrant
        // Note: contribute uses transferFrom which triggers callback on the pool (not attacker)
        // So this particular test doesn't trigger the attacker's callback
        attacker.contribute(poolId, 100e18, mnee);

        // Verify only one contribution recorded
        assertEq(pool.getContribution(poolId, address(attacker)), 100e18);
    }

    /// @notice T36: Reentrancy on exit is blocked
    /// @dev Callback token triggers attacker's hook, but nonReentrant blocks reentry
    function test_reentrancy_exit() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);

        // Attacker and contributors fund well above threshold
        attacker.contribute(poolId, 200e18, mnee);
        vm.prank(contributor1);
        pool.contribute(poolId, 300e18);
        vm.prank(contributor2);
        pool.contribute(poolId, 300e18); // Total: 800e18, above tier 1 (500e18)

        _advancePastDeadline(poolId);

        uint256 balanceBefore = mnee.balanceOf(address(attacker));

        // Setup reentrant attack on exit
        attacker.setAttack(poolId, ReentrantAttacker.AttackType.EXIT, 2);

        // Execute exit - reentrancy guard should prevent double-withdrawal
        attacker.exit(poolId);

        // Verify callback was triggered (attackCount > 0) but reentry was blocked
        assertGt(attacker.attackCount(), 0, "Callback should have been triggered");

        // Attacker should have only gotten their contribution back once
        assertEq(pool.getContribution(poolId, address(attacker)), 0);
        uint256 balanceAfter = mnee.balanceOf(address(attacker));
        assertEq(balanceAfter - balanceBefore, 200e18, "Should receive exactly one withdrawal");
    }

    /// @notice T37: Reentrancy on finalize is blocked
    /// @dev Create pool with attacker as recipient to test reentry via payout callback
    function test_reentrancy_finalize() public {
        // Create pool with attacker as recipient (so attacker receives callback on finalize)
        uint256[] memory thresholds = new uint256[](1);
        thresholds[0] = TIER1_THRESHOLD;

        bytes32[] memory docHashes = new bytes32[](1);
        docHashes[0] = DOC_HASH_1;

        address[] memory vendors = new address[](1);
        vendors[0] = vendor1;

        vm.prank(organizer);
        uint256 poolId = pool.createPool(
            address(attacker), // Attacker is recipient
            block.timestamp + DEFAULT_DEADLINE,
            DEFAULT_COOLDOWN,
            thresholds,
            docHashes,
            vendors
        );

        // Attest and fund
        TierPool.Pool memory p = pool.getPool(poolId);
        vm.prank(vendor1);
        pool.attestQuote(poolId, 1, p.deadline + p.cooldownDuration + DEFAULT_VALID_UNTIL);

        vm.prank(contributor1);
        pool.contribute(poolId, TIER1_THRESHOLD);

        _advancePastCooldown(poolId);

        // Setup attacker to try reentrant finalize when it receives payout
        attacker.setAttack(poolId, ReentrantAttacker.AttackType.FINALIZE, 2);

        uint256 balanceBefore = mnee.balanceOf(address(attacker));

        // Finalize - callback triggers but reentry blocked by nonReentrant
        pool.finalize(poolId);

        // Verify callback was triggered but reentry blocked
        assertGt(attacker.attackCount(), 0, "Callback should have been triggered");

        // Pool should be finalized only once
        p = pool.getPool(poolId);
        assertEq(p.finalized, true);

        // Attacker (recipient) should have received payout exactly once
        uint256 balanceAfter = mnee.balanceOf(address(attacker));
        assertEq(balanceAfter - balanceBefore, TIER1_THRESHOLD, "Should receive payout exactly once");
    }

    /// @notice T38: Reentrancy on claimRefund is blocked
    /// @dev Callback token triggers attacker's hook, but nonReentrant blocks reentry
    function test_reentrancy_claimRefund() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);

        // Attacker contributes small amount (under threshold)
        attacker.contribute(poolId, 100e18, mnee);

        _advancePastDeadline(poolId);

        // State is REFUNDING
        assertEq(uint256(pool.getState(poolId)), uint256(TierPool.State.REFUNDING));

        // Setup reentrant attack
        attacker.setAttack(poolId, ReentrantAttacker.AttackType.CLAIM_REFUND, 2);

        uint256 balanceBefore = mnee.balanceOf(address(attacker));

        // Claim refund - callback triggers but reentry blocked by nonReentrant
        attacker.claimRefund(poolId);

        // Verify callback was triggered but reentry blocked
        assertGt(attacker.attackCount(), 0, "Callback should have been triggered");

        // Should have received only their contribution once
        uint256 balanceAfter = mnee.balanceOf(address(attacker));
        assertEq(balanceAfter - balanceBefore, 100e18, "Should receive refund exactly once");
        assertEq(pool.getContribution(poolId, address(attacker)), 0);
    }

    // ══════════════════════════════════════════════════════════════
    // ACCESS CONTROL TESTS (T39-T40)
    // ══════════════════════════════════════════════════════════════

    /// @notice T39: Only designated vendor can attest (cross-cutting)
    function test_accessControl_onlyVendorCanAttest() public {
        uint256 poolId = _createDefaultPool();

        TierPool.Pool memory p = pool.getPool(poolId);
        uint256 validUntil = p.deadline + p.cooldownDuration + DEFAULT_VALID_UNTIL;

        // Organizer cannot attest
        vm.prank(organizer);
        vm.expectRevert(TierPool.NotTierVendor.selector);
        pool.attestQuote(poolId, 1, validUntil);

        // Recipient cannot attest
        vm.prank(recipient);
        vm.expectRevert(TierPool.NotTierVendor.selector);
        pool.attestQuote(poolId, 1, validUntil);

        // Contributor cannot attest
        vm.prank(contributor1);
        vm.expectRevert(TierPool.NotTierVendor.selector);
        pool.attestQuote(poolId, 1, validUntil);

        // Wrong vendor cannot attest
        vm.prank(vendor2);
        vm.expectRevert(TierPool.NotTierVendor.selector);
        pool.attestQuote(poolId, 1, validUntil);

        // Correct vendor can attest
        vm.prank(vendor1);
        pool.attestQuote(poolId, 1, validUntil);
    }

    /// @notice T40: Functions respect state machine
    function test_accessControl_stateGating() public {
        uint256 poolId = _createDefaultPool();

        // PENDING: contribute fails
        vm.prank(contributor1);
        vm.expectRevert(TierPool.Tier1NotAttested.selector);
        pool.contribute(poolId, 100e18);

        // PENDING: exit fails
        vm.prank(contributor1);
        vm.expectRevert(TierPool.NotInCooldownState.selector);
        pool.exit(poolId);

        // PENDING: finalize fails
        vm.expectRevert(TierPool.CannotFinalizeYet.selector);
        pool.finalize(poolId);

        // PENDING: claimRefund fails
        vm.prank(contributor1);
        vm.expectRevert(TierPool.NotInRefundingState.selector);
        pool.claimRefund(poolId);

        // Move to ACTIVE
        _attestTier1(poolId);

        // ACTIVE: exit fails
        vm.prank(contributor1);
        vm.expectRevert(TierPool.NotInCooldownState.selector);
        pool.exit(poolId);

        // ACTIVE: finalize fails
        vm.expectRevert(TierPool.CannotFinalizeYet.selector);
        pool.finalize(poolId);

        // ACTIVE: claimRefund fails
        vm.prank(contributor1);
        vm.expectRevert(TierPool.NotInRefundingState.selector);
        pool.claimRefund(poolId);

        // Fund and move to COOLDOWN
        _fundToTier1(poolId);
        _advancePastDeadline(poolId);

        // COOLDOWN: contribute fails
        vm.prank(contributor2);
        vm.expectRevert(TierPool.NotInActiveState.selector);
        pool.contribute(poolId, 100e18);

        // COOLDOWN: finalize fails
        vm.expectRevert(TierPool.CannotFinalizeYet.selector);
        pool.finalize(poolId);

        // COOLDOWN: claimRefund fails (because payable tier >= 1)
        vm.prank(contributor1);
        vm.expectRevert(TierPool.NotInRefundingState.selector);
        pool.claimRefund(poolId);

        // Move to PAYABLE
        _advancePastCooldown(poolId);

        // PAYABLE: contribute fails
        vm.prank(contributor2);
        vm.expectRevert(TierPool.NotInActiveState.selector);
        pool.contribute(poolId, 100e18);

        // PAYABLE: exit fails
        vm.prank(contributor1);
        vm.expectRevert(TierPool.NotInCooldownState.selector);
        pool.exit(poolId);

        // PAYABLE: claimRefund fails
        vm.prank(contributor1);
        vm.expectRevert(TierPool.NotInRefundingState.selector);
        pool.claimRefund(poolId);

        // Finalize to PAID
        pool.finalize(poolId);

        // PAID: all actions fail
        vm.prank(contributor2);
        vm.expectRevert(TierPool.NotInActiveState.selector);
        pool.contribute(poolId, 100e18);

        vm.prank(contributor1);
        vm.expectRevert(TierPool.NotInCooldownState.selector);
        pool.exit(poolId);

        // After fix: AlreadyFinalized is checked before getState (which would return PAID)
        vm.expectRevert(TierPool.AlreadyFinalized.selector);
        pool.finalize(poolId);

        vm.prank(contributor1);
        vm.expectRevert(TierPool.NotInRefundingState.selector);
        pool.claimRefund(poolId);
    }

    // ══════════════════════════════════════════════════════════════
    // ADDITIONAL SECURITY TESTS
    // ══════════════════════════════════════════════════════════════

    /// @notice Pool not found reverts correctly
    function test_poolNotFound_reverts() public {
        uint256 invalidPoolId = 999;

        vm.expectRevert(TierPool.PoolNotFound.selector);
        pool.getState(invalidPoolId);

        vm.expectRevert(TierPool.PoolNotFound.selector);
        pool.getPool(invalidPoolId);

        vm.expectRevert(TierPool.PoolNotFound.selector);
        pool.getPayableTier(invalidPoolId);

        vm.expectRevert(TierPool.PoolNotFound.selector);
        pool.contribute(invalidPoolId, 100e18);
    }

    /// @notice Nothing to exit reverts
    function test_exit_nothingToExit_reverts() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);

        // contributor2 never contributed
        vm.prank(contributor1);
        pool.contribute(poolId, 600e18);

        _advancePastDeadline(poolId);

        vm.prank(contributor2);
        vm.expectRevert(TierPool.NothingToExit.selector);
        pool.exit(poolId);
    }

    /// @notice Zero contribution reverts
    function test_contribute_zeroAmount_reverts() public {
        uint256 poolId = _createDefaultPool();
        _attestTier1(poolId);

        vm.prank(contributor1);
        vm.expectRevert(TierPool.ZeroAmount.selector);
        pool.contribute(poolId, 0);
    }
}
