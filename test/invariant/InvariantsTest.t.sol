// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handlers} from "test/invariant/Handlers.t.sol";

contract InvariantsTest is Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    IERC20 weth;
    IERC20 wbtc;
    Handlers handlers;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (, , address wethAddr, address wbtcAddr, ) = helperConfig
            .activeNetworkConfig();
        weth = IERC20(wethAddr);
        wbtc = IERC20(wbtcAddr);
        handlers = new Handlers(engine, dsc);
        targetContract(address(handlers));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = weth.balanceOf(address(engine));
        uint256 totalWbtcDeposited = wbtc.balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValueOfToken(
            address(weth),
            totalWethDeposited
        );
        uint256 wbtcValue = engine.getUsdValueOfToken(
            address(wbtc),
            totalWbtcDeposited
        );

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        engine.getTokenAddresses();
        engine.getPriceFeedAddresses();
        engine.getAccountInformation(msg.sender);
        engine.getAccountCollateralValue(msg.sender);
        engine.getHealthFactor();
        engine.getCollateralBalanceOfUser(msg.sender, address(weth));
        engine.getTokenAmountFromUsd(address(weth), 1e18);
        engine.getUsdValueOfToken(address(weth), 1e18);
    }
}
