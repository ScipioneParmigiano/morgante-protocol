// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {DeployFlashLoan} from "script/DeployFlashLoan.s.sol";
import {MordredEngine} from "src/MordredEngine.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {CorollaryFunctions} from "script/CorollaryFunctions.s.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Mordred} from "src/MordredToken.sol";
import {MorganteGovernor} from "src/MorganteGovernor.sol";
import {TimeLock} from "src/TimeLock.sol";
import {FlashLoan} from "src/Pool.sol";
import {MockV3Aggregator} from "script/mocks/MockV3Aggregator.s.sol";

contract FlashLoanUnitTestsTwo is Test {
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
        address token,
        uint256 indexed amount
    );
    event newFlashLoan(
        address indexed sender,
        address indexed token,
        uint256 indexed amount
    );
    event receivedPremium(
        address indexed sender,
        address indexed token,
        uint256 indexed amount
    );
    event updatedFlashLoansFee(uint256 newFee);

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
    DeployFlashLoan deployer = new DeployFlashLoan();
    CorollaryFunctions corollary = new CorollaryFunctions();
    MorganteGovernor governor;
    TimeLock timeLock;
    FlashLoan pool;
    Mordred mdd;
    MordredEngine mdde;
    MockV3Aggregator mockV3Aggregator = new MockV3Aggregator(18, 1);

    address user = makeAddr("BOB");
    uint256 initial_balance = 1000 ether;
    uint256 constant ACCURACY = 1e12;
    address public linkUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public link;
    address public wbtc;
    address[] tokenAddresses;
    address[] tokenPriceFeeds;
    uint256 public deployerKey;
    uint256 constant PRECISION = 1e4;
    uint256 minDelay = 3600; // 1h
    uint256 quorum = 20;
    uint256 period = 86400; //1w
    uint256 votingDelay = 10; // 10 blocks
    address[] propsers;
    address[] executors;
    address[] addressesToCall;
    uint256[] feeValues;
    bytes[] functionCalls;

    ////////////
    // set up //
    ////////////
    function setUp() external {
        (
            pool,
            ,
            link,
            wbtc,
            linkUsdPriceFeed,
            btcUsdPriceFeed,
            ,
            timeLock,
            governor
        ) = deployer.run();
        address flashLoanDeployer = pool.owner();
        tokenAddresses = [link, wbtc];
        tokenPriceFeeds = [linkUsdPriceFeed, btcUsdPriceFeed];
        vm.deal(user, initial_balance);

        ERC20Mock(link).mint(user, initial_balance);
        ERC20Mock(wbtc).mint(user, initial_balance);

        mdd = Mordred(pool.returnMordredTokenAddress());
        mdde = MordredEngine(pool.returnMordredEngineAddress());
        timeLock = new TimeLock(minDelay, propsers, executors);
        governor = new MorganteGovernor(mdd, timeLock);
        vm.prank(user);
        mdd.delegate(user);
        bytes32 proposerRole = timeLock.PROPOSER_ROLE();
        bytes32 executorRole = timeLock.EXECUTOR_ROLE();
        bytes32 adminRole = timeLock.TIMELOCK_ADMIN_ROLE();

        timeLock.grantRole(proposerRole, address(governor));
        timeLock.grantRole(executorRole, address(0));
        timeLock.revokeRole(adminRole, msg.sender);

        vm.prank(flashLoanDeployer);
        pool.transferOwnership(address(timeLock));
    }

    ///////////////
    // modifiers //
    ///////////////
    modifier deposited(
        uint256 collateralAmount,
        uint256 mddAmount,
        uint256 seed
    ) {
        address token = _getTokenFromSeed(seed);

        mddAmount = bound(mddAmount, 1, type(uint16).max);
        collateralAmount = bound(collateralAmount, 1, type(uint16).max);

        if ((collateralAmount * _getTokenPrice(seed)) / mddAmount <= 1) return;
        if (collateralAmount > initial_balance) return;
        if (collateralAmount == 0) return;
        if (mddAmount == 0) return;

        console.log(collateralAmount);
        console.log(_getTokenPrice(seed));
        console.log(mddAmount);

        vm.startPrank(user);
        ERC20Mock(token).approve(address(mdde), collateralAmount);
        pool.deposit(collateralAmount, mddAmount, token);
        vm.stopPrank();
        _;
    }

    //## redeemCollateral tests =====================================================================
    function testFuzz_cantRedeemZero(
        uint256 amountDeposited,
        uint256 mddAmount,
        uint256 seed
    ) external deposited(amountDeposited, mddAmount, seed) {
        address token = _getTokenFromSeed(seed);
        vm.prank(user);

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__MustBeMoreThanZero.selector
            )
        );
        pool.redeemCollateral(token, 0);
    }

    function testFuzz_cantWithdrawMoreThanDeposited(
        uint256 amountDeposited,
        uint256 amountToWithdraw,
        uint256 seed
    ) external deposited(amountDeposited, 1, seed) {
        address token = _getTokenFromSeed(seed);
        amountDeposited = bound(amountDeposited, 1, type(uint16).max);

        if (amountToWithdraw <= amountDeposited) return;
        if (amountDeposited < 1) return;
        if (amountDeposited > initial_balance) return;
        vm.prank(user);

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__CantWithdrawMoreThanDeposited.selector,
                amountToWithdraw,
                amountDeposited
            )
        );
        pool.redeemCollateral(token, amountToWithdraw);
    }

    function testFuzz_cantRedeemNonAllowedToken(
        uint256 amountDeposited,
        uint256 amountToWithdraw,
        address token
    ) external {
        if (token == link) return;
        if (token == wbtc) return;
        if (amountToWithdraw > amountDeposited) return;
        if (amountDeposited < 1) return;
        if (amountToWithdraw < 1) return;
        vm.prank(user);

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__TokenNotAllowed.selector,
                token
            )
        );
        pool.redeemCollateral(token, amountToWithdraw);
    }

    function testFuzz_redeemCollateralIsWorking(
        uint256 amountDeposited,
        uint256 amountToWithdraw,
        uint256 seed
    ) external deposited(amountDeposited, 2, seed) {
        address token = _getTokenFromSeed(seed);
        amountToWithdraw = bound(amountToWithdraw, 1, type(uint16).max);
        amountDeposited = bound(amountDeposited, 1, type(uint16).max);
        if (amountToWithdraw >= amountDeposited) return;
        if (amountDeposited < 1) return;
        if (amountToWithdraw < 1) return;

        vm.prank(user);
        pool.redeemCollateral(token, amountToWithdraw);

        assertEq(
            pool.getUserBalanceSingularToken(user, token),
            amountDeposited - amountToWithdraw
        );
    }

    //## depositCollateral tests ====================================================================
    function testFuzz_cantDepositZeroTokens(uint256 seed) external {
        address token = _getTokenFromSeed(seed);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__MustBeMoreThanZero.selector
            )
        );
        pool.depositCollateral(token, 0);
    }

    function testFuzz_cantDepositNonAllowedToken(
        uint256 amount,
        address token
    ) external {
        if (token == link) return;
        if (token == wbtc) return;
        if (amount == 0) return;
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__TokenNotAllowed.selector,
                token
            )
        );
        pool.depositCollateral(token, amount);
    }

    function testFuzz_depositCollateralIsWorking(
        uint256 amount,
        uint256 seed
    ) external {
        console.log(amount);
        amount = bound(amount, 1, type(uint16).max);
        if (amount <= 0) return;
        if (amount > initial_balance) return;
        address token = _getTokenFromSeed(seed);

        vm.startPrank(user);
        IERC20(token).approve(address(mdde), amount);
        pool.depositCollateral(token, amount);

        assertEq(pool.getUserBalanceSingularToken(user, token), amount);
    }

    //## mintMordred tests ======================================================================
    function testFuzz_cantMintZero(
        uint256 amountDeposited,
        uint256 seed
    ) external deposited(amountDeposited, 1, seed) {
        vm.startPrank(user);

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__MustBeMoreThanZero.selector
            )
        );
        pool.mintMordred(0);
        vm.stopPrank();
    }

    function testFuzz_mintmddisWorking(
        uint256 amountDeposited,
        uint256 amountmdd,
        uint256 seed
    ) external deposited(amountDeposited, 1, seed) {
        uint256 tokenPrice = _getTokenPrice(seed);

        amountmdd = bound(amountmdd, 1, type(uint16).max);
        amountDeposited = bound(amountDeposited, 1, type(uint16).max);
        if (amountmdd <= 1) return;
        if (amountDeposited * tokenPrice <= amountmdd + 1) return;
        vm.startPrank(user);
        pool.mintMordred(amountmdd / 2);
        vm.stopPrank();
    }

    //## burnMordred tests ======================================================================
    function testFuzz_cantBurnZero(
        uint256 amountDeposited,
        uint256 amountmdd,
        uint256 seed
    ) external deposited(amountDeposited, amountmdd, seed) {
        vm.startPrank(user);

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__MustBeMoreThanZero.selector
            )
        );
        pool.burnMordred(0);
        vm.stopPrank();
    }

    function testFuzz_burnmddisWorking(
        uint256 amountDeposited,
        uint256 amountmdd,
        uint256 amountmddtoBurn,
        uint256 seed
    ) external deposited(amountDeposited, amountmdd, seed) {
        uint256 tokenPrice = _getTokenPrice(seed);
        amountmdd = bound(amountmdd, 1, type(uint16).max);
        amountmddtoBurn = bound(amountmddtoBurn, 1, type(uint16).max);
        amountDeposited = bound(amountDeposited, 1, type(uint16).max);

        if (amountmddtoBurn >= amountmdd) return;
        if (amountDeposited * tokenPrice <= 2 * amountmdd + 1) return;
        vm.startPrank(user);
        IERC20(mdd).approve(address(mdde), amountmddtoBurn);
        pool.burnMordred(amountmddtoBurn);
        vm.stopPrank();

        assertEq(IERC20(mdd).balanceOf(user), amountmdd - amountmddtoBurn);
    }

    //## liquidate tests ============================================================================
    function testFuzz_cantLiquidateZero(uint256 seed) external {
        address token = _getTokenFromSeed(seed);
        vm.prank(user);

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__MustBeMoreThanZero.selector
            )
        );
        pool.liquidate(token, user, 0);
    }

    function testFuzz_cantLiquidateNonAllowedToken(
        uint256 amount,
        address token
    ) external {
        vm.prank(user);
        if (amount == 0) return;
        if (token == link) return;
        if (token == wbtc) return;

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__TokenNotAllowed.selector,
                token
            )
        );
        pool.liquidate(token, user, amount);
    }

    //## getUserBalanceSingularToken tests ==========================================================
    function testFuzz_getUserBalanceSingularToken(
        uint256 amount,
        uint256 amountmdd,
        uint256 seed
    ) external deposited(amount, amountmdd, seed) {
        amountmdd = bound(amountmdd, 1, type(uint16).max);
        amount = bound(amount, 1, type(uint16).max);

        if (amount == 0) return;
        if (amountmdd == 0) return;
        if (amount > amountmdd) return;
        address token = _getTokenFromSeed(seed);
        uint256 balance = pool.getUserBalanceSingularToken(user, token);

        assertEq(balance, amount);
    }

    //## getPoolBalanceSingularToken tests ==========================================================
    function testFuzz_getPoolBalanceSingularToken(
        uint256 amount,
        uint256 seed
    ) external deposited(amount, 1, seed) {
        amount = bound(amount, 1, type(uint16).max);

        if (amount > initial_balance) return;
        if (amount == 0) return;
        address token = _getTokenFromSeed(seed);
        uint256 balance = pool.getPoolBalanceSingularToken(token);

        assertEq(balance, amount);
    }

    //## getCollectedTokenFeesPerToken tests ========================================================
    // function testFuzz_getCollectedTokenFeesPerToken(
    //     uint256 amount,
    //     uint256 seed
    // ) external deposited(amount, 1, seed) {
    //     address token = _getTokenFromSeed(seed);
    //     amount = bound(amount, 1, type(uint16).max);
    //     if (amount <= 1) return;
    //     if (
    //         (amount * (pool.getFee())) / pool.getPrecision() >=
    //         initial_balance / 2
    //     ) return;

    //     vm.startPrank(user);
    //     IERC20(token).approve(
    //         address(pool),
    //         (amount * (pool.getPrecision() + pool.getFee())) /
    //             pool.getPrecision() /
    //             2
    //     );
    //     pool.borrowFlashLoan(amount / 2, token);
    // }

    //## getTokenAddresses tests ====================================================================
    function test_getTokenAddresses() external {
        address[] memory collaterals = pool.getTokenAddresses();

        assertEq(collaterals, tokenAddresses);
    }

    //## getPriceFeedAddresses tests ================================================================
    function test_getPriceFeedAddresses() external {
        address[] memory priceFeeds = pool.getPriceFeedAddresses();

        assertEq(priceFeeds, tokenPriceFeeds);
    }

    //## getFee tests ===============================================================================
    function test_getFee() external {
        uint256 fee = pool.getFee();
        uint256 expectedFee = deployer.fee();
        assertEq(expectedFee, fee);
    }

    //## returnMordredTokenAddress tests ========================================================
    function test_returnMordredTokenAddress() external {
        address addressmdd = pool.returnMordredTokenAddress();

        assertEq(addressmdd, address(mdd));
    }

    //## returnMordredEngineAddress tests =======================================================
    function test_returnMordredEngineAddress() external {
        address addressmddE = pool.returnMordredEngineAddress();

        assertEq(addressmddE, address(mdde));
    }

    //## getPrecision tests =========================================================================
    function test_getPrecision() external {
        uint256 precision = pool.getPrecision();
        uint256 expectedPrecision = 1e18;

        assertEq(precision, expectedPrecision);
    }

    ////////////////////////
    // internal functions //
    ////////////////////////
    function _getTokenFromSeed(uint256 seed) internal view returns (address) {
        if (seed % 2 == 0) return wbtc;
        return link;
    }

    function _getTokenPrice(uint256 seed) internal view returns (uint256) {
        return mdde.tokenPriceToUsd(_getTokenFromSeed(seed), 1);
    }
}
