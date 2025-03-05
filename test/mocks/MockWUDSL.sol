// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {MockUSDL} from "./MockUSDL.sol";

contract MockWUSDL is ERC20 {
    address public immutable asset;
    uint256 public exchangeRate = 1e18; // 1:1 initial exchange rate

    constructor(address _asset) ERC20("Wrapped USDL", "wUSDL", 18) {
        asset = _asset;
    }

    function setExchangeRate(uint256 _rate) external {
        exchangeRate = _rate;
    }

    function totalAssets() public view returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        return (assets * 1e18) / exchangeRate;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return (shares * exchangeRate) / 1e18;
    }

    function previewDeposit(uint256 assets) public view returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return (assets * 1e18) / exchangeRate;
    }

    function previewRedeem(uint256 shares) public view returns (uint256) {
        return convertToAssets(shares);
    }

    function deposit(uint256 assets, address receiver) public returns (uint256 shares) {
        shares = previewDeposit(assets);
        ERC20(asset).transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        return shares;
    }

    function mint(uint256 shares, address receiver) public returns (uint256 assets) {
        assets = previewMint(shares);
        ERC20(asset).transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256 shares) {
        shares = previewWithdraw(assets);
        if (owner != msg.sender) {
            uint256 allowed = allowance[owner][msg.sender];
            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - shares;
            }
        }
        _burn(owner, shares);
        ERC20(asset).transfer(receiver, assets);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) public returns (uint256 assets) {
        assets = previewRedeem(shares);
        if (owner != msg.sender) {
            uint256 allowed = allowance[owner][msg.sender];
            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - shares;
            }
        }
        _burn(owner, shares);
        ERC20(asset).transfer(receiver, assets);
        return assets;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}