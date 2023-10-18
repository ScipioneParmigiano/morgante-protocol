// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IFlashLoan} from "./InterfaceFlashLoan.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {MordredEngine} from "src/MordredEngine.sol";
import {Mordred} from "src/MordredToken.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/security/Pausable.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/*
 * The following contract is a liquidity pool in which users can deposit some predefined tokens to receive an interest.
 * The interest come from the flash loans that the pool provide.
 */

contract FlashLoan is ReentrancyGuard, Ownable, Pausable {
    ////////////
    // errors //
    ////////////
    error FlashLoan__TokenAddressesAndPriceFeedAddressesShouldHaveSameLength();
    error FlashLoan__MustBeMoreThanZero();
    error FlashLoan__TransferFailed();
    error FlashLoan__TokenNotAllowed(address tokenAddress);
    error FlashLoan__InsufficientFunds();
    error FlashLoan__CantWithdrawMoreThanDeposited(
        uint256 amountToWitdraw,
        uint256 withdrawerBalance
    );
    error FlashLoan__aWeekHasNotElapsed();

    ///////////
    // types //
    ///////////
    using OracleLib for AggregatorV3Interface;

    ////////////
    // events //
    ////////////
    event depositedToken(
        address indexed sender,
        address indexed token,
        uint256 indexed amount
    );
    event withdrawnToken(
        address indexed sender,
        address indexed token,
        uint256 indexed amount
    );
    event newFlashLoan(
        address indexed sender,
        address indexed token,
        uint256 indexed amount
    );
    event receivedPremium(address indexed token, uint256 indexed amount);
    event updatedFlashLoansFee(uint256 indexed newFee);

    ///////////////
    // variables //
    ///////////////
    uint256 poolBalanceLink;
    uint256 poolBalanceWbtc;
    uint256 fee; // is (price of the flash loan in percentage + 1) * 1e18
    uint256 constant PRECISION = 1e18;
    uint256 constant ACCURACY = 1e12;
    address[] s_collateralTokens;
    address[] s_priceFeeds;
    mapping(address lender => mapping(address collateralAddress => uint256 yield)) s_lendersYields;
    mapping(address => address) s_tokenToPriceFeeds;
    mapping(address => uint256) lenderShare;
    Mordred immutable mdd;
    MordredEngine mdde;
    mapping(address userAddress => mapping(address collateralAddress => uint256 amount)) s_userCollateralBalance;
    mapping(address => uint256) s_collectedFees;
    mapping(address token => uint256 poolBalance) s_tokenToPoolBalance;
    uint256 constant FEE = 1; // 0.1% for swaps
    uint256 constant FEE_PRECISION = 1000; // precision for swaps
    address tokenA;
    address tokenB;

    ///////////////
    // modifiers //
    ///////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) revert FlashLoan__MustBeMoreThanZero();
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_tokenToPriceFeeds[tokenAddress] == address(0)) {
            revert FlashLoan__TokenNotAllowed(tokenAddress);
        }
        _;
    }

    modifier withdrawnIsLessThanDeposited(
        uint256 amount,
        address withdrawer,
        address token
    ) {
        uint256 balance = mdde.getUserBalanceSingularToken(withdrawer, token);
        if (amount >= balance) {
            revert FlashLoan__CantWithdrawMoreThanDeposited(amount, balance);
        }
        _;
    }

    modifier tokenAvailable(address token, uint256 amountToSwap) {
        if (amountToSwap >= ERC20Mock(token).balanceOf(address(this))) revert();
        _;
    }

    /////////////////
    // constructor //
    /////////////////
    constructor(
        address[] memory _tokenAddresses,
        address[] memory _priceFeedAddresses,
        uint256 _fee
    ) {
        fee = _fee;
        mdd = new Mordred();
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert FlashLoan__TokenAddressesAndPriceFeedAddressesShouldHaveSameLength();
        }

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_tokenToPriceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_collateralTokens.push(_tokenAddresses[i]);
            s_priceFeeds.push(_priceFeedAddresses[i]);
        }

        mdde = new MordredEngine(
            _tokenAddresses,
            _priceFeedAddresses,
            mdd,
            this,
            _tokenAddresses[0],
            _tokenAddresses[1]
        );
        tokenA = _tokenAddresses[0];
        tokenB = _tokenAddresses[1];
        mdd.transferOwnership(address(mdde));
        mdde.transferOwnership(address(this));
    }

    ///////////////
    // functions //
    ///////////////
    //@description: function that allows users to deposit a predefined amount of tokens
    //               to gain a yield. It mint to the user some mdd tokens
    //@param: amountCollateral is the amount of that token
    //@param: amountMordredToMint is the amount of Mordred to be minted
    //@param: tokenCollateralAddress is the address of the token to be used as collateral
    function deposit(
        uint256 amountCollateral,
        uint256 amountMordredToMint,
        address tokenCollateralAddress
    )
        external
        nonReentrant
        moreThanZero(amountCollateral)
        moreThanZero(amountMordredToMint)
        isAllowedToken(tokenCollateralAddress)
    {
        // Mordred mint logic and deposit
        mdde.depositCollateralAndMintMordred(
            tokenCollateralAddress,
            amountCollateral,
            amountMordredToMint,
            msg.sender
        );

        // update pool's balance
        s_tokenToPoolBalance[tokenCollateralAddress] += amountCollateral;

        // update user balance
        s_userCollateralBalance[tokenCollateralAddress][
            tokenCollateralAddress
        ] += amountCollateral;

        emit depositedToken(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
    }

    //@description: funtion to redeem collateral and burn associated Mordred
    //@param: tokenCollateral is the address of the token to use as collateral
    //@param: amountCollateral is the amount of that token
    //@param: amountMordredToBurn is the amount of Mordred to be burned
    //@note: it's not possible to redeem all the amount deposited, but at least one wei in strapped in the protocol
    function withdraw(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountMordredToBurn
    )
        external
        nonReentrant
        moreThanZero(amountCollateral)
        moreThanZero(amountMordredToBurn)
        isAllowedToken(tokenCollateralAddress)
        withdrawnIsLessThanDeposited(
            amountCollateral,
            msg.sender,
            tokenCollateralAddress
        )
        whenNotPaused
    {
        // Mordred burn logic and redeem
        mdde.redeemCollateralForMordred(
            tokenCollateralAddress,
            amountCollateral,
            amountMordredToBurn,
            msg.sender
        );

        // update pool's balance
        s_tokenToPoolBalance[tokenCollateralAddress] -= amountCollateral;

        // update user balance
        s_userCollateralBalance[tokenCollateralAddress][
            tokenCollateralAddress
        ] -= amountCollateral;

        emit withdrawnToken(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
    }

    //@description: function to allow users to borrow tokens from the smart contract
    //@param: amount is the amount to borrow
    //@param: token is the address of the tokens to borrow
    function borrowFlashLoan(
        uint256 amount,
        address token
    ) external nonReentrant moreThanZero(amount) isAllowedToken(token) {
        // check the amount to borrow is less than the amount available
        uint256 startingBalance = getPoolBalanceSingularToken(token);
        if (amount > startingBalance) revert FlashLoan__InsufficientFunds();
        _pause();

        uint256 mddeBalance = IERC20(token).balanceOf(address(mdde));

        // transfer to the borrower
        mdde.borrow(amount, token, msg.sender);

        // user uses the borrowed amount and transfer back to mdde
        IFlashLoan(msg.sender).useBorrowedFunds(token, amount);

        // check the user has sent the correct amount
        uint256 collectedFee = (amount * fee - PRECISION) / PRECISION;
        if (
            IERC20(token).balanceOf(address(mdde)) != mddeBalance + collectedFee
        ) return ();

        s_collectedFees[token] += collectedFee;
        _unpause();
        emit newFlashLoan(msg.sender, token, amount);
    }

    //@description: function that allows users to redeem their rewards
    //@param tokenAddress is the address of the token that you wnat to get as reward
    //@note: in order to ensure fairness, one can call this function only once time per week
    function claimReward(address tokenAddress) external nonReentrant {
        uint256 amount = getUserRewards(tokenAddress);
        if (amount == 0) revert();
        mdde.reward(amount, tokenAddress, msg.sender);

        s_collectedFees[tokenAddress] -= amount;
    }

    //@description: function to deposit collateral. If the collateral depreciate, a user may want to call the function to avoid liquidation
    //@param: tokenCollateralAddress is the address of the token to use as collateral
    //@param: amountCollateral is the amount of that token
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        isAllowedToken(tokenCollateralAddress)
        moreThanZero(amountCollateral)
    {
        mdde.depositCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender
        );

        // update pool balance
        s_tokenToPoolBalance[tokenCollateralAddress] += amountCollateral;

        // update user balance
        s_userCollateralBalance[tokenCollateralAddress][
            tokenCollateralAddress
        ] += amountCollateral;
    }

    //@description: function to mint some Mordred. The function may be called by some user if the collater is appreciating
    //@description: function to redeem collateral. If the collateral appreciate, a user may want to call the function
    //@param: tokenCollateralAddress is the address of the token to use as collateral
    //@param: amountCollateral is the amount of that token
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        withdrawnIsLessThanDeposited(
            amountCollateral,
            msg.sender,
            tokenCollateralAddress
        )
    {
        // reedeem collateral
        mdde.redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender
        );

        // update pool balance
        s_tokenToPoolBalance[tokenCollateralAddress] -= amountCollateral;

        // update user balance
        s_userCollateralBalance[tokenCollateralAddress][
            tokenCollateralAddress
        ] -= amountCollateral;
    }

    //@param: amount is the amount of Mordred to be minted
    function mintMordred(uint256 amount) external moreThanZero(amount) {
        mdde.mintMordred(amount, msg.sender);
    }

    //@description: function to burn some Mordred. The function may be called by some user if the collater is depreciating, in order to avoid liquidation
    //@param: amount is the amount of Mordred to be burned
    function burnMordred(uint256 amount) external moreThanZero(amount) {
        mdde.burnMordred(amount, msg.sender);
    }

    //@description: function to liquidate one's position once the health factor is broken
    //@param: collateral is the collateral address to liquidate from the user
    //@param: user is the one who broke the health factor
    //@param: debtToCover is the amount of Mordred to burn to improve the user's health factor
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) isAllowedToken(collateral) {
        mdde.liquidate(collateral, user, debtToCover, msg.sender);
    }

    //@description: function to change the flash loan fee
    //@param: newFee is the new fee level (e.g. 1003000000000000000000 stands for 0.3%)
    function newFlashLoansRate(uint256 newFee) external onlyOwner {
        fee = newFee;

        emit updatedFlashLoansFee(newFee);
    }

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
        uint256 amountA = calculateAmountAToSwapForB(amountTokenToSwap);
        uint256 amountB = (amountA * (PRECISION)) / (PRECISION + FEE);

        mdde.swapAForB(amountA, amountB);

        s_collectedFees[tokenA] += amountA - amountB;
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
        uint256 amountB = calculateAmountBToSwapForA(amountTokenToSwap);
        uint256 amountA = (amountB * (PRECISION)) / (PRECISION + FEE);

        mdde.swapBForA(amountB, amountA);

        s_collectedFees[tokenA] += amountA - amountB;
    }

    //////////////////////
    // getter functions //
    //////////////////////
    //@description: function returning the amount of tokens deposited by the caller of the function
    //@param: user is the user whose balance is required
    //@param: token the token address
    function getUserBalanceSingularToken(
        address user,
        address token
    ) public view returns (uint256) {
        return mdde.getUserBalanceSingularToken(user, token);
    }

    function getmddAmountOwned(address user) public view returns (uint256) {
        return mdd.balanceOf(user);
    }

    //@description: function returning the total amount of a particular token that the pool contains
    //@param: token is the collateral address
    function getPoolBalanceSingularToken(
        address token
    ) public view returns (uint256) {
        return s_tokenToPoolBalance[token];
    }

    //@description: function returning the address of the allowed tokens
    function getTokenAddresses() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    //@description: function returning the address of the price oracle of the allowed tokens
    function getPriceFeedAddresses() external view returns (address[] memory) {
        return s_priceFeeds;
    }

    //@description: function returning the fee of the flash loans.
    //               Note that the actual fee is fee/FEE_PRECISION - 1
    function getFee() external view returns (uint256) {
        return fee;
    }

    //@description: function returning the address of the Mordred token
    function returnMordredTokenAddress() external view returns (address) {
        return address(mdd);
    }

    //@description: function returning the address of MordredEngine
    function returnMordredEngineAddress() external view returns (address) {
        return address(mdde);
    }

    //@description: function returning the precision
    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    //@description: give the value of the supplies collateral
    //@param: user is the user address
    function getCollateralAccountValueInUsd(
        address user
    ) external view returns (uint256) {
        return mdde.getCollateralAccountValueInUsd(user);
    }

    //@description: function returning the rewards a user can claim
    //@param: tokenAddress is the address of the token whose rewards you are interested in
    function getUserRewards(
        address tokenAddress
    ) public view returns (uint256) {
        if (s_tokenToPoolBalance[tokenAddress] > 0) {
            return
                (s_userCollateralBalance[msg.sender][tokenAddress] *
                    s_collectedFees[tokenAddress]) /
                s_tokenToPoolBalance[tokenAddress];
        } else {
            return 0;
        }
    }

    function calculateAmountAToSwapForB(
        uint256 amountToSwap
    ) internal view returns (uint256) {
        AggregatorV3Interface priceFA = AggregatorV3Interface(
            s_tokenToPriceFeeds[tokenA]
        );
        AggregatorV3Interface priceFB = AggregatorV3Interface(
            s_tokenToPriceFeeds[tokenB]
        );

        (, int256 priceA, , , ) = priceFA.stalePriceCheck();
        (, int256 priceB, , , ) = priceFB.stalePriceCheck();

        return
            (((amountToSwap * (PRECISION * uint256(priceA))) /
                uint256(priceB)) * (FEE_PRECISION + FEE)) / FEE_PRECISION;
    }

    function calculateAmountBToSwapForA(
        uint256 amountToSwap
    ) internal view returns (uint256) {
        AggregatorV3Interface priceFA = AggregatorV3Interface(
            s_tokenToPriceFeeds[tokenA]
        );
        AggregatorV3Interface priceFB = AggregatorV3Interface(
            s_tokenToPriceFeeds[tokenB]
        );

        (, int256 priceA, , , ) = priceFA.stalePriceCheck();
        (, int256 priceB, , , ) = priceFB.stalePriceCheck();

        return
            (((amountToSwap * (PRECISION * uint256(priceB))) /
                uint256(priceA)) * (FEE_PRECISION + FEE)) / FEE_PRECISION;
    }
}
