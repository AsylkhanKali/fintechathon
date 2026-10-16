// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title MockPriceFeed
/// @notice Chainlink AggregatorV3-compatible USDC/USD feed for the demo. The owner sets the price
///         on cue to trigger depeg scenarios. Testnet only, zero value.
contract MockPriceFeed is Ownable {
    uint8 public constant decimals = 8;
    string public constant description = "Mock USDC / USD (testnet, zero value)";
    uint256 public constant version = 1;

    struct Round {
        int256 answer;
        uint256 updatedAt;
    }

    uint80 public latestRound;
    mapping(uint80 => Round) internal _rounds;

    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);

    error RoundNotFound();

    constructor(address owner_, int256 initialAnswer) Ownable(owner_) {
        _setPrice(initialAnswer);
    }

    /// @param answer Price with 8 decimals, e.g. 0.97 USD = 97_000_000.
    function setPrice(int256 answer) external onlyOwner {
        _setPrice(answer);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return getRoundData(latestRound);
    }

    function getRoundData(uint80 id)
        public
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        Round memory r = _rounds[id];
        if (r.updatedAt == 0) revert RoundNotFound();
        return (id, r.answer, r.updatedAt, r.updatedAt, id);
    }

    function _setPrice(int256 answer) internal {
        uint80 id = ++latestRound;
        _rounds[id] = Round(answer, block.timestamp);
        emit AnswerUpdated(answer, id, block.timestamp);
    }
}
