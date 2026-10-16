// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

/// @notice Shared chain guard and deployment-file paths. Only zero-value networks are allowed.
abstract contract Common is Script {
    uint256 internal constant ANVIL_CHAIN_ID = 31337;
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;

    error UnsupportedChain(uint256 chainId);

    function _network() internal view returns (string memory) {
        if (block.chainid == ANVIL_CHAIN_ID) return "anvil";
        if (block.chainid == BASE_SEPOLIA_CHAIN_ID) return "base-sepolia";
        revert UnsupportedChain(block.chainid);
    }

    function _deploymentsDir() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/../deployments/");
    }

    function _deploymentFile() internal view returns (string memory) {
        return string.concat(_deploymentsDir(), _network(), ".json");
    }

    /// @dev The address the script broadcasts from (--sender / --private-key / --account).
    function _broadcaster() internal returns (address sender) {
        (, sender,) = vm.readCallers();
    }
}
