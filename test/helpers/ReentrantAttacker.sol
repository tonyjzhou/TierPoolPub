// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TierPool} from "../../src/TierPool.sol";

/// @title ReentrantAttacker
/// @notice Mock contract for testing reentrancy protection
contract ReentrantAttacker {
    TierPool public pool;
    uint256 public poolId;
    uint256 public attackCount;
    uint256 public maxAttacks;
    AttackType public attackType;

    enum AttackType {
        EXIT,
        CLAIM_REFUND,
        FINALIZE,
        CONTRIBUTE
    }

    constructor(address _pool) {
        pool = TierPool(_pool);
    }

    function setAttack(uint256 _poolId, AttackType _type, uint256 _maxAttacks) external {
        poolId = _poolId;
        attackType = _type;
        maxAttacks = _maxAttacks;
        attackCount = 0;
    }

    // Called when this contract receives tokens
    function onTokenTransfer(address, uint256, bytes calldata) external returns (bool) {
        _attemptReentry();
        return true;
    }

    // Fallback for any token callback
    receive() external payable {
        _attemptReentry();
    }

    function _attemptReentry() internal {
        if (attackCount >= maxAttacks) return;
        attackCount++;

        if (attackType == AttackType.EXIT) {
            try pool.exit(poolId) {} catch {}
        } else if (attackType == AttackType.CLAIM_REFUND) {
            try pool.claimRefund(poolId) {} catch {}
        } else if (attackType == AttackType.FINALIZE) {
            try pool.finalize(poolId) {} catch {}
        } else if (attackType == AttackType.CONTRIBUTE) {
            // Would need approval first
            try pool.contribute(poolId, 100e18) {} catch {}
        }
    }

    // Allow this contract to be used as a contributor
    function contribute(uint256 _poolId, uint256 amount, IERC20 token) external {
        token.approve(address(pool), amount);
        pool.contribute(_poolId, amount);
    }

    function exit(uint256 _poolId) external {
        pool.exit(_poolId);
    }

    function claimRefund(uint256 _poolId) external {
        pool.claimRefund(_poolId);
    }

    function finalize(uint256 _poolId) external {
        pool.finalize(_poolId);
    }
}
