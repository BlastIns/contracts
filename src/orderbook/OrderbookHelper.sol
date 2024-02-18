// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./orderlist.sol";

contract OrderbookHelper {

    struct OrderDetailInfo {
        uint256 orderId;
        address askAddress;
        uint256 amount;
        uint256 spotPrice;
        OrderList.OrderStatus status;
        uint256 askTime;        
        address[] takerAddresses;
        uint256[] dealedAmounts;
        uint256[] dealedTakeTimes;
    }

    function getListingOrders(address orderListAddr, uint256 _fromIndex, uint256 _toIndex) view public returns(OrderList.OrderInfo[] memory orderInfos) {
        OrderList orderList = OrderList(orderListAddr); 
        uint256 length = orderList.getTotalOrderNumber();
        if (_toIndex > length) _toIndex = length;
        require(_fromIndex < _toIndex, "OrderbookHelper: index is out of bound.");
        
        orderInfos = new OrderList.OrderInfo[](_toIndex - _fromIndex);
        uint256 index = 0;
        (bool exist, uint256 currentId) = orderList.getNodeInfo(0);
        while(index < _toIndex && exist) {
            if (index < _fromIndex) {
                (exist, currentId) = orderList.getNodeInfo(currentId);
                index++;
                continue;
            }
            (
                uint256 orderId,
                address askAddress,
                uint256 amount,
                uint256 spotPrice,
                OrderList.OrderStatus status,
                uint256 askTime
            ) = orderList.totalOrders(currentId);

            orderInfos[index - _fromIndex] = OrderList.OrderInfo(
                orderId,
                askAddress,
                amount,
                spotPrice,
                status,
                askTime,
                new address[](0),
                new uint256[](0),
                new uint256[](0)
            );
            
            (exist, currentId) = orderList.getNodeInfo(currentId);
            index++;
        }
    }

    function getUserOrders(address orderListAddr, address user) external view returns(OrderDetailInfo[] memory orderDetailInfos) {
        OrderList orderList = OrderList(orderListAddr); 
        uint256 userOrderLength = orderList.getUserOrderNumber(user);
        orderDetailInfos = new OrderDetailInfo[](userOrderLength);
        for (uint256 i = userOrderLength - 1; i >= 0; i--) {
            uint256 currentId = orderList.userOrdersMap(user, i);
            (
                uint256 orderId,
                address askAddress,
                uint256 amount,
                uint256 spotPrice,
                OrderList.OrderStatus status,
                uint256 askTime
            ) = orderList.totalOrders(currentId);

            uint256 dealedOrdersLength = orderList.getDealedOrderLength(currentId);
            orderDetailInfos[userOrderLength - 1 - i] = OrderDetailInfo(
                orderId,
                askAddress,
                amount,
                spotPrice,
                status,
                askTime,
                new address[](dealedOrdersLength),
                new uint256[](dealedOrdersLength),
                new uint256[](dealedOrdersLength)
            );

            for (uint256 j = 0; j < dealedOrdersLength; j++) {
                (orderDetailInfos[userOrderLength - 1 - i].takerAddresses[j],
                orderDetailInfos[userOrderLength - 1 - i].dealedAmounts[j],
                orderDetailInfos[userOrderLength - 1 - i].dealedTakeTimes[j]) = orderList.getDealedOrderInfo(currentId, j);
            }

            if (i == 0) break;
        }
    }
}
