// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import {ERC20Votes} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

// governance token

contract Mordred is ERC20, ERC20Permit, ERC20Votes, Ownable {
    error Mordred__MustBeMoreThanZero();
    error Mordred__BurnAmountExceedsBalance(uint256 amount);
    error Mordred__NotZeroAddress();

    constructor() ERC20("Mordred", "MDD") ERC20Permit("Mordred") {}

    function mint(
        address to,
        uint256 amount
    ) external onlyOwner returns (bool) {
        if (to == address(0)) revert Mordred__NotZeroAddress();
        if (amount <= 0) revert Mordred__MustBeMoreThanZero();

        _mint(to, amount);
        return true;
    }

    function burn(uint256 amount, address sender) external onlyOwner {
        uint256 balance = balanceOf(sender);
        if (amount <= 0) revert Mordred__MustBeMoreThanZero();
        if (amount > balance) revert Mordred__BurnAmountExceedsBalance(balance);

        _burn(sender, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(
        address account,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._burn(account, amount);
    }
}
