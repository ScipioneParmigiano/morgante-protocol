// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OracleLib} from "./libraries/OracleLib.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

// Contract that implements a simple pool for swaps between LINK and WBTC provided by the LP
// in order to diversificate their investment.

contract MockTokenSwap is ReentrancyGuard, Ownable {
    ////////////
    // errors //
    ////////////
    error MockTokenSwap__MoreThanZero();
    error MockTokenSwap__TokenNotAllowed();
    error MockTokenSwap__CantWithdrawMoreThanDeposited();

    ///////////
    // types //
    ///////////
    using OracleLib for AggregatorV3Interface;

    ///////////////
    // variables //
    ///////////////
    address tokenA;
    address tokenB;
    address priceFeedA;
    address priceFeedB;
    uint256 constant FEE = 1; // 0.1%
    uint256 constant FEE_PRECISION = 1000;
    uint256 constant PRECISION = 1e8;
    mapping(address user => mapping(address token => uint256 balance)) s_balance;

    ///////////////
    // modifiers //
    ///////////////
    modifier allowedToken(address token) {
        if (token != tokenA && token != tokenB)
            revert MockTokenSwap__TokenNotAllowed();
        _;
    }

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert MockTokenSwap__MoreThanZero();
        _;
    }

    modifier tokenAvailable(address token, uint256 amountToSwap) {
        if (amountToSwap >= ERC20Mock(token).balanceOf(address(this)))
            revert MockTokenSwap__MoreThanZero();
        _;
    }

    modifier withdrawnIsLessThanDeposited(
        uint256 amount,
        address withdrawer,
        address token
    ) {
        uint256 balance = s_balance[withdrawer][token];
        if (amount >= balance) {
            revert MockTokenSwap__CantWithdrawMoreThanDeposited();
        }
        _;
    }

    /////////////////
    // constructor //
    /////////////////
    constructor(
        address _tokenA,
        address _tokenB,
        address _priceFeedA,
        address _priceFeedB
    ) {
        tokenA = _tokenA;
        tokenB = _tokenB;
        priceFeedA = _priceFeedA;
        priceFeedB = _priceFeedB;
    }

    ///////////////
    // functions //
    ///////////////
    //@description: function to swap some tokenA for tokenB
    //@param: amountTokenToSwap is the amount of tokenA the user want to swap
    function swapAForB(
        uint256 amountTokenToSwap
    )
        external
        nonReentrant
        moreThanZero(amountTokenToSwap)
        tokenAvailable(tokenA, amountTokenToSwap)
    {
        uint256 amountToSend = calculateAmountAToSwapForB(amountTokenToSwap);

        bool success = ERC20Mock(tokenB).transfer(msg.sender, amountToSend);

        if (!success) revert();
    }

    //@description: function to swap some tokenB for tokenA
    //@param: amountTokenToSwap is the amount of tokenB the user want to swap
    function swapBForA(
        uint256 amountTokenToSwap
    )
        external
        nonReentrant
        moreThanZero(amountTokenToSwap)
        tokenAvailable(tokenB, amountTokenToSwap)
    {
        uint256 amountToSend = calculateAmountBToSwapForA(amountTokenToSwap);

        bool success = ERC20Mock(tokenA).transfer(msg.sender, amountToSend);

        if (!success) revert();
    }

    //@description: function to deposit some token to obtain a yield
    //@param: amount is the amount to deposit
    //@param: token is the address to deposit
    function deposit(
        uint256 amount,
        address token
    ) external moreThanZero(amount) onlyOwner nonReentrant {
        bool success = ERC20Mock(token).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        if (!success) revert();

        s_balance[msg.sender][token] += amount;
    }

    //@description: function to redeem some token from the pool
    //@param: amount is the amount to redeem
    //@param: token is the address to redeem
    function withdraw(
        uint256 amount,
        address token
    )
        external
        onlyOwner
        nonReentrant
        withdrawnIsLessThanDeposited(amount, msg.sender, token)
        moreThanZero(amount)
    {
        bool success = ERC20Mock(token).transfer(msg.sender, amount);
        if (!success) revert();

        s_balance[msg.sender][token] -= amount;
    }

    ////////////////////////
    // internal functions //
    ////////////////////////
    function calculateAmountAToSwapForB(
        uint256 amountToSwap
    ) internal view returns (uint256) {
        AggregatorV3Interface priceFA = AggregatorV3Interface(priceFeedA);
        AggregatorV3Interface priceFB = AggregatorV3Interface(priceFeedA);

        (, int256 priceA, , , ) = priceFA.stalePriceCheck();
        (, int256 priceB, , , ) = priceFB.stalePriceCheck();

        return (amountToSwap * (PRECISION * uint256(priceA))) / uint256(priceB);
    }

    function calculateAmountBToSwapForA(
        uint256 amountToSwap
    ) internal view returns (uint256) {
        AggregatorV3Interface priceFA = AggregatorV3Interface(priceFeedA);
        AggregatorV3Interface priceFB = AggregatorV3Interface(priceFeedA);

        (, int256 priceA, , , ) = priceFA.stalePriceCheck();
        (, int256 priceB, , , ) = priceFB.stalePriceCheck();

        return (amountToSwap * (PRECISION * uint256(priceB))) / uint256(priceA);
    }
}
