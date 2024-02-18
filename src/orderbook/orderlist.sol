// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./StructuredLinkedList.sol";
import "../BlastClaimWithYield.sol";
import "./IOrderbook.sol";

contract OrderList is IStructureInterface, BlastClaimWithYield {
    using EnumerableSet for EnumerableSet.UintSet;
    using StructuredLinkedList for StructuredLinkedList.List;

    struct StatInfo {
        uint256 totalVolume;
    }

    enum OrderStatus {
        Listing,
        UnList,
        Dealed
    }

    struct OrderInfo {
        uint256 orderId;
        address askAddress;
        uint256 amount;
        uint256 spotPrice;
        OrderStatus status;
        uint256 askTime;        
        address[] takerAddresses;
        uint256[] dealedAmounts;
        uint256[] dealedTakeTimes;
    }

    uint256 public constant BaseRate = 10000;
    uint256 public feeRate;
    uint256 public platformFee;
    uint256 public globalId;
    address public listedToken;
    address public paidToken;  // ETH = address(0)
    bool public bSellList;
    StatInfo public statInfo;
    IOrderbook public orderbook;

    mapping(uint256 => OrderInfo) public totalOrders;
    mapping(address => uint256[]) public userOrdersMap;
    StructuredLinkedList.List private listedOrders;

    address public constant ETH = address(0x0000000000000000000000000000000000000000);
    address public constant WETH = address(0x4200000000000000000000000000000000000023);
    address public constant USDB = address(0x4200000000000000000000000000000000000022);
    address public feeToken;

    event MakeOrder(address indexed user, uint256 indexed orderId, uint256 amount, uint256 spotPrice);
    event TakeOrder(address indexed from, address indexed to, uint256 indexed orderId, uint256 listedTokenAmount, uint256 paidTokenAmount, uint256 spotPrice);
    
    // _listedToken weth: 0x4200000000000000000000000000000000000023
    // _paidToken blas: 0x10B0Ee2cfcAf6de5042c93DAeD8bE841c50146Fb
    constructor(address _orderbook, address _listedToken, address _paidToken, address _feeToken, uint256 _feeRate, bool _bSellList) BlastClaimWithYield(msg.sender) { 
        require(isBasicQuoteToken(_listedToken) || isBasicQuoteToken(_paidToken), "At least one basic token(WETH/USDB)"); 
        require(_feeToken == _listedToken || _feeToken == _paidToken, "!fee token error");      
        listedToken = _listedToken;
        paidToken = _paidToken;
        feeToken = _feeToken;
        feeRate = _feeRate;
        bSellList = _bSellList;
        orderbook = IOrderbook(_orderbook);
    }

    // get node price by order id
    function getValue(uint256 orderId) view public override returns(uint256) {
        if (orderId == 0) return 0;
        OrderInfo memory orderInfo = totalOrders[orderId];
        return orderInfo.spotPrice;
    }

    function isBasicQuoteToken(address token) pure public returns(bool) {
        return token == WETH || token == USDB;
    }

    function nodeExist(uint256 node) view public returns(bool) {
        return listedOrders.nodeExists(node);
    }
    
    // amount: the amount of listed token
    // spotPrice: the spot price of base token the orderbook
    function makeOrder(uint256 amount, uint256 spotPrice, uint256[] memory nearestNodes) public {
        require(amount > 0, "amount = 0");
        require(spotPrice > 0, "spotPrice = 0");
        globalId++;

        OrderInfo memory orderInfo = OrderInfo({
            orderId: globalId,
            askAddress: msg.sender,
            amount: amount,
            spotPrice: spotPrice,
            status: OrderStatus.Listing,
            askTime: block.timestamp,
            takerAddresses: new address[](0),
            dealedAmounts: new uint256[](0),
            dealedTakeTimes: new uint256[](0)
        });

        totalOrders[globalId] = orderInfo;
        userOrdersMap[msg.sender].push(globalId);

        uint256 nearestNode = 0;
        for (uint256 i = 0; i < nearestNodes.length; i++) {    
            if (nearestNodes[i] == 0) {                
                break;
            }
            if (listedOrders.nodeExists(nearestNodes[i])) {
                nearestNode = nearestNodes[i];
                break;
            }
        }
        
        uint256 next = listedOrders.getSortedSpot(address(this), spotPrice, nearestNode, !bSellList);        
        listedOrders.insertBefore(next, globalId);

        IERC20(listedToken).transferFrom(msg.sender, address(this), amount);

        emit MakeOrder(msg.sender, globalId, amount, spotPrice);
    }

    function getNearestNodesToInsert(uint256 spotPrice) view public returns(uint256[] memory nearestNodes) {
        nearestNodes = new uint256[](3);

        uint256 nextNode = listedOrders.getSortedSpot(address(this), spotPrice, 0, !bSellList); 
        (, nearestNodes[0]) = listedOrders.getPreviousNode(nextNode);

        nearestNodes[1] = nextNode; 

        (, uint256 nextNode1) = listedOrders.getNextNode(nextNode);
        nearestNodes[2] = nextNode1; 
    }

    function getHeaderOrderIndex() view public returns(bool exist, uint256 index) {
        return listedOrders.getAdjacent(0, true);   // get the first node of the list
    }
    
    function getTotalOrderNumber() view public returns(uint256) {
        return listedOrders.sizeOf();
    }
    
    function getNodeInfo(uint256 node) view public returns(bool, uint256) {
        return listedOrders.getNextNode(node);
    }

    function getUserOrderNumber(address user) view public returns(uint256) {
        return userOrdersMap[user].length;
    }

    function getDealedOrderLength(uint256 orderId) view public returns(uint256) {
        return totalOrders[orderId].takerAddresses.length;
    }

    function unlistOrder(uint256 orderId) external {
        OrderInfo storage orderInfo = totalOrders[orderId];
        require(orderInfo.status == OrderStatus.Listing, "Not in list");
        require(msg.sender == orderInfo.askAddress, "!owner");
        orderInfo.status = OrderStatus.UnList;
        listedOrders.remove(orderId);

        IERC20(listedToken).transfer(msg.sender, orderInfo.amount);
    }

    // amount: the amount of listed token, 0 means take all left amount
    function takeOrder(uint256 orderId, uint256 amount) public payable returns(uint256) {                
        OrderInfo storage orderInfo = totalOrders[orderId];
        require(orderInfo.status == OrderStatus.Listing, "Order NOT in listing");
        require(msg.sender != orderInfo.askAddress, "Can NOT take your own order.");
        (bool exist, uint256 headOrderId) = listedOrders.getNextNode(0);
        require(exist && headOrderId == orderId, "NOT the head order");

        uint256 leftAmount = orderInfo.amount;
        if (amount == 0) amount = leftAmount;

        require(leftAmount >= amount, "Not enough amount in this order.");

        // default: sellList
        uint256 paidTokenAmount = calculateAmountIn(orderInfo.spotPrice, amount);
        uint256 cost = feeToken == paidToken ? paidTokenAmount : amount;
        uint256 costCutFee = cost * (BaseRate - feeRate) / BaseRate;
        platformFee += cost - costCutFee; 

        IERC20(paidToken).transferFrom(msg.sender, address(this), paidTokenAmount);       
        IERC20(paidToken).transfer(orderInfo.askAddress, feeToken == paidToken ? costCutFee : paidTokenAmount); 

        IERC20(listedToken).transfer(msg.sender, feeToken == listedToken ? costCutFee : amount); 

        orderInfo.takerAddresses.push(msg.sender);
        orderInfo.dealedAmounts.push(amount);
        orderInfo.dealedTakeTimes.push(block.timestamp);
        orderbook.recordDealedInfo(bSellList, orderId, orderInfo.takerAddresses.length - 1);
        
        uint256[] memory orderIds = userOrdersMap[msg.sender];
        if (orderIds.length == 0) {
            userOrdersMap[msg.sender].push(orderId);
        } else if (orderIds[orderIds.length - 1] != orderId) {
            userOrdersMap[msg.sender].push(orderId);
        }

        orderInfo.amount -= amount;
        if (leftAmount == amount) {
            orderInfo.status = OrderStatus.Dealed;
            listedOrders.remove(orderId);
        }

        emit TakeOrder(orderInfo.askAddress, msg.sender, orderId, amount, paidTokenAmount, orderInfo.spotPrice);
        return paidTokenAmount;
    }

    function getTokenAmountToPaid(uint256 orderId) public view returns(uint256) {
        OrderInfo memory orderInfo = totalOrders[orderId];
        uint256 paidTokenAmount = calculateAmountIn(orderInfo.spotPrice, orderInfo.amount);

        return paidTokenAmount;
    }

    function calculateAmountIn(uint256 spotPrice, uint256 orderAmount) public view returns(uint256) {
        uint256 paidTokenAmount = bSellList ? spotPrice * orderAmount / 1e18 : orderAmount * 1e18 / spotPrice;

        return paidTokenAmount;
    }

    function calculateAmountOut(uint256 spotPrice, uint256 paidTokenAmount) public view returns(uint256) {
        uint256 listedTokenAmountOut = bSellList ? paidTokenAmount * 1e18 / spotPrice
                                                 : paidTokenAmount * spotPrice / 1e18;

        return listedTokenAmountOut;
    }

    function takeOrders(uint256[] memory orderIds) external payable returns(uint256) {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < orderIds.length; i++) {
            totalAmount += takeOrder(orderIds[i], 0);
        }

        return totalAmount;
    }

    function takeOrders(uint256 inAmount, uint256 minOutAmount) external payable {
        uint256 leftAmount = inAmount;
        uint256 outAmount = 0;
        (bool exist, uint256 orderId) = getHeaderOrderIndex();
        while(exist && leftAmount > 0) {
            uint256 paidTokenAmount = getTokenAmountToPaid(orderId);
            if (leftAmount >= paidTokenAmount) {
                outAmount += takeOrder(orderId, 0);
                leftAmount -= paidTokenAmount;
            } else {
                OrderInfo memory orderInfo = totalOrders[orderId];
                uint256 listedTokenAmountOut = calculateAmountOut(orderInfo.spotPrice, leftAmount);
                outAmount += takeOrder(orderId, listedTokenAmountOut);
                leftAmount = 0;
            }
            (exist, orderId) = getHeaderOrderIndex();
        }
        require(outAmount >= minOutAmount, "!minOutAmount");
    }

    function setFeeRate(uint256 _feeRate) external onlyOwner {
        feeRate = _feeRate;
    }

    function withdrawFee(address receiver) external onlyOwner {
        if (listedToken == address(0) || paidToken == address(0)) {
            payable (receiver).transfer(platformFee);
        } else if (isBasicQuoteToken(listedToken)) {
            IERC20(listedToken).transfer(receiver, platformFee);
        } else {
            IERC20(paidToken).transfer(receiver, platformFee);
        }
        platformFee = 0;
    }

    function getListingOrders(uint256 fromIndex, uint256 toIndex) view public returns(OrderInfo[] memory orderInfos) {
        uint256 length = getTotalOrderNumber();
        if (toIndex > length) toIndex = length;
        require(fromIndex < toIndex, "Orderlist: index is out of bound.");
        
        orderInfos = new OrderInfo[](toIndex - fromIndex);
        uint256 index = 0;
        (bool exist, uint256 currentId) = getNodeInfo(0);
        while(index < toIndex && exist) {
            if (index < fromIndex) {
                (exist, currentId) = getNodeInfo(currentId);
                index++;
                continue;
            }

            orderInfos[index - fromIndex] = totalOrders[currentId];
            
            (exist, currentId) = getNodeInfo(currentId);
            index++;
        }
    }

    function getUserOrders(address user, uint256 fromIndex, uint256 toIndex) external view returns(OrderInfo[] memory orderInfos) {
        uint256 userOrderLength = getUserOrderNumber(user);
        if (toIndex > userOrderLength) toIndex = userOrderLength;
        require(fromIndex < toIndex, "Orderlist: index is out of bound.");

        orderInfos = new OrderInfo[](toIndex - fromIndex);
        for (uint256 i = toIndex - 1; i >= fromIndex; i--) {
            uint256 orderId = userOrdersMap[user][i];
            orderInfos[userOrderLength - 1 - i] = totalOrders[orderId];

            if (i == 0) break;
        }
    }

    function getDealedOrderInfo(uint256 orderId, uint256 dealedOrderIndex) external view 
        returns(OrderInfo memory orderInfo, address takerAddress, uint256 amount, uint256 time) {
            orderInfo = totalOrders[orderId];
            takerAddress = totalOrders[orderId].takerAddresses[dealedOrderIndex];
            amount = totalOrders[orderId].dealedAmounts[dealedOrderIndex];
            time = totalOrders[orderId].dealedTakeTimes[dealedOrderIndex];
        }
}
