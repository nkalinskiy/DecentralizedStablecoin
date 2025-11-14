// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Nikita Kalinskii
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1:1 peg to the USD.
 * Properties:
 * - Exogenous Collateral (ETH & BTC)
 * - Algorithmically Stable
 * - Dollar Pegged
 *
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by wETH & wBTC.
 *
 * Our DSC system should always be overcollateralized. At no point should the value of all the collateral <= the $ backed value if all the DSC.
 *
 * @notice This contract is the core of the DSC System. It handles all the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI Stablecoin System) system.
 */
contract DSCEngine is ReentrancyGuard {
    // Errors //
    error DSCEngine__AmountMustBeAboveZero();
    error DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken(uint256 healthFactor);
    error DSCEngine__MintingFailed();

    // State variables //
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 150$ over collateralization
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeedsByToken;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable I_DSC;

    // Events //
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed token, uint256 indexed amount);

    // Modifiers //

    modifier moreThanZero(uint256 amount) {
        _moreThanZero(amount);
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        _isAllowedToken(tokenAddress);
        _;
    }

    // Constructor //
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeedsByToken[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        I_DSC = DecentralizedStableCoin(dscAddress);
    }

    // External function //

    /**
     * 
     * @param tokenCollateralAddress The address of the token to deposit as collateral (must be allowed)
     * @param amountCollateral The amount of collateral to deposit (must be greater than 0)
     * @param amountToMint The amount of DSC to mint (must be greater than 0)
     * @notice this function will deposit the collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountToMint) public {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountToMint);
    }

    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amount The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amount)
        public
        moreThanZero(amount)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amount;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amount);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * 
     * @param tokenCollateralAddress The address of the token to redeem collateral for (must be allowed)
     * @param amountCollateral The amount of collateral to redeem (must be greater than 0)
     * @param amountDscToBurn The amount of DSC to burn (must be greater than 0)
     * @notice this function will burn DSC and redeem collateral in one transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) 
        public moreThanZero(amountCollateral) nonReentrant {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(msg.sender, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param amountToMint the amount of decentralized stablecoin to mint
     * @notice they must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountToMint) public moreThanZero(amountToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = I_DSC.mint(msg.sender, amountToMint);
        if (!minted) {
            revert DSCEngine__MintingFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        s_dscMinted[msg.sender] -= amount;
        bool success = I_DSC.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        I_DSC.burn(amount);
    }

    function liquidate() external {}

    function getHealthFactor() external view {}

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount, and then get the price
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValueOfToken(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValueOfToken(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeedsByToken[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // ETH / USD has 8 decimal places
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    // Private and Internal Functions //

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * Returns how close to liquidation a user is.
     * If a user goes below 1, they can get liquidated.
     * @param user The address of the user to check
     */
    function _healthFactor(address user) private view returns (uint256) {
        // Check that total collateral value >= DSC minted
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     * @param user the user to check the health factor of
     * @notice reverts if the health factor is below the minimum threshold (not enough collateral)
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken(healthFactor);
        }
    }

    function _moreThanZero(uint256 amount) internal pure {
        if (amount == 0) {
            revert DSCEngine__AmountMustBeAboveZero();
        }
    }

    function _isAllowedToken(address tokenAddress) internal view {
        if (s_priceFeedsByToken[tokenAddress] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
    }
}
