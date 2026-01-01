// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockFeeOnTransferToken
/// @notice Mock ERC20 that takes a 1% fee on transfers (for testing balance-delta pattern)
contract MockFeeOnTransferToken is ERC20 {
    uint8 private _decimals;
    uint256 public feePercent = 1; // 1% fee

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * feePercent) / 100;
        uint256 netAmount = amount - fee;
        // Burn the fee (simulates fee going somewhere else)
        _burn(msg.sender, fee);
        return super.transfer(to, netAmount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * feePercent) / 100;
        uint256 netAmount = amount - fee;
        // Burn the fee (simulates fee going somewhere else)
        _burn(from, fee);

        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, netAmount);
        return true;
    }
}
