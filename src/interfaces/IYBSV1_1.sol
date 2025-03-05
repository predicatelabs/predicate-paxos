// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IYBSV1_1 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function rebaseSharesOf(address account) external view returns (uint256);
    function fixedSharesOf(address account) external view returns (uint256);
    function isAddrBlocked(address addr) external view returns (bool);
    function isAddrBlockedForReceiving(address addr) external view returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function getActiveMultiplier() external view returns (uint256);
}