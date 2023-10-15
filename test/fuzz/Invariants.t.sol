// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";
import {Mordred} from "src/MordredToken.sol";
import {MordredEngine} from "src/MordredEngine.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "script/mocks/MockV3Aggregator.s.sol";
import {DeployFlashLoan} from "script/DeployFlashLoan.s.sol";
import {CorollaryFunctions} from "script/CorollaryFunctions.s.sol";
import {FlashLoan} from "src/Pool.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

// invariant property: the MDD stablecoin should always be overcollateralized

contract InvariantTest is StdInvariant, Test {
    DeployFlashLoan deployer;
    FlashLoan pool;
    MordredEngine mdde;
    Mordred mdd;
    address link;
    address wbtc;
    Handler handler;

    function setUp() public {
        deployer = new DeployFlashLoan();
        (pool, , link, wbtc, , , , , ) = deployer.run();
        mdde = MordredEngine(pool.returnMordredEngineAddress());
        mdd = Mordred(pool.returnMordredTokenAddress());
        handler = new Handler(mdde, mdd, pool);
        targetContract(address(handler));
    }

    function invariant_protocolMustBeOvercorrateralized() public view {
        uint256 totalMordredSupply = mdd.totalSupply();
        uint256 totalDepositedLink = IERC20(link).balanceOf(address(mdde));
        uint256 totalDepositedWBTC = IERC20(wbtc).balanceOf(address(mdde));

        uint256 collateralUsdValue = mdde.tokenPriceToUsd(
            link,
            totalDepositedLink
        ) + mdde.tokenPriceToUsd(wbtc, totalDepositedWBTC);

        assert(collateralUsdValue >= totalMordredSupply);
    }
}
