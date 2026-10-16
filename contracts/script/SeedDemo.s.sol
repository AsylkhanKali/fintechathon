// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Common} from "./Common.sol";
import {Treasury} from "../src/Treasury.sol";

/// @notice Applies the finance team's demo policy to a deployed Treasury, so the agent can run
///         without the setup form: caps, 60% max vault share, and 66 allowlisted payees
///         (60 contributors paid on the 1st, 6 vendors on the 15th).
///         Writes deployments/demo-payees.json (amounts in whole mUSDC) for the agent's policy.json.
///
///         Payee addresses are deterministic and fictional: keccak256("fintechathon-demo:<name>").
///         No private keys exist for them; they only ever receive zero-value test tokens.
contract SeedDemo is Common {
    uint256 internal constant APPROVAL_THRESHOLD = 40_000e6;
    uint256 internal constant PER_PAYMENT_CAP = 100_000e6;
    uint256 internal constant DAILY_CAP = 600_000e6;
    uint256 internal constant MAX_VAULT_SHARE_BPS = 6_000;

    function run() external {
        Treasury treasury = Treasury(vm.parseJsonAddress(vm.readFile(_deploymentFile()), ".Treasury"));
        (address[] memory payroll, string memory payrollJson) = _payroll();
        (address[] memory vendors, string memory vendorJson) = _vendors();

        vm.startBroadcast();
        treasury.setCaps(PER_PAYMENT_CAP, APPROVAL_THRESHOLD, DAILY_CAP);
        treasury.setMaxVaultShareBps(MAX_VAULT_SHARE_BPS);
        treasury.setPayees(payroll, true);
        treasury.setPayees(vendors, true);
        vm.stopBroadcast();

        string memory json = string.concat(
            '{"note":"Fictional demo payees for zero-value testnet tokens. No private keys exist for these addresses.",',
            '"limits":{"approvalThresholdUsd":40000,"perPaymentCapUsd":100000,"dailyPaymentCapUsd":600000,"maxVaultShareBps":6000},',
            '"payroll":{"dayOfMonth":1,"totalUsd":481000,"payees":[',
            payrollJson,
            ']},"vendors":{"dayOfMonth":15,"totalUsd":115000,"payees":[',
            vendorJson,
            "]}}"
        );
        vm.writeJson(json, string.concat(_deploymentsDir(), "demo-payees.json"));
    }

    /// @dev Finance spec: team size x average monthly salary = 481,000 total.
    function _payroll() internal pure returns (address[] memory addrs, string memory json) {
        string[5] memory teams = ["Engineering", "Research", "Product & Design", "Growth & Marketing", "Operations & Finance"];
        uint8[5] memory people = [25, 10, 8, 10, 7];
        uint16[5] memory salary = [9_000, 8_500, 8_000, 6_500, 6_000];

        addrs = new address[](60);
        uint256 k;
        for (uint256 t; t < 5; ++t) {
            for (uint256 i = 1; i <= people[t]; ++i) {
                string memory name = string.concat(teams[t], " contributor ", i < 10 ? "0" : "", vm.toString(i));
                addrs[k] = _demoAddress(name);
                json = string.concat(json, k == 0 ? "" : ",", _entry(name, teams[t], addrs[k], salary[t]));
                ++k;
            }
        }
    }

    /// @dev Finance spec vendors, 115,000 total.
    function _vendors() internal pure returns (address[] memory addrs, string memory json) {
        string[6] memory names = [
            "Cloud hosting and blockchain node provider",
            "Security audit firm (retainer)",
            "Freelance contractors (design, translation)",
            "Legal and compliance counsel",
            "Coworking space",
            "Data and analytics APIs"
        ];
        uint16[6] memory fees = [35_000, 25_000, 20_000, 15_000, 12_000, 8_000];

        addrs = new address[](6);
        for (uint256 i; i < 6; ++i) {
            addrs[i] = _demoAddress(names[i]);
            json = string.concat(json, i == 0 ? "" : ",", _entry(names[i], "Vendor", addrs[i], fees[i]));
        }
    }

    function _demoAddress(string memory name) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked("fintechathon-demo:", name)))));
    }

    function _entry(string memory name, string memory group, address addr, uint256 amountUsd)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            '{"name":"',
            name,
            '","group":"',
            group,
            '","address":"',
            vm.toString(addr),
            '","amount":',
            vm.toString(amountUsd),
            "}"
        );
    }
}
