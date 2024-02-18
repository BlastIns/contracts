// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface  IYieldPool {
    function depositYield() payable external;
    function depositSelfYield() external;
}