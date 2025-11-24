// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin public dsc;
    DSCEngine public engine;
    DeployDSC public deployer;
    address public USER = makeAddr("user");

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine,) = deployer.run();
    }

    modifier asEngine() {
        vm.startPrank(address(engine));
        _;
        vm.stopPrank();
    }

    // Constructor tests //
    function testConstructor() public {
        assertEq(dsc.name(), "DecentralizedStableCoin");
        assertEq(dsc.symbol(), "DSC");
        assertEq(dsc.owner(), address(engine));
    }

    // Mint tests // 
    function testMintSuccess() public asEngine() {
        bool success = dsc.mint(address(engine), 100 ether);
        assertTrue(success);
        assertEq(dsc.balanceOf(address(engine)), 100 ether);
    }

    function testRevertIfMintToZeroAddress() public asEngine() {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MintToZeroAddress.selector);
        dsc.mint(address(0), 100 ether);
    }

    function testRevertIfMintAmountIsZero() public asEngine() {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeAboveZero.selector);
        dsc.mint(address(engine), 0);
    }

    function testMintRevertIfNotOwner() public {
        vm.prank(USER);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        dsc.mint(USER, 100 ether);
    }

    // Burn tests //
    function testBurnSuccess() public asEngine() {
        dsc.mint(address(engine), 100 ether);
        dsc.burn(100 ether);
        assertEq(dsc.balanceOf(address(engine)), 0);
    }

    function testRevertIfBurnAmountIsZero() public asEngine() {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__AmountMustBeAboveZero.selector);
        dsc.burn(0);
    }

    function testRevertIfBurnAmountExceedsBalance() public asEngine() {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(100 ether);
    }

    function testBurnRevertIfNotOwner() public {
        vm.prank(USER);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        dsc.burn(100 ether);
    }
}