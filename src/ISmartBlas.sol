// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import "./IYieldPool.sol";

interface ISmartBlas {
    function initialize(address yieldPool, string memory name, uint256 fee, uint256 limit, uint256 maxMint, address owner) external;
    function claimAllYield2Pool() external;
}