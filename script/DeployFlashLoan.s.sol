// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {CorollaryFunctions} from "script/CorollaryFunctions.s.sol";
import {Mordred} from "src/MordredToken.sol";
import {MorganteGovernor} from "src/MorganteGovernor.sol";
import {TimeLock} from "src/TimeLock.sol";
import {MordredEngine} from "src/MordredEngine.sol";
import {FlashLoan} from "src/Pool.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";

contract DeployFlashLoan is Script {
    address[] public tokenAddresses;
    address[] public tokenPriceFeed;
    uint256 public fee = 1001000000000000000; // 0.1%
    uint256 minDelay = 259200; // 3 days
    address[] propser;
    address[] executors;

    CorollaryFunctions corollary;
    MorganteGovernor governor;
    Mordred qb;
    FlashLoan pool;
    TimeLock timeLock;

    function run()
        public
        returns (
            FlashLoan,
            CorollaryFunctions,
            address,
            address,
            address,
            address,
            uint256,
            TimeLock,
            MorganteGovernor
        )
    {
        corollary = new CorollaryFunctions();
        (
            address link,
            address wbtc,
            address linkUsdPriceFeed,
            address wbtcUsdPriceFeed,
            uint256 deployerKey
        ) = corollary.activeNetworkConfig();
        tokenAddresses = [link, wbtc];
        tokenPriceFeed = [linkUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        pool = new FlashLoan(tokenAddresses, tokenPriceFeed, fee);
        timeLock = new TimeLock(minDelay, propser, executors);
        governor = new MorganteGovernor(qb, timeLock);

        vm.stopBroadcast();
        ERC20Mock(link).mint(
            0x3746cFd972D3292Ed2567f8fD302E1e26b143535,
            1000 ether
        );
        ERC20Mock(wbtc).mint(
            0x3746cFd972D3292Ed2567f8fD302E1e26b143535,
            1000 ether
        );

        return (
            pool,
            corollary,
            link,
            wbtc,
            linkUsdPriceFeed,
            wbtcUsdPriceFeed,
            deployerKey,
            timeLock,
            governor
        );
    }
}
