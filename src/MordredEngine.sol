// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Mordred} from "./MordredToken.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
import {FlashLoan} from "src/Pool.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

/*
 * MordredEnrgine.sol is the engine of the whole protocol, is owned by the Pool.sol contract and is what powers swaps, as well as flash loans.
 *
*/
contract MordredEngine is Ownable, ReentrancyGuard {
    ////////////
    // errors //
    ////////////
    error MordredEngine__TokenAddressesAndPriceFeedAddressesShouldHaveSameLength();
    error MordredEngine__TransferFailed();
    error MordredEngine__TokenNotAllowedAsCollateral(address token);
    error MordredEngine__BreaksHealthFactor(uint256 healthFactor);
    error MordredEngine__MintFailed();
    error MordredEngine__HealthFactorOk();
    error MordredEngine__HealthFactorNotImproved();

    ///////////
    // types //
    ///////////
    using OracleLib for AggregatorV3Interface;

    ////////////
    // events //
    ////////////
    event CollateralDeposited(
        address indexed sender,
        address indexed token,
        uint256 indexed amout
    );
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );

    ///////////////
    // variables //
    ///////////////
    Mordred immutable mdd;
    mapping(address => address) private s_tokenToPriceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) s_userBalance;
    mapping(address => uint256) s_MordredMinted;
    address[] private s_collateralTokens;
    FlashLoan pool;
    uint256 constant LIQUIDATION_THRESHOLD = 50; // 200%
    uint256 constant LIQUIDATION_PRECISION = 100;
    uint256 constant LIQUIDATION_BONUS = 10;
    uint256 constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 MIN_HEALTH_FACTOR = 1e18;
    address tokenA;
    address tokenB;

    ///////////////
    // modifiers //
    ///////////////
    modifier isAllowedToken(address tokenAddress) {
        if (s_tokenToPriceFeeds[tokenAddress] == address(0)) {
            revert MordredEngine__TokenNotAllowedAsCollateral(tokenAddress);
        }
        _;
    }

    /////////////////
    // constructor //
    /////////////////
    constructor(
        address[] memory _tokenAddresses,
        address[] memory _priceFeedAddresses,
        Mordred _mdd,
        FlashLoan _pool,
        address _tokenA,
        address _tokenB
    ) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert MordredEngine__TokenAddressesAndPriceFeedAddressesShouldHaveSameLength();
        }
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_tokenToPriceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_collateralTokens.push(_tokenAddresses[i]);
        }
        mdd = _mdd;
        pool = _pool;
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    ///////////////
    // functions //
    ///////////////
    //@description: deposit collateral and mint Mordred
    //@param: tokenCollateralAddress is the address of the token to use as collateral
    //@param: amountCollateral is the amount of that token
    //@param: amountMordredToMint is the amount of Mordred to be minted
    //@param: sender is the user that call the deposit function of the pool contract
    function depositCollateralAndMintMordred(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountMordredToMint,
        address sender
    ) external onlyOwner {
        _depositCollateral(tokenCollateralAddress, amountCollateral, sender);
        _mintMordred(amountMordredToMint, sender);
    }

    //@description: funtion to redeem collateral and burn associated Mordred
    //@param: tokenCollateral is the address of the token to use as collateral
    //@param: amountCollateral is the amount of that token
    //@param: amountMordredToBurn is the  the amount of Mordred to be burned
    //@param: sender is the address of the user who called the withdraw function of the pool contract
    function redeemCollateralForMordred(
        address tokenCollateral,
        uint256 amountCollateral,
        uint256 amountMordredToBurn,
        address sender
    ) external onlyOwner {
        _burnMordred(amountMordredToBurn, sender, sender);
        _redeemCollateral(
            tokenCollateral,
            amountCollateral,
            address(this),
            sender
        );
    }

    //@description: function to burn some Mordred. The function may be called by some user if the collater is appreciating
    //@param: amount is the amount of Mordred to be minted
    //@param: sender is the caller of the function in the pool contract
    function mintMordred(uint256 amount, address sender) external onlyOwner {
        _mintMordred(amount, sender);
    }

    //@description: function to burn some Mordred. The function may be called by some user if the collater is depreciating, in order to avoid liquidation
    //@param: amount is the amount of Mordred to be burned
    //@param: sender is the caller of the function in the pool contract
    function burnMordred(uint256 amount, address sender) external onlyOwner {
        _burnMordred(amount, sender, sender);
    }

    //@description: function to deposit collateral. If the collateral depreciate, a user may want to call the function to avoid liquidation
    //@param: tokenCollateralAddress is the address of the token to use as collateral
    //@param: amountCollateral is the amount of that token
    //@param: sender is the user that call the redeem function of the pool contract
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address sender
    ) external onlyOwner {
        _depositCollateral(tokenCollateralAddress, amountCollateral, sender);
    }

    //@description: function to redeem collateral. If the collateral appreciate, a user may want to call the function
    //@param: tokenCollateralAddress is the address of the token to use as collateral
    //@param: amountCollateral is the amount of that token
    //@param: sender is the user that call the redeem function of the pool contract
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address sender
    ) external onlyOwner {
        IERC20(tokenCollateralAddress).approve(msg.sender, amountCollateral);
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            address(this),
            sender
        );
        _revertIfHealthFactorIsBroken(sender);
    }

    //@description: function to liquidate one's position once the health factor is broken
    //@param: collateral is the collateral address to liquidate from the user
    //@param: user is the one who broke the health factor
    //@param: debtToCover is the amount of Mordred to burn to improve the user's health factor
    //@param: sender is the address calling the function in the pool contract
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover,
        address sender
    ) external {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor >= MIN_HEALTH_FACTOR) {
            revert MordredEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );
        // give a 10% bonus
        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, sender);
        _burnMordred(debtToCover, user, sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= userHealthFactor)
            revert MordredEngine__HealthFactorNotImproved();
        _revertIfHealthFactorIsBroken(sender);
    }

    //@description: function to send a predefined amount of tokens to a borrower
    //@param: amount is the amount of tokens
    //@param: token is the address of the tokens
    //@param: sender is the address of the borrower
    function borrow(
        uint256 amount,
        address token,
        address borrower
    ) external onlyOwner nonReentrant {
        bool success = IERC20(token).transfer(borrower, amount);
        if (!success) revert MordredEngine__TransferFailed();
    }

    //@description: function to swap a predefined amount of tokenA for some tokenB. Swaps represent the secondary yield generator for the protocol
    function swapAForB(uint256 amountA, uint256 amountB) external {
        bool successOne = ERC20Mock(tokenA).transferFrom(
            msg.sender,
            address(this),
            amountA
        );
        if (!successOne) revert();

        bool successTwo = ERC20Mock(tokenB).transfer(msg.sender, amountB);
        if (!successTwo) revert();
    }

    //@description: function to swap a predefined amount of tokenB for some tokenA. Swaps represent the secondary yield generator for the protocol
    function swapBForA(uint256 amountB, uint256 amountA) external {
        bool successOne = ERC20Mock(tokenB).transferFrom(
            msg.sender,
            address(this),
            amountB
        );
        if (!successOne) revert();

        bool successTwo = ERC20Mock(tokenA).transfer(msg.sender, amountA);
        if (!successTwo) revert();
    }

    //@description: function to send a predefined amount of tokens to a borrower
    //@param: amount is the amount of tokens
    //@param: token is the address of the tokens
    //@param: sender is the address of the borrower
    function reward(
        //??? missing the swap collected fees
        uint256 amount,
        address token,
        address lender
    ) external onlyOwner nonReentrant {
        bool success = IERC20(token).transfer(lender, amount);
        if (!success) revert MordredEngine__TransferFailed();
    }

    //////////////////////
    // getter functions //
    //////////////////////
    //@description: function returning the amount of tokens deposited by the caller of the function
    //@param: user is the user whose balance is required
    //@param: token is the token address
    function getUserBalanceSingularToken(
        address user,
        address token
    ) external view returns (uint256) {
        return s_userBalance[user][token];
    }

    //@description: returns the number of Mordred minted by the user and the value in usd of it's collateral
    //@param: user is the user whose info are wanted
    function getAccountInfo(
        address user
    ) external view returns (uint256, uint256) {
        return _getAccountInfo(user);
    }

    //@description: function to get the price of tokens in USD
    //@param: token is the collateral address
    //@param: amount is the amount of the collateral
    function tokenPriceToUsd(
        address token,
        uint256 amount
    ) external view returns (uint256) {
        return _tokenPriceToUsd(token, amount);
    }

    //@description: function to get the amount of token one can buy using a predefined amount of usd
    //@param: token is the collateral address
    //@param: usdAmountInWei is the amount of usd. It has to be expressed in wei (i.e. 1e18)
    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_tokenToPriceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.stalePriceCheck();
        return ((usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    //@description: calculate a the health factor
    //@param: totalMordredMinted is the number of Mordred
    //@param: collateralValueInUsd is the collateral value in USD
    function healthFactor(
        uint256 totalMordredMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalMordredMinted, collateralValueInUsd);
    }

    //@description: give the value of the supplies collateral
    //@param: user is the user address
    function getCollateralAccountValueInUsd(
        address user
    ) public view returns (uint256) {
        uint256 totalCollateralValueInUsd;
        for (uint256 i; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_userBalance[user][token];

            totalCollateralValueInUsd += _tokenPriceToUsd(token, amount);
        }

        return totalCollateralValueInUsd;
    }

    //@description: function returning the additional feed precision
    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    //@description: function returning the precision
    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    //@description: function returning the health factor of a user
    //@param: user is the address whose health factor is wanted
    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    //@description: function returning the liquidation bonus
    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    //@description: function returning the addresses of the tokens allowed as collateral
    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    //@description: function returning the address of the price feed associated to a token
    //@param: token is the address of the collateral token
    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_tokenToPriceFeeds[token];
    }

    //@description: function returning the minimum health factor
    function getMinHealthFactor() external view returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    ////////////////////////////////////
    // internal and private functions //
    ////////////////////////////////////
    //@description: returns the number of Mordred minteb by the user and the value in usd of it's collateral
    //@param: user is the user whose info are required
    function _getAccountInfo(
        address user
    ) internal view returns (uint256, uint256) {
        uint256 collateralValueInUsd = getCollateralAccountValueInUsd(user);
        uint256 mddMinted = s_MordredMinted[user];
        return (mddMinted, collateralValueInUsd);
    }

    //@description: function to calculate the price of tokens in USD
    //@param: token is the collateral address
    //@param: amount is the amount of the collateral
    function _tokenPriceToUsd(
        address token,
        uint256 amount
    ) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_tokenToPriceFeeds[token]
        );

        (, int256 price, , , ) = priceFeed.stalePriceCheck();
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    //@description: function to burn some Mordred
    //@param: amount is the amount to be burn
    //@param: onBehalfOf is the address that lose his Mordred token
    //@param: from is the address that transfers the tokens
    function _burnMordred(
        uint256 amount,
        address onBehalfOf,
        address from
    ) internal {
        s_MordredMinted[onBehalfOf] -= amount;
        bool success = mdd.transferFrom(from, address(this), amount);
        if (!success) revert MordredEngine__TransferFailed();
        mdd.burn(amount, address(this));
    }

    //@description: function to mint some Mordred
    //@param: amountMordred is the amount of Mordred to mint. It has to be overcollateralized
    //@param: sender is the user that call the deposit function in the pool contract
    function _mintMordred(uint256 amountMordred, address sender) internal {
        s_MordredMinted[sender] += amountMordred;
        _revertIfHealthFactorIsBroken(sender);

        bool mintSuccess = mdd.mint(sender, amountMordred);
        if (!mintSuccess) revert MordredEngine__MintFailed();
    }

    //@description: function to deposit collateral
    //@param: tokenCollateralAddress is the address of the token to deposit as collateral
    //@param: amountCollateral is the amount of collateral to deposit
    //@param: sender is the user that call the deposit function of the pool contract
    function _depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address sender
    ) internal isAllowedToken(tokenCollateralAddress) {
        // transfer
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            sender,
            address(this),
            amountCollateral
        );
        if (!success) revert MordredEngine__TransferFailed();

        // update user's balance
        s_userBalance[sender][tokenCollateralAddress] += amountCollateral;

        emit CollateralDeposited(
            sender,
            tokenCollateralAddress,
            amountCollateral
        );
    }

    //@decsription: redeem collateral
    //@param: token is the collateral address
    //@param: amountCollateral is the amount of the collateral
    //@param: from is from which address the tokens are transfered
    //@param: to is to which address the tokens are transfered
    //@param: by is the address of the intermediate agent calling the function (the pool)
    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) internal isAllowedToken(tokenCollateralAddress) {
        // transfer
        IERC20(tokenCollateralAddress).approve(address(this), amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            from,
            to,
            amountCollateral
        );
        if (!success) revert MordredEngine__TransferFailed();

        // update user's balance
        s_userBalance[to][tokenCollateralAddress] -= amountCollateral;

        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    //@description: calculate how close to liquidation a user is. If the ratio goes under 1, the user is liquidated
    //@param: user is the user whose health factor is wanted
    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalMordredMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInfo(user);
        return _calculateHealthFactor(totalMordredMinted, collateralValueInUsd);
    }

    //@description: calculate a the health factor
    //@param: totalMordredMinted is the number of Mordred
    //@param: collateralValueInUsd is the collateral value in USD
    function _calculateHealthFactor(
        uint256 totalMordredMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalMordredMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / 100;
        return (collateralAdjustedForThreshold * 1e18) / totalMordredMinted;
    }

    //@description: revert if the health factor of a user is below 1e18s
    //@param: user is the person who wants to mint Mordred. The function assert check whether _user has enough collateral
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR)
            revert MordredEngine__BreaksHealthFactor(userHealthFactor);
    }
}
