// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract MockUSDL is ERC20 {
    uint256 constant MULTIPLIER = 1e18;
    uint256 public rebaseMultiplier = MULTIPLIER;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_, decimals_) {}

    function getActiveMultiplier() external view returns (uint256) {
        return rebaseMultiplier;
    }

    function setRebaseMultiplier(uint256 newMultiplier) external {
        rebaseMultiplier = newMultiplier;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}