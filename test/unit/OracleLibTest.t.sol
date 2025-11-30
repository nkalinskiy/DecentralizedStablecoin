// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {OracleLib} from "../../src/libs/OracleLib.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract OracleLibTest is Test {
    using OracleLib for AggregatorV3Interface;

    uint256 public constant TIMEOUT = 3 hours;

    function setUp() public {}

    function testRevertIfStalePrice() public {
        AggregatorV3Interface priceFeed = new MockV3Aggregator(
            18,
            1000000000000000000
        );
        vm.warp(block.timestamp + TIMEOUT + 1);
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        priceFeed.staleCheckLatestRoundData();
    }

    function testDoesNotRevertIfNotStale() public {
        AggregatorV3Interface priceFeed = new MockV3Aggregator(
            18,
            1000000000000000000
        );
        vm.warp(block.timestamp + TIMEOUT - 1);
        priceFeed.staleCheckLatestRoundData();
    }
}
