// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20WithCallback
/// @notice ERC20 token that calls recipient hook after transfer (simulates ERC777-like behavior)
/// @dev Used to properly test reentrancy protection
contract MockERC20WithCallback is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @dev Override transfer to call recipient hook after successful transfer
    function transfer(address to, uint256 amount) public override returns (bool) {
        bool success = super.transfer(to, amount);
        if (success) {
            _callRecipientHook(msg.sender, to, amount);
        }
        return success;
    }

    /// @dev Override transferFrom to call recipient hook after successful transfer
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool success = super.transferFrom(from, to, amount);
        if (success) {
            _callRecipientHook(from, to, amount);
        }
        return success;
    }

    /// @dev Call hook on recipient if it's a contract
    function _callRecipientHook(address from, address to, uint256 amount) internal {
        if (to.code.length > 0) {
            // Try to call onTokenTransfer hook (similar to ERC677/ERC777)
            // Ignore return value and don't revert if call fails
            (bool success,) =
                to.call(abi.encodeWithSignature("onTokenTransfer(address,uint256,bytes)", from, amount, ""));
            // Silence unused variable warning
            success;
        }
    }
}
