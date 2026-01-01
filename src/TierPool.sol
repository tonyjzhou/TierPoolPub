// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title TierPool
/// @notice Verifiable Group-Buy Coordinator with Enforced Quote Attestation & Exit Protection
/// @dev A trust-minimized group-buy escrow where contributors pool MNEE toward tiered funding goals,
///      vendors attest quotes on-chain with enforced validity periods, and contributors retain a
///      credible exit window.
contract TierPool is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ══════════════════════════════════════════════════════════════
    // CONSTANTS
    // ══════════════════════════════════════════════════════════════

    IERC20 public immutable MNEE;
    uint8 public constant MAX_TIERS = 3;
    uint256 public constant MAX_COOLDOWN = 30 days;

    // ══════════════════════════════════════════════════════════════
    // TYPES
    // ══════════════════════════════════════════════════════════════

    enum State {
        PENDING, // Pool created, waiting for Tier 1 attestation
        ACTIVE, // Tier 1 attested, contributions open
        COOLDOWN, // After deadline, exits allowed
        PAYABLE, // Cooldown expired, payable tier >= 1
        PAID, // Payout executed
        REFUNDING // No payable tier, refunds available
    }

    enum AttestationStatus {
        MISSING, // Vendor hasn't attested yet
        VALID, // Attested and not expired
        EXPIRED // Attested but validUntil has passed
    }

    struct Tier {
        uint256 threshold; // MNEE amount to unlock this tier
        bytes32 documentHash; // keccak256 of quote document bytes
        address vendor; // Vendor address (must call attestQuote)
        uint256 attestedAt; // Timestamp when vendor attested (0 = not attested)
        uint256 validUntil; // Quote expiration (set by vendor during attestation)
    }

    struct Pool {
        address organizer;
        address recipient;
        uint256 deadline;
        uint256 cooldownDuration;
        uint256 totalRaised;
        uint256 totalRefunded; // Track refunds for accurate accounting
        bool finalized;
    }

    // ══════════════════════════════════════════════════════════════
    // STATE
    // ══════════════════════════════════════════════════════════════

    uint256 public nextPoolId;
    mapping(uint256 => Pool) internal _pools;
    mapping(uint256 => Tier[]) internal _tiers;
    mapping(uint256 => mapping(address => uint256)) public contributions;

    // ══════════════════════════════════════════════════════════════
    // EVENTS
    // ══════════════════════════════════════════════════════════════

    event PoolCreated(
        uint256 indexed poolId,
        address indexed organizer,
        address indexed recipient,
        uint256 deadline,
        uint256 cooldownDuration
    );

    event TierAdded(uint256 indexed poolId, uint8 tierIndex, uint256 threshold, bytes32 documentHash, address vendor);

    event QuoteAttested(
        uint256 indexed poolId,
        uint8 tierIndex,
        address indexed vendor,
        uint256 validUntil,
        uint256 attestedAt,
        bytes32 commitmentHash
    );

    event Contributed(uint256 indexed poolId, address indexed contributor, uint256 amount, uint256 newTotal);

    event Exited(uint256 indexed poolId, address indexed contributor, uint256 amount, uint256 newTotal);

    event Finalized(
        uint256 indexed poolId,
        bool success,
        uint8 finalTier,
        bytes32 finalDocumentHash,
        address recipient,
        uint256 amount
    );

    event RefundClaimed(uint256 indexed poolId, address indexed contributor, uint256 amount);

    // ══════════════════════════════════════════════════════════════
    // ERRORS
    // ══════════════════════════════════════════════════════════════

    error PoolNotFound();
    error InvalidRecipient();
    error DeadlineMustBeFuture();
    error CooldownRequired();
    error CooldownTooLong();
    error InvalidTierCount();
    error TiersMustBeAscending();
    error ThresholdMustBePositive();
    error InvalidVendor();
    error InvalidDocumentHash();
    error NotInActiveState();
    error Tier1NotAttested();
    error ZeroAmount();
    error NotInCooldownState();
    error NothingToExit();
    error CannotFinalizeYet();
    error AlreadyFinalized();
    error NotInRefundingState();
    error NothingToClaim();
    error NotTierVendor();
    error AlreadyAttested();
    error ValidUntilTooEarly();
    error PoolAlreadyActive();

    // ══════════════════════════════════════════════════════════════
    // MODIFIERS
    // ══════════════════════════════════════════════════════════════

    modifier poolExists(uint256 poolId) {
        if (poolId >= nextPoolId) revert PoolNotFound();
        _;
    }

    // ══════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ══════════════════════════════════════════════════════════════

    constructor(address mneeToken) {
        MNEE = IERC20(mneeToken);
    }

    // ══════════════════════════════════════════════════════════════
    // WRITE FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    /// @notice Create a new pool with 1-3 tiers
    /// @param recipient Address that receives funds on successful payout
    /// @param deadline Unix timestamp after which contributions stop
    /// @param cooldownDuration Seconds for exit window after deadline
    /// @param thresholds MNEE amounts for each tier (ascending order)
    /// @param documentHashes keccak256 of quote document bytes for each tier
    /// @param vendors Vendor addresses for each tier (will call attestQuote)
    function createPool(
        address recipient,
        uint256 deadline,
        uint256 cooldownDuration,
        uint256[] calldata thresholds,
        bytes32[] calldata documentHashes,
        address[] calldata vendors
    ) external returns (uint256 poolId) {
        // Validation
        if (recipient == address(0)) revert InvalidRecipient();
        if (deadline <= block.timestamp) revert DeadlineMustBeFuture();
        if (cooldownDuration == 0) revert CooldownRequired();
        if (cooldownDuration > MAX_COOLDOWN) revert CooldownTooLong();

        uint256 tierCount = thresholds.length;
        if (tierCount == 0 || tierCount > MAX_TIERS) revert InvalidTierCount();
        if (documentHashes.length != tierCount || vendors.length != tierCount) {
            revert InvalidTierCount();
        }

        // Verify tiers are valid and ascending
        for (uint256 i = 0; i < tierCount; i++) {
            if (thresholds[i] == 0) revert ThresholdMustBePositive();
            if (i > 0 && thresholds[i] <= thresholds[i - 1]) revert TiersMustBeAscending();
            if (vendors[i] == address(0)) revert InvalidVendor();
            if (documentHashes[i] == bytes32(0)) revert InvalidDocumentHash();
        }

        // Create pool
        poolId = nextPoolId++;

        _pools[poolId] = Pool({
            organizer: msg.sender,
            recipient: recipient,
            deadline: deadline,
            cooldownDuration: cooldownDuration,
            totalRaised: 0,
            totalRefunded: 0,
            finalized: false
        });

        // Add tiers (attestation fields start empty)
        for (uint256 i = 0; i < tierCount; i++) {
            _tiers[poolId].push(
                Tier({
                    threshold: thresholds[i],
                    documentHash: documentHashes[i],
                    vendor: vendors[i],
                    attestedAt: 0,
                    validUntil: 0
                })
            );

            // Casting to uint8 is safe because tierCount <= MAX_TIERS (3)
            emit TierAdded(poolId, uint8(i + 1), thresholds[i], documentHashes[i], vendors[i]);
        }

        emit PoolCreated(poolId, msg.sender, recipient, deadline, cooldownDuration);
    }

    /// @notice Vendor attests to their quote for a specific tier
    /// @dev Only callable by the tier's designated vendor address
    /// @param poolId Pool to attest for
    /// @param tierIndex 1-based tier index (1, 2, or 3)
    /// @param validUntil Unix timestamp when this quote expires (must be >= deadline + cooldown)
    function attestQuote(uint256 poolId, uint8 tierIndex, uint256 validUntil) external poolExists(poolId) {
        Pool storage pool = _pools[poolId];

        // Can only attest before deadline (no point attesting after)
        if (block.timestamp >= pool.deadline) revert PoolAlreadyActive();

        // Convert to 0-based for internal access
        if (tierIndex == 0 || tierIndex > _tiers[poolId].length) {
            revert InvalidTierCount();
        }
        uint256 idx = tierIndex - 1;

        Tier storage tier = _tiers[poolId][idx];

        // Only the designated vendor can attest
        if (msg.sender != tier.vendor) revert NotTierVendor();

        // Can only attest once (immutable)
        if (tier.attestedAt != 0) revert AlreadyAttested();

        // validUntil must extend past earliest possible finalization
        uint256 minValidUntil = pool.deadline + pool.cooldownDuration;
        if (validUntil < minValidUntil) revert ValidUntilTooEarly();

        // Record attestation
        tier.attestedAt = block.timestamp;
        tier.validUntil = validUntil;

        // Compute commitment hash binding vendor to specific terms (FR-2.7)
        bytes32 commitmentHash =
            keccak256(abi.encode(poolId, tierIndex, tier.threshold, tier.documentHash, pool.recipient));

        emit QuoteAttested(poolId, tierIndex, msg.sender, validUntil, block.timestamp, commitmentHash);
    }

    /// @notice Contribute MNEE to a pool
    /// @dev Requires Tier 1 to be attested before accepting contributions
    /// @param poolId Pool to contribute to
    /// @param amount MNEE amount to contribute
    function contribute(uint256 poolId, uint256 amount) external nonReentrant poolExists(poolId) {
        State state = getState(poolId);
        if (state != State.ACTIVE) {
            if (state == State.PENDING) revert Tier1NotAttested();
            revert NotInActiveState();
        }
        if (amount == 0) revert ZeroAmount();

        // Balance-delta: safe for fee-on-transfer tokens (FR-3.5)
        uint256 balanceBefore = MNEE.balanceOf(address(this));
        MNEE.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = MNEE.balanceOf(address(this)) - balanceBefore;

        contributions[poolId][msg.sender] += received;
        _pools[poolId].totalRaised += received;

        emit Contributed(poolId, msg.sender, received, _pools[poolId].totalRaised);
    }

    /// @notice Exit during cooldown window (rage-quit)
    /// @dev Exit may cause pool to transition from COOLDOWN to REFUNDING if it drops payable tier to 0
    /// @param poolId Pool to exit from
    function exit(uint256 poolId) external nonReentrant poolExists(poolId) {
        if (getState(poolId) != State.COOLDOWN) revert NotInCooldownState();

        uint256 amount = contributions[poolId][msg.sender];
        if (amount == 0) revert NothingToExit();

        contributions[poolId][msg.sender] = 0;
        _pools[poolId].totalRaised -= amount;

        MNEE.safeTransfer(msg.sender, amount);

        emit Exited(poolId, msg.sender, amount, _pools[poolId].totalRaised);
    }

    /// @notice Finalize pool - execute payout (only needed for successful pools)
    /// @param poolId Pool to finalize
    function finalize(uint256 poolId) external nonReentrant poolExists(poolId) {
        // Check finalized first (before getState which returns PAID when finalized)
        if (_pools[poolId].finalized) revert AlreadyFinalized();

        State state = getState(poolId);
        if (state != State.PAYABLE) revert CannotFinalizeYet();

        _pools[poolId].finalized = true;

        Pool storage pool = _pools[poolId];
        uint8 finalTier = getPayableTier(poolId);
        Tier storage tier = _tiers[poolId][finalTier - 1];

        // Use tracked totalRaised minus refunds for accurate payout
        uint256 payoutAmount = pool.totalRaised - pool.totalRefunded;

        MNEE.safeTransfer(pool.recipient, payoutAmount);

        emit Finalized(poolId, true, finalTier, tier.documentHash, pool.recipient, payoutAmount);
    }

    /// @notice Claim refund when pool is in REFUNDING state
    /// @dev No finalize() call required - refunds are immediately available
    /// @param poolId Pool to claim from
    function claimRefund(uint256 poolId) external nonReentrant poolExists(poolId) {
        if (getState(poolId) != State.REFUNDING) revert NotInRefundingState();

        uint256 amount = contributions[poolId][msg.sender];
        if (amount == 0) revert NothingToClaim();

        contributions[poolId][msg.sender] = 0;
        _pools[poolId].totalRefunded += amount;

        MNEE.safeTransfer(msg.sender, amount);

        emit RefundClaimed(poolId, msg.sender, amount);
    }

    // ══════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    /// @notice Get the current state of a pool
    /// @dev State is derived from time, balance, and attestation status
    function getState(uint256 poolId) public view returns (State) {
        if (poolId >= nextPoolId) revert PoolNotFound();

        Pool storage pool = _pools[poolId];
        Tier[] storage tiers = _tiers[poolId];

        // Check if Tier 1 is attested (required for ACTIVE state)
        bool tier1Attested = _isAttestationValid(tiers[0]);

        // Before deadline
        if (block.timestamp < pool.deadline) {
            return tier1Attested ? State.ACTIVE : State.PENDING;
        }

        // Already finalized (only happens on successful payout)
        if (pool.finalized) {
            return State.PAID;
        }

        // After deadline: check if there's a payable tier
        uint8 payableTier = _calculatePayableTier(poolId);
        bool hasPayableTier = payableTier >= 1;

        // During cooldown window
        uint256 cooldownEnds = pool.deadline + pool.cooldownDuration;
        if (block.timestamp < cooldownEnds) {
            return hasPayableTier ? State.COOLDOWN : State.REFUNDING;
        }

        // After cooldown
        return hasPayableTier ? State.PAYABLE : State.REFUNDING;
    }

    /// @notice Get the highest tier that's both funded AND validly attested
    /// @return Payable tier (1-based), or 0 if none
    function getPayableTier(uint256 poolId) public view returns (uint8) {
        if (poolId >= nextPoolId) revert PoolNotFound();
        return _calculatePayableTier(poolId);
    }

    /// @notice Get the highest tier that's funded (regardless of attestation)
    /// @dev Uses current escrow balance (totalRaised - totalRefunded) for consistency
    /// @return Unlocked tier (1-based), or 0 if none
    function getUnlockedTier(uint256 poolId) public view returns (uint8) {
        if (poolId >= nextPoolId) revert PoolNotFound();

        uint256 raised = _pools[poolId].totalRaised - _pools[poolId].totalRefunded;
        Tier[] storage tiers = _tiers[poolId];

        uint8 tier = 0;
        for (uint256 i = 0; i < tiers.length; i++) {
            if (raised >= tiers[i].threshold) {
                // Casting to uint8 is safe because tiers.length <= MAX_TIERS (3)
                tier = uint8(i + 1);
            }
        }
        return tier;
    }

    /// @notice Get attestation status for a tier
    function getAttestationStatus(uint256 poolId, uint8 tierIndex) public view returns (AttestationStatus) {
        if (poolId >= nextPoolId) revert PoolNotFound();
        if (tierIndex == 0 || tierIndex > _tiers[poolId].length) {
            revert InvalidTierCount();
        }

        Tier storage tier = _tiers[poolId][tierIndex - 1];

        if (tier.attestedAt == 0) {
            return AttestationStatus.MISSING;
        }

        if (block.timestamp > tier.validUntil) {
            return AttestationStatus.EXPIRED;
        }

        return AttestationStatus.VALID;
    }

    function getPool(uint256 poolId) external view poolExists(poolId) returns (Pool memory) {
        return _pools[poolId];
    }

    function getTiers(uint256 poolId) external view poolExists(poolId) returns (Tier[] memory) {
        return _tiers[poolId];
    }

    function getTier(uint256 poolId, uint8 tierIndex) external view poolExists(poolId) returns (Tier memory) {
        if (tierIndex == 0 || tierIndex > _tiers[poolId].length) {
            revert InvalidTierCount();
        }
        return _tiers[poolId][tierIndex - 1];
    }

    function getContribution(uint256 poolId, address contributor) external view poolExists(poolId) returns (uint256) {
        return contributions[poolId][contributor];
    }

    function getCooldownEndsAt(uint256 poolId) external view poolExists(poolId) returns (uint256) {
        return _pools[poolId].deadline + _pools[poolId].cooldownDuration;
    }

    function getTierCount(uint256 poolId) external view poolExists(poolId) returns (uint256) {
        return _tiers[poolId].length;
    }

    /// @notice Helper to compute document hash (for off-chain verification)
    function computeDocumentHash(bytes calldata document) external pure returns (bytes32) {
        return keccak256(document);
    }

    // ══════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    function _calculatePayableTier(uint256 poolId) internal view returns (uint8) {
        uint256 raised = _pools[poolId].totalRaised - _pools[poolId].totalRefunded;
        Tier[] storage tiers = _tiers[poolId];

        uint8 payableTier = 0;
        for (uint256 i = 0; i < tiers.length; i++) {
            if (raised >= tiers[i].threshold && _isAttestationValid(tiers[i])) {
                // Casting to uint8 is safe because tiers.length <= MAX_TIERS (3)
                payableTier = uint8(i + 1);
            }
        }
        return payableTier;
    }

    function _isAttestationValid(Tier storage tier) internal view returns (bool) {
        return tier.attestedAt > 0 && block.timestamp <= tier.validUntil;
    }
}
