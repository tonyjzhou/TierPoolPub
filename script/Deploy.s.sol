// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {TierPool} from "../src/TierPool.sol";

/// @title Deploy
/// @notice Deployment script for TierPool contract
contract Deploy is Script {
    // BSC Mainnet MNEE token address
    address public constant MNEE_BSC_MAINNET = 0x8ccedbAe4916b79da7F3F612EfB2EB93A2bFD6cF;

    function run() external returns (TierPool pool) {
        vm.startBroadcast();
        pool = new TierPool(MNEE_BSC_MAINNET);
        vm.stopBroadcast();
    }
}
