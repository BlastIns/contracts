// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IOrderbook {
    function recordDealedInfo(
        bool bSellList,
        uint256 orderId,
        uint256 dealedOrderIndex
    ) external;
}