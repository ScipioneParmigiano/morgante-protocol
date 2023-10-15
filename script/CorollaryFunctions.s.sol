// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "../lib/forge-std/src/Script.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.s.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {LINK} from "script/mocks/MockLINK.sol";
import {wBTC} from "script/mocks/MockWBTC.sol";

contract CorollaryFunctions is Script {
    struct NetworkConfig {
        address link;
        address wbtc;
        address linkUsdPriceFeed;
        address wbtcUsdPriceFeed;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 20000e8;
    uint256 public constant BALANCE = 1000e8;
    NetworkConfig public activeNetworkConfig;
    uint256 public ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 534351) {
            activeNetworkConfig = getScrollSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getScrollSepoliaConfig()
        public
        view
        returns (NetworkConfig memory)
    {
        return
            NetworkConfig({
                link: 0x279cBF5B7e3651F03CB9b71A9E7A3c924b267801,
                wbtc: 0x5EA79f3190ff37418d42F9B2618688494dBD9693,
                linkUsdPriceFeed: 0xaC3E04999aEfE44D508cB3f9B972b0Ecd07c1efb,
                wbtcUsdPriceFeed: 0x87dce67002e66C17BC0d723Fe20D736b80CAaFda,
                deployerKey: vm.envUint("PRIVATE_KEY")
            });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // Check to see if we already an active network config
        if (activeNetworkConfig.linkUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        LINK linkMock = new LINK();
        wBTC wbtcMock = new wBTC();

        MockV3Aggregator linkUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            BTC_USD_PRICE
        );
        vm.stopBroadcast();

        return
            NetworkConfig({
                link: address(linkMock),
                wbtc: address(wbtcMock),
                linkUsdPriceFeed: address(linkUsdPriceFeed),
                wbtcUsdPriceFeed: address(btcUsdPriceFeed),
                deployerKey: ANVIL_PRIVATE_KEY
            });
    }
}
