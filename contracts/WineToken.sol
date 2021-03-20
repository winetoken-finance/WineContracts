// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/GSN/Context.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Capped.sol";
import "./UniBurnOnTransfer.sol";

contract WineToken is
    Context,
    AccessControl,
    ERC20Burnable,
    ERC20Capped,
    UniBurnOnTransfer
{
    using SafeMath for uint256;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    string constant TOKEN_NAME = "Cabernet Franc Wine Token";
    string constant TOKEN_SYMBOL = "CWINE";
    uint256 PRE_MINE_SUPPLY = 1; // 1
    uint256 capped = 3000000000000000000000; // 3000

    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) ERC20Capped(capped) UniBurnOnTransfer(uint256(1), uint256(2), uint256(4).mul(10**18)){
        // setting initial roles
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());

        // miniting pre-mine
        _mint(_msgSender(), PRE_MINE_SUPPLY.mul(10**18));
    }

    function mint(address to, uint256 amount) external virtual {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "WineToken: must have minter role to mint"
        );
        _mint(to, amount);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override(ERC20, UniBurnOnTransfer) {
        super._transfer(sender, recipient, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20, ERC20Capped, UniBurnOnTransfer) {
        super._beforeTokenTransfer(from, to, amount);
    }
}
