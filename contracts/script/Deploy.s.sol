// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Common} from "./Common.sol";
import {Treasury} from "../src/Treasury.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockYieldVault} from "../src/mocks/MockYieldVault.sol";
import {MockPriceFeed} from "../src/mocks/MockPriceFeed.sol";

/// @notice Deploys MockUSDC, MockPriceFeed, MockYieldVault and Treasury; wires roles; allowlists
///         the vault; mints the demo treasury balance; writes deployments/<network>.json.
///         The broadcaster becomes the owner (founder) of every contract.
///
///         Env: AGENT_ADDRESS (required), POLICY_HASH (optional).
contract Deploy is Common {
    uint256 internal constant START_BALANCE = 4_000_000e6; // finance spec demo treasury
    uint256 internal constant VAULT_RATE_BPS = 500; // 5% simulated APY
    int256 internal constant PRICE_ONE_DOLLAR = 1e8;

    function run() external {
        string memory network = _network();
        address agent = vm.envAddress("AGENT_ADDRESS");
        bytes32 policyHash = vm.envOr("POLICY_HASH", bytes32(0));
        uint256 startBlock = block.number;

        vm.startBroadcast();
        address owner = _broadcaster();
        MockUSDC usdc = new MockUSDC(owner);
        MockPriceFeed feed = new MockPriceFeed(owner, PRICE_ONE_DOLLAR);
        MockYieldVault vault = new MockYieldVault(usdc, owner, VAULT_RATE_BPS);
        Treasury treasury = new Treasury(usdc, owner, agent);

        usdc.setMinter(address(vault), true);
        treasury.setVault(address(vault), true);
        if (policyHash != bytes32(0)) treasury.setPolicyHash(policyHash);
        usdc.mint(address(treasury), START_BALANCE);
        vm.stopBroadcast();

        string memory k = "deployment";
        vm.serializeString(k, "network", network);
        vm.serializeUint(k, "chainId", block.chainid);
        vm.serializeUint(k, "startBlock", startBlock);
        vm.serializeAddress(k, "owner", owner);
        vm.serializeAddress(k, "agent", agent);
        vm.serializeAddress(k, "MockUSDC", address(usdc));
        vm.serializeAddress(k, "MockPriceFeed", address(feed));
        vm.serializeAddress(k, "MockYieldVault", address(vault));
        string memory json = vm.serializeAddress(k, "Treasury", address(treasury));
        vm.createDir(_deploymentsDir(), true);
        vm.writeJson(json, _deploymentFile());
    }
}
