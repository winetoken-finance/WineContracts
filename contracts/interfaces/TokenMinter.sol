// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

interface TokenMinter {
    function mint(address to, uint256 amount) external;

    function burn(uint256 amount) external;
}
