// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWHYPE{
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
        function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
