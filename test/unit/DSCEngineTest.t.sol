// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    // IERC20 Events //
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
   
    // DSC Engine Events //
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    DeployDSC deployer;
    HelperConfig helperConfig;

    address public weth;
    address public wbtc;
    address public wethUsdPriceFeed;
    address public wbtcUsdPriceFeed;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant TEN_DSC = 10 ether;
    uint256 public constant TEN_K_DSC = 10 ether * 1000;
    uint256 public constant ETH_PRECISION = 1e18;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    // Modifiers // 
    modifier depositedCollateral() {
        _depositCollateral();
        _;
    }

    modifier depositedCollateralAndMintedDsc(uint256 amountToMint) {
        _depositCollateral();
        vm.startPrank(USER);
        engine.mintDsc(amountToMint);
        vm.stopPrank();
        _;
    }

    function _depositCollateral() private {
        vm.startPrank(USER);
        
        vm.expectEmit(true, true, true, false);
        emit Approval(USER, address(engine), AMOUNT_COLLATERAL);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        
        vm.expectEmit(true, true, true, false);
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false);
        emit Transfer(USER, address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        
        vm.stopPrank();
    }

    // Constructor Tests //

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testIfTokenLengthDoesNotMatchPriceFeedsLengthReverts() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testConstructorSetsTokenAddressesAndPriceFeedAddresses() public {
        tokenAddresses = engine.getTokenAddresses();
        priceFeedAddresses = engine.getPriceFeedAddresses();
        assertEq(tokenAddresses.length, 2);
        assertEq(priceFeedAddresses.length, 2);
        assertEq(tokenAddresses[0], weth);
        assertEq(tokenAddresses[1], wbtc);
        assertEq(priceFeedAddresses[0], wethUsdPriceFeed);
        assertEq(priceFeedAddresses[1], wbtcUsdPriceFeed);
    }

    // Getter Tests //

    function testGetAccountInformation() public depositedCollateral() {
        vm.startPrank(USER);
        engine.mintDsc(TEN_DSC);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, TEN_DSC);
        assertEq(collateralValueInUsd, 2000 * AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testGetCollateralValueInUsd() public depositedCollateral() {
        vm.startPrank(USER);
        
        ERC20Mock(wbtc).mint(USER, AMOUNT_COLLATERAL);
        ERC20Mock(wbtc).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(wbtc, AMOUNT_COLLATERAL);
        

        uint256 collateralValueInUsd = engine.getAccountCollateralValue(USER);
        uint256 btcUsdPrice = 1000e18;
        uint256 ethUsdPrice = 2000e18;
        uint256 expectedCollateralValueInUsd = (AMOUNT_COLLATERAL * btcUsdPrice / ETH_PRECISION) + (AMOUNT_COLLATERAL * ethUsdPrice / ETH_PRECISION);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);
        vm.stopPrank();
    }
    
    // Price Feed Tests //

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // 15ETH * 2000 USD / ETH = 30000 USD
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValueOfToken(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        // 2000 USD / ETH test price feed
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    // Deposit Collateral Tests //

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertIfCollateralTokenIsNotAllowed() public {
        ERC20Mock token = new ERC20Mock("MOCK", "MCK", USER, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(token), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral() {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
       
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositedAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositedAmount);
    }

    function testDepositCollateralAndMintDscSuccess() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, TEN_DSC);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, TEN_DSC);
        assertEq(collateralValueInUsd, 2000 * AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositCollateralRevertsIfTransferFails() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        vm.mockCall(
            weth, 
            abi.encodeWithSelector(
                ERC20Mock(weth).transferFrom.selector, 
                USER, 
                address(engine), 
                AMOUNT_COLLATERAL
            ), 
            abi.encode(false)
        );
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    // Mint DSC Tests //
    function testMintDscRevertsIfAmountIsZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);
        engine.mintDsc(0);
    }

    function testMintDscRevertsIfHealthFactorIsBroken() public depositedCollateral() {
        vm.startPrank(USER);
        vm.expectPartialRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        engine.mintDsc(AMOUNT_COLLATERAL * 2000);
        vm.stopPrank();
    }

    function testMintDscRevertsIfMintingFails() public depositedCollateral() {
        vm.startPrank(USER);
        vm.mockCall(
            address(dsc),
            abi.encodeWithSelector(dsc.mint.selector, USER, TEN_DSC),
            abi.encode(false)
        );
        vm.expectRevert(DSCEngine.DSCEngine__MintingFailed.selector);
        engine.mintDsc(TEN_DSC);
        vm.stopPrank();
    }

    // Burn DSC Tests //

    function testBurnDscSuccess() public depositedCollateralAndMintedDsc(TEN_DSC) {
        vm.startPrank(USER);
        dsc.approve(address(engine), TEN_DSC);
        engine.burnDsc(TEN_DSC);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, 2000 * AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testBurnDscRevertsIfAmountIsZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);
        engine.burnDsc(0);
    }

    // Redeem Collateral Tests //

    function testRedeemCollateralSuccess() public depositedCollateral() {
        assertEq(ERC20Mock(weth).balanceOf(USER), 0);
        
        vm.startPrank(USER);
        
        vm.expectEmit(true, true, true, false);
        emit CollateralRedeemed(USER, USER, weth, AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false);
        emit Transfer(address(engine), USER, AMOUNT_COLLATERAL);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, 0);
        assertEq(ERC20Mock(weth).balanceOf(USER), AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    function testRedeemCollateralRevertsIfAmountIsZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);
        engine.redeemCollateral(weth, 0);
    }

    function testRedeemCollateralRevertsIfTransferFails() public depositedCollateral() {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        vm.mockCall(
            weth,
            abi.encodeWithSelector(ERC20Mock(weth).transfer.selector, USER, AMOUNT_COLLATERAL),
            abi.encode(false)
        );
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertsIfHealthFactorIsBroken() public depositedCollateralAndMintedDsc(TEN_DSC) {
        vm.startPrank(USER);
        vm.expectPartialRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralForDscSuccess() public depositedCollateralAndMintedDsc(TEN_DSC) {
        assertEq(ERC20Mock(weth).balanceOf(USER), 0);
        assertEq(dsc.balanceOf(USER), TEN_DSC);

        vm.startPrank(USER);
        dsc.approve(address(engine), TEN_DSC);
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, TEN_DSC);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, 0);
        assertEq(ERC20Mock(weth).balanceOf(USER), AMOUNT_COLLATERAL);
        assertEq(dsc.balanceOf(USER), 0);
        vm.stopPrank();
    }

    // Liquidate Tests //
    function testLiquidateRevertsIfHealthFactorIsOk() public depositedCollateralAndMintedDsc(TEN_DSC) {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEnging__HealthFactorOk.selector);
        engine.liquidate(weth, USER, TEN_DSC);
        vm.stopPrank();
    }

    function testLiquidateRevertsIfAmountIsZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__AmountMustBeAboveZero.selector);
        engine.liquidate(weth, USER, 0);
    }

    function testLiquidateRevertsIfTokenIsNotAllowed() public {
        address notAllowedToken = makeAddr("notAllowedToken");
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.liquidate(notAllowedToken, USER, TEN_DSC);
    }

    function testLiquidateRevertsIfLiquidatorHasInsufficientDscAmount() public depositedCollateralAndMintedDsc(TEN_DSC) {
        uint256 liquidatorStartingWeth = AMOUNT_COLLATERAL * 100;
        ERC20Mock(weth).mint(LIQUIDATOR, liquidatorStartingWeth);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), liquidatorStartingWeth);
        engine.depositCollateralAndMintDsc(weth, liquidatorStartingWeth, TEN_DSC - 1 ether);
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(10);
        vm.expectRevert(DSCEngine.DSCEngine__InsufficientDscAmount.selector);
        engine.liquidate(weth, USER, TEN_DSC);
        vm.stopPrank();
    }

    function testFullLiquidationSuccess() public depositedCollateralAndMintedDsc(TEN_K_DSC) {
        uint256 FOUR_K_DSC = 4 ether * 1000;
        uint256 liquidatorMintedDsc = 15 ether * 1000;
        uint256 liquidatorStartingWeth = AMOUNT_COLLATERAL * 1000000;
        ERC20Mock(weth).mint(LIQUIDATOR, liquidatorStartingWeth);
        
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), liquidatorStartingWeth);
        engine.depositCollateralAndMintDsc(weth, liquidatorStartingWeth, liquidatorMintedDsc);

        // Just to immitate time passing, nothing would happen if we didn't do this.
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
        // ETH price drops to 1400 USD/ETH
        uint256 DROPPED_RATE = 1400e8;
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(int256(DROPPED_RATE));

        vm.startPrank(USER);
        uint256 brokenHealthFactorOfLiquidatedUser = engine.getHealthFactor();
        assert(brokenHealthFactorOfLiquidatedUser < MIN_HEALTH_FACTOR);

        vm.startPrank(LIQUIDATOR);
        assert(engine.getHealthFactor() > MIN_HEALTH_FACTOR);
        dsc.approve(address(engine), FOUR_K_DSC);
        engine.liquidate(weth, USER, FOUR_K_DSC);

        // Liquidator should have less DSC balance, should tak collateral from luquidated user position. His minted DSC is not changed.
        (uint256 liquidatorDscMinted, uint256 liquidatorCollateralValueInUsd) = engine.getAccountInformation(LIQUIDATOR);
        assertEq(liquidatorDscMinted, liquidatorMintedDsc);
        assertEq(liquidatorCollateralValueInUsd, engine.getUsdValueOfToken(weth, liquidatorStartingWeth));
        assertEq(dsc.balanceOf(LIQUIDATOR), liquidatorMintedDsc - FOUR_K_DSC);

        uint256 baseCollateralTakenFromLiquidatedUser = engine.getTokenAmountFromUsd(weth, FOUR_K_DSC);
        uint256 bonusCollateralTakenFromLiquidatedUser = baseCollateralTakenFromLiquidatedUser * 10 / 1e2;
        uint256 totalCollateralTakenFromLiquidatedUser = baseCollateralTakenFromLiquidatedUser + bonusCollateralTakenFromLiquidatedUser;
        assertEq(ERC20Mock(weth).balanceOf(LIQUIDATOR), totalCollateralTakenFromLiquidatedUser);
        assert(engine.getHealthFactor() > MIN_HEALTH_FACTOR);

        // Just to immitate time passing, nothing would happen if we didn't do this.
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // Liquidated user should have less collateral, less minted DSC, same amount of DSC on balance and improved health factor.
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        assertEq(totalDscMinted, TEN_K_DSC - FOUR_K_DSC);
        assertEq(collateralValueInUsd, engine.getUsdValueOfToken(weth, AMOUNT_COLLATERAL - totalCollateralTakenFromLiquidatedUser));
        assertEq(dsc.balanceOf(USER), TEN_K_DSC);
        vm.startPrank(USER);
        assert(engine.getHealthFactor() > brokenHealthFactorOfLiquidatedUser);
        vm.stopPrank();
    }

    function testLiquidateRevertsIfLiquidatorHealthFactorBroke() public depositedCollateralAndMintedDsc(TEN_K_DSC) {
        uint256 FOUR_K_DSC = 4 ether * 1000;
        uint256 liquidatorMintedDsc = TEN_K_DSC;
        uint256 liquidatorStartingWeth = AMOUNT_COLLATERAL;
        ERC20Mock(weth).mint(LIQUIDATOR, liquidatorStartingWeth);
        
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), liquidatorStartingWeth);
        engine.depositCollateralAndMintDsc(weth, liquidatorStartingWeth, liquidatorMintedDsc);
        
        // Just to immitate time passing, nothing would happen if we didn't do this.
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
        
        // ETH price drops to 1400 USD/ETH
        uint256 DROPPED_RATE = 1400e8;
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(int256(DROPPED_RATE));
        
        dsc.approve(address(engine), FOUR_K_DSC);
        vm.expectPartialRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        engine.liquidate(weth, USER, FOUR_K_DSC);

        vm.stopPrank();
    }
}