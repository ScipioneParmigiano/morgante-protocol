// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {StdCheats} from "lib/forge-std/src/StdCheats.sol";
import {Mordred} from "src/MordredToken.sol";
import {MordredEngine} from "src/MordredEngine.sol";
import {DeployFlashLoan} from "script/DeployFlashLoan.s.sol";
import {CorollaryFunctions} from "script/CorollaryFunctions.s.sol";
import {FlashLoan} from "src/Pool.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "script/mocks/MockV3Aggregator.s.sol";
import {FlashLoan} from "src/Pool.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {FlashLoanExampleForBorrowers} from "src/FlashLoanExampleForBorrowers.sol";

contract Handler is Test {
    MordredEngine mdde;
    FlashLoan pool;
    Mordred mdd;
    FlashLoanExampleForBorrowers flashLoan =
        new FlashLoanExampleForBorrowers(address(pool));
    ERC20Mock link;
    ERC20Mock wbtc;
    MockV3Aggregator public linkUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    address[] public users;

    constructor(MordredEngine _mdde, Mordred _mdd, FlashLoan _pool) {
        mdd = _mdd;
        mdde = _mdde;
        pool = _pool;

        address[] memory collateralTokens = mdde.getCollateralTokens();
        link = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        linkUsdPriceFeed = MockV3Aggregator(
            mdde.getCollateralTokenPriceFeed(address(link))
        );
        btcUsdPriceFeed = MockV3Aggregator(
            mdde.getCollateralTokenPriceFeed(address(wbtc))
        );
        link.mint(address(this), 1000 ether);
        wbtc.mint(address(this), 1000 ether);
    }

    function depositCollateralAndMintmdd(
        uint256 amountCollateral,
        uint256 amountToBeMinted,
        uint256 seed
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(seed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        if (amountCollateral <= 1) return;
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(mdde), amountCollateral);
        if (users.length == 0) return;
        address sender = users[seed % users.length];
        (uint256 totalMordredminted, uint256 collateralValueInUsd) = mdde
            .getAccountInfo(msg.sender);
        int256 maxToMint = int256(
            collateralValueInUsd / 2 - totalMordredminted
        );
        if (maxToMint < 0) return;

        amountToBeMinted = bound(amountToBeMinted, 0, uint256(maxToMint));
        if (amountToBeMinted == 0) return;

        vm.prank(sender);
        pool.deposit(amountCollateral, amountToBeMinted, address(collateral));
    }

    function redeemCollateralAndBurnmdd(
        uint256 amountToRedeem,
        uint256 amountMordred,
        uint256 seed
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(seed);
        uint256 maxCollateralToRedeem = pool.getUserBalanceSingularToken(
            msg.sender,
            address(collateral)
        );
        amountToRedeem = bound(amountToRedeem, 0, maxCollateralToRedeem);

        amountMordred = bound(amountMordred, 0, mdd.balanceOf(msg.sender));
        if (amountMordred == 0) {
            return;
        }

        if (users.length == 0) return;
        address sender = users[seed % users.length];

        vm.prank(sender);

        pool.withdraw(address(collateral), amountToRedeem, amountMordred);
    }

    function depositCollateral(
        uint256 collateralSeet,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeet);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);
        if (amountCollateral <= 1) return;
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(mdde), amountCollateral);
        pool.deposit(
            amountCollateral,
            amountCollateral / 2,
            address(collateral)
        );
        vm.stopPrank();
    }

    function redeemCollateral(
        uint256 collateralSeet,
        uint256 amountToRedeem
    ) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeet);
        uint256 maxCollateralToRedeem = pool.getUserBalanceSingularToken(
            msg.sender,
            address(collateral)
        );
        amountToRedeem = bound(amountToRedeem, 0, maxCollateralToRedeem);
        if (amountToRedeem == 0) return;
        vm.startPrank(msg.sender);
        pool.withdraw(address(collateral), amountToRedeem, amountToRedeem / 2);
        vm.stopPrank();
    }

    function mintMordred(uint256 amountToBeMinted, uint256 addressSeed) public {
        if (users.length == 0) return;
        address sender = users[addressSeed % users.length];
        (uint256 totalMordredminted, uint256 collateralValueInUsd) = mdde
            .getAccountInfo(msg.sender);
        int256 maxToMint = int256(
            collateralValueInUsd / 2 - totalMordredminted
        );
        if (maxToMint < 0) return;

        amountToBeMinted = bound(amountToBeMinted, 0, uint256(maxToMint));
        if (amountToBeMinted == 0) return;

        vm.startPrank(sender);
        pool.mintMordred(amountToBeMinted);
        vm.stopPrank();
    }

    function burnMordred(uint256 amountMordred) public {
        amountMordred = bound(amountMordred, 0, mdd.balanceOf(msg.sender));
        if (amountMordred == 0) {
            return;
        }
        pool.burnMordred(amountMordred);
    }

    function borrowFlashLoan(uint256 amount, uint256 seed) public {
        ERC20Mock token = _getCollateralFromSeed(seed);

        if (amount == 0) return;
        if (amount > pool.getPoolBalanceSingularToken(address(token))) return;
        uint256 fee = pool.getFee();
        uint256 precision = pool.getPrecision();
        if (
            (amount * fee - precision) / precision >=
            token.balanceOf(address(this))
        ) return;
        if (users.length == 0) return;
        address sender = users[seed % users.length];

        vm.prank(sender);
        flashLoan.executeFlashLoan(amount, address(token));
        //     token.approve(address(pool), (amount * fee) / precision);
        //     pool.borrowFlashLoan(amount, address(token));

        //     token.transferFrom(
        //         msg.sender,
        //         address(mdde),
        //         (amount * fee) / precision
        //     );
    }

    function claimReward(uint256 amount, uint256 seed) public {
        address token = address(_getCollateralFromSeed(seed));
        if (users.length == 0) return;
        address sender = users[seed % users.length];

        vm.prank(sender);
        amount = pool.getUserRewards(token);

        if (amount == 0) return;

        pool.claimReward(token);
    }

    // ///////////////////////
    // // internal function //
    // ///////////////////////
    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) return link;
        return wbtc;
    }
}
