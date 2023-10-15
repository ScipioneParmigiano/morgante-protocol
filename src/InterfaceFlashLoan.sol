// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFlashLoan {
    function useBorrowedFunds(address token, uint256 amount) external;
}
