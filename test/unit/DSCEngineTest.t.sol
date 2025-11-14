// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    DeployDSC deployer;
    HelperConfig helperConfig;

    address public weth;
    address public wbtc;
    address public wethUsdPriceFeed;
    address public wbtcUsdPriceFeed;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    // Price Feed Tests //

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15ETH * 2000 USD / ETH = 30000 USD
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValueOfToken(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    // Deposit Collateral Tests //

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }
}