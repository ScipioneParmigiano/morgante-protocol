// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

contract FlashLoanUnitTestsOne is Test {
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
    address flashLoanDeployer = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 initial_balance = 1000 ether;
    uint256 constant ACCURACY = 1e12;
    address public linkUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public link;
    address public wbtc;
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

        if (block.chainid == 31337) {
            vm.deal(user, initial_balance);
        }
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

        mddAmount = bound(mddAmount, 1, type(uint96).max);
        collateralAmount = bound(collateralAmount, 1, type(uint96).max);

        if ((collateralAmount * _getTokenPrice(seed)) / mddAmount <= 1) return;
        if (collateralAmount > initial_balance) return;
        if (collateralAmount <= 0) return;
        if (mddAmount <= 0) return;

        console.log(collateralAmount);
        console.log(_getTokenPrice(seed));
        console.log(mddAmount);

        vm.startPrank(user);
        ERC20Mock(token).approve(address(mdde), collateralAmount);
        pool.deposit(collateralAmount, mddAmount, token);
        vm.stopPrank();
        _;
    }

    //# flash loan tests ============================================================================
    //## deposit tests ==============================================================================
    function testOnlyOwnerCanDeposit() external {
        vm.expectRevert();
        mdde.depositCollateralAndMintMordred(link, 100, 1, user);
    }

    function testFuzz_depositIsWorking(
        uint256 collateralAmount,
        uint256 mddAmount,
        uint256 seed
    ) external {
        address token = _getTokenFromSeed(seed);

        mddAmount = bound(mddAmount, 1, type(uint96).max);
        collateralAmount = bound(collateralAmount, 1, type(uint96).max);

        if ((collateralAmount * _getTokenPrice(seed)) / mddAmount <= 1) return;
        if (collateralAmount > initial_balance) return;
        if (collateralAmount <= 0) return;
        if (mddAmount <= 0) return;

        console.log(collateralAmount);
        console.log(_getTokenPrice(seed));
        console.log(mddAmount);

        vm.startPrank(user);
        ERC20Mock(token).approve(address(mdde), collateralAmount);
        pool.deposit(collateralAmount, mddAmount, token);
        assertEq(
            pool.getUserBalanceSingularToken(user, token),
            collateralAmount
        );
        assertEq(
            pool.getUserBalanceSingularToken(user, token),
            collateralAmount
        );
        vm.stopPrank();
    }

    function testFuzz_cantDepositZero(uint256 seed) external {
        address token = _getTokenFromSeed(seed);

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__MustBeMoreThanZero.selector
            )
        );
        vm.startPrank(user);
        pool.deposit(0, 1, token);
        vm.stopPrank();
    }

    function testFuzz_cantMintZero(uint256 seed) external {
        address token = _getTokenFromSeed(seed);

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__MustBeMoreThanZero.selector
            )
        );
        vm.startPrank(user);
        pool.deposit(1, 0, token);
        vm.stopPrank();
    }

    function testFuzz_cantDepositNonAllowedToken(address token) external {
        if (token == link) return;
        if (token == wbtc) return;

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__TokenNotAllowed.selector,
                token
            )
        );
        vm.startPrank(user);
        pool.deposit(1, 1, token);
        vm.stopPrank();
    }

    //## withdraw tests =============================================================================
    function testFuzz_OnlyOwnerCanWithdraw(
        uint256 collateralAmount,
        uint256 mddAmount,
        uint256 seed
    ) external deposited(collateralAmount, mddAmount, seed) {
        address token = _getTokenFromSeed(seed);

        vm.expectRevert();
        mdde.redeemCollateralForMordred(
            token,
            collateralAmount / 2,
            mddAmount / 2,
            user
        );
    }

    function testFuzz_onlyAllowedTokensWithdraw(
        uint256 amount,
        address token
    ) external {
        if (link == token) return;
        if (wbtc == token) return;
        if (amount > initial_balance) return;
        if (amount <= 2) return;

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__TokenNotAllowed.selector,
                token
            )
        );
        pool.withdraw(token, amount, 1);
    }

    function testFuzz_cantRedeemZeroCollateral(
        uint256 collateralAmount,
        uint256 mddAmount,
        uint256 seed
    ) external deposited(collateralAmount, mddAmount, seed) {
        address token = _getTokenFromSeed(seed);
        if (collateralAmount > initial_balance) return;
        if (collateralAmount <= 2) return;

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__MustBeMoreThanZero.selector
            )
        );
        vm.startPrank(user);
        pool.withdraw(token, collateralAmount, 0);
        vm.stopPrank();
    }

    function testFuzz_cantRedeemMoreThanDeposited(
        uint256 collateralAmount,
        uint256 mddAmount,
        uint256 seed
    ) external deposited(collateralAmount, mddAmount, seed) {
        address token = _getTokenFromSeed(seed);
        if (collateralAmount > initial_balance) return;
        if (collateralAmount <= 2) return;
        if (mddAmount == 0) return;

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__CantWithdrawMoreThanDeposited.selector,
                collateralAmount + 1,
                collateralAmount
            )
        );
        vm.startPrank(user);
        pool.withdraw(token, collateralAmount + 1, mddAmount);
        vm.stopPrank();
    }

    function testFuzz_cantBurnZeromdd(
        uint256 collateralAmount,
        uint256 mddAmount,
        uint256 seed
    ) external deposited(collateralAmount, mddAmount, seed) {
        address token = _getTokenFromSeed(seed);
        if (collateralAmount > initial_balance) return;
        if (collateralAmount <= 2) return;

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__MustBeMoreThanZero.selector
            )
        );
        vm.startPrank(user);
        pool.withdraw(token, 0, mddAmount);
        vm.stopPrank();
    }

    function testFuzz_withdrawIsWorking(
        uint256 collateralAmountDeposited,
        uint256 collateralAmountWithdrawn,
        uint256 mddAmountMinted,
        uint256 mddAmountBurned,
        uint256 seed
    ) external deposited(collateralAmountDeposited, mddAmountMinted, seed) {
        address token = _getTokenFromSeed(seed);

        mddAmountMinted = bound(mddAmountMinted, 1, type(uint96).max);
        mddAmountBurned = bound(mddAmountBurned, 1, type(uint96).max);
        collateralAmountDeposited = bound(
            collateralAmountDeposited,
            1,
            type(uint96).max
        );
        collateralAmountWithdrawn = bound(
            collateralAmountWithdrawn,
            1,
            type(uint96).max
        );

        if (
            (collateralAmountDeposited * _getTokenPrice(seed)) /
                mddAmountMinted <=
            1
        ) return;

        if (collateralAmountDeposited > initial_balance) return;
        if (collateralAmountDeposited <= 0) return;
        if (mddAmountMinted <= 0) return;
        if (mddAmountBurned <= 0) return;
        if (collateralAmountWithdrawn >= collateralAmountDeposited) return;
        if (mddAmountMinted <= mddAmountBurned) return;

        console.log(IERC20(token).balanceOf(address(mdde)));
        vm.startPrank(user);

        mdd.approve(address(mdde), mddAmountBurned);
        pool.withdraw(token, collateralAmountWithdrawn, mddAmountBurned);
        assertEq(
            pool.getPoolBalanceSingularToken(token),
            collateralAmountDeposited - collateralAmountWithdrawn
        );
        assertEq(
            pool.getUserBalanceSingularToken(user, token),
            collateralAmountDeposited - collateralAmountWithdrawn
        );
        vm.stopPrank();
    }

    //## borrowFlashLoan tests ======================================================================
    function testFuzz_cantBorrowZero(
        uint256 collateralAmount,
        uint256 mddAmount,
        uint256 seed
    ) external deposited(collateralAmount, mddAmount, seed) {
        address token = _getTokenFromSeed(seed);
        mddAmount = bound(mddAmount, 1, type(uint96).max);
        collateralAmount = bound(collateralAmount, 1, type(uint96).max);

        if ((collateralAmount * _getTokenPrice(seed)) / mddAmount <= 1) return;
        if (collateralAmount > initial_balance) return;
        if (collateralAmount <= 0) return;
        if (mddAmount <= 0) return;

        vm.startPrank(user);
        IERC20(token).approve(address(pool), 100 * pool.getFee());

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__MustBeMoreThanZero.selector
            )
        );
        pool.borrowFlashLoan(0, token);
        vm.stopPrank();
    }

    function testFuzz_onlyAllowedTokensCanBeBorrowedByFlashLoan(
        uint256 amount,
        address token
    ) external {
        if (link == token) return;
        if (wbtc == token) return;
        if (amount > initial_balance) return;
        if (amount <= 2) return;

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__TokenNotAllowed.selector,
                token
            )
        );
        pool.borrowFlashLoan(amount, token);
    }

    function testFuzz_cantLendMoreThanBalanceOfThePool(
        uint256 amountToBorrow,
        uint256 collateralAmount,
        uint256 mddAmount,
        uint256 seed
    ) external deposited(collateralAmount, mddAmount, seed) {
        address token = _getTokenFromSeed(seed);
        mddAmount = bound(mddAmount, 1, type(uint96).max);
        collateralAmount = bound(collateralAmount, 1, type(uint96).max);
        amountToBorrow = bound(amountToBorrow, 1, type(uint96).max);

        if (amountToBorrow <= 0) return;
        if (
            (amountToBorrow * (pool.getFee())) / pool.getPrecision() >=
            initial_balance
        ) return;
        if ((collateralAmount * _getTokenPrice(seed)) / mddAmount <= 1) return;
        if (collateralAmount > initial_balance) return;
        if (collateralAmount <= 0) return;
        if (mddAmount <= 0) return;
        if (amountToBorrow <= pool.getPoolBalanceSingularToken(token)) return;

        vm.startPrank(user);
        IERC20(token).approve(address(pool), amountToBorrow * pool.getFee());

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashLoan.FlashLoan__InsufficientFunds.selector
            )
        );
        pool.borrowFlashLoan(amountToBorrow, token);
        vm.stopPrank();
    }

    // function testFuzz_FlashLoanIsWorking(
    //     uint256 amountToBorrow,
    //     uint256 collateralAmount,
    //     uint256 mddAmount,
    //     uint256 seed
    // ) external deposited(collateralAmount, mddAmount, seed) {
    //     address token = _getTokenFromSeed(seed);
    //     mddAmount = bound(mddAmount, 1, type(uint96).max);
    //     collateralAmount = bound(collateralAmount, 1, type(uint96).max);
    //     amountToBorrow = bound(amountToBorrow, 1, type(uint96).max);

    //     console.log("--------------");
    //     console.log(IERC20(token).balanceOf(address(mdde)));
    //     if (amountToBorrow == 0) return;
    //     if (amountToBorrow > pool.getPoolBalanceSingularToken(token)) return;
    //     if (
    //         (amountToBorrow * (pool.getFee())) /
    //             pool.getPrecision() +
    //             collateralAmount >=
    //         initial_balance
    //     ) return;
    //     if ((collateralAmount * _getTokenPrice(seed)) / mddAmount <= 1) return;
    //     if (collateralAmount > initial_balance) return;
    //     if (collateralAmount <= 0) return;
    //     if (mddAmount <= 0) return;
    //     if (amountToBorrow > pool.getPoolBalanceSingularToken(token)) return;
    //     console.log("--------------");
    //     console.log(IERC20(token).balanceOf(address(mdde)));

    //     console.log(amountToBorrow);
    //     vm.startPrank(user);
    //     IERC20(token).approve(
    //         address(pool),
    //         (amountToBorrow * pool.getFee()) / pool.getPrecision()
    //     );
    //     pool.borrowFlashLoan(amountToBorrow, token);

    //     assertEq(collateralAmount, pool.getPoolBalanceSingularToken(token));
    //     vm.stopPrank();
    // }

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
