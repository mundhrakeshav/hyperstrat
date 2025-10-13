// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "solady/tokens/ERC20.sol";

contract MockERC20 is ERC20 {
    string private _name;
    string private _symbol;

    constructor(
        string memory name,
        string memory symbol
    ) {
        _name = name;
        _symbol = symbol;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }
}