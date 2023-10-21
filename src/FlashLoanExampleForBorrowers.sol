// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FlashLoan} from "./Pool.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";

/*
 * Contract that shows how to use the Morgante protocol for flash loans.
*/

contract FlashLoanExampleForBorrowers {
    FlashLoan pool;

    constructor(address _poolAddress) {
        pool = FlashLoan(_poolAddress);
    }

    function useBorrowedAmount(address token, uint256 amount) external {
        // use here your funds for arbitrage or whatever

        // transfer back to mdde
        uint256 fee = pool.getFee();
        uint256 precision = pool.getPrecision();

        bool success = IERC20(token).transfer(
            pool.returnMordredEngineAddress(),
            (amount * fee) / precision
        );

        if (!success) revert("errore");
    }

    // function to connect the dots
    function executeFlashLoan(uint256 amount, address token) external {
        pool.borrowFlashLoan(amount, token);
    }
}
