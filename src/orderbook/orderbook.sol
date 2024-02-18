// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./orderlist.sol";
import "../BlastClaimWithYield.sol";
import { Checkpoints } from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import "./pyth/IPyth.sol";

contract Orderbook is BlastClaimWithYield {
    using Checkpoints for Checkpoints.Trace224;

    struct DealedOrder {
        uint256 orderId;
        bool bSold;  // true: sold, false: buy
        uint256 baseTokenAmount;
        uint256 quoteTokenAmount;
        uint256 spotPrice;
        address from;
        address to;
        uint256 time;
    }

    struct DealedOrderIdPair {
        bool bSellList;
        uint256 orderId;
        uint256 dealedIndex;
    }

    uint256 public feeRate;
    address public baseToken;
    address public quoteToken;  // ETH = address(0)
    OrderList public sellList;
    OrderList public buyList;
    DealedOrderIdPair[] public dealedOrderIdPairs; 

    IPyth public pyth;
    bytes32 public ethPriceId;
    address public constant WETH = address(0x4200000000000000000000000000000000000023);

    Checkpoints.Trace224 private totalVolumeCheckpoints;
    mapping(address account => Checkpoints.Trace224) private quoteTokenUserVolumeCheckpoints;
    mapping(address account => Checkpoints.Trace224) private baseTokenUserVolumeCheckpoints;

    // blas: 0x082fd79063139f5E2Fd978B3f1468D2f171F9939
    // weth: 0x4200000000000000000000000000000000000023
    // pyth@testnet = 0xA2aa501b19aff244D90cc15a4Cf739D2725B5729
    // priceId@testnet = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace
    constructor(address _baseToken, address _quoteToken, address _buyListFeeToken, address _sellListFeeToken, uint256 _feeRate, address _pyth, bytes32 _ethPriceId) BlastClaimWithYield(msg.sender) {
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        feeRate = _feeRate;
        buyList = new OrderList(address(this), quoteToken, baseToken, _buyListFeeToken, feeRate, false);
        sellList = new OrderList(address(this), baseToken, quoteToken, _sellListFeeToken, feeRate, true);
        pyth = IPyth(_pyth);
        ethPriceId = _ethPriceId;
    }

    function setFeeRate(uint256 _feeRate) external onlyOwner {
        feeRate = _feeRate;
        sellList.setFeeRate(_feeRate);
        buyList.setFeeRate(_feeRate);
    }

    function withdrawFee(address receiver) external onlyOwner {
        sellList.withdrawFee(receiver);
        buyList.withdrawFee(receiver);
    }

    function setPythInfo(address _pyth, bytes32 _ethPriceId) external onlyOwner {
        pyth = IPyth(_pyth);
        ethPriceId = _ethPriceId;
    }

    function claimOrderlistGasFee(address receiver) external onlyOwner {
        sellList.claimAllGas(receiver);
        buyList.claimAllGas(receiver);
    }

    function claimOrderlistYield(address receiver) external onlyOwner {
        sellList.claimAllYield(receiver);
        buyList.claimAllYield(receiver);
    }

    function recordDealedInfo(
        bool bSellList,
        uint256 orderId,
        uint256 dealedOrderIndex
    ) external {
        require(msg.sender == address(buyList) || msg.sender == address(sellList), "Only orderlist allowed");
        dealedOrderIdPairs.push(DealedOrderIdPair(bSellList, orderId, dealedOrderIndex));

        int64 quoteTokenPrice = 0;  // xxx U / ETH
        if (quoteToken == address(0) || quoteToken == WETH) {
            try pyth.getPrice(ethPriceId) returns (PythStructs.Price memory currentBasePrice) {
                quoteTokenPrice = currentBasePrice.price;
            } catch {
                PythStructs.Price memory currentBasePrice = pyth.getPriceUnsafe(ethPriceId);
                quoteTokenPrice = currentBasePrice.price;
            }
        }

        OrderList.OrderInfo memory orderInfo; 
        address quoteTokenPaidAddress;
        address baseTokenPaidAddress;
        address takerAddress;
        uint256 dealedAmount; 
        uint256 dealedTime;
        uint256 baseTokenAmount;
        uint256 quoteTokenAmount;
        if (bSellList) {
            (orderInfo, takerAddress, dealedAmount, dealedTime) 
                = sellList.getDealedOrderInfo(orderId, dealedOrderIndex);
            baseTokenAmount = dealedAmount;
            quoteTokenAmount = dealedAmount * orderInfo.spotPrice / 1e18;
            quoteTokenPaidAddress = takerAddress;
            baseTokenPaidAddress = orderInfo.askAddress;
        } else {
            (orderInfo, takerAddress, dealedAmount, dealedTime) 
                = buyList.getDealedOrderInfo(orderId, dealedOrderIndex);
            baseTokenAmount = dealedAmount * 1e18 / orderInfo.spotPrice;
            quoteTokenAmount = dealedAmount;    
            quoteTokenPaidAddress = orderInfo.askAddress;
            baseTokenPaidAddress = takerAddress;
        }
        uint256 quoteTokenValue = quoteTokenAmount * uint256(uint64(quoteTokenPrice)) / 1e18;
        
        uint224 latestValue = totalVolumeCheckpoints.latest();
        totalVolumeCheckpoints.push(uint32(block.number), uint224(latestValue + quoteTokenValue));

        uint224 quoteLastestValue = quoteTokenUserVolumeCheckpoints[quoteTokenPaidAddress].latest();
        quoteTokenUserVolumeCheckpoints[quoteTokenPaidAddress].push(uint32(block.number), 
                                                                    uint224(quoteLastestValue + quoteTokenValue));

        uint224 baseLastestValue = baseTokenUserVolumeCheckpoints[baseTokenPaidAddress].latest();
        baseTokenUserVolumeCheckpoints[baseTokenPaidAddress].push(uint32(block.number), 
                                                                  uint224(baseLastestValue + quoteTokenValue));
    }

    function getTotalVolumeAtBlock(uint32 blockHeight) public view returns(uint256) {
        return totalVolumeCheckpoints.upperLookupRecent(blockHeight);
    }

    function getUserSellVolumeAtBlock(address user, uint32 blockHeight) public view returns(uint256) {
        return baseTokenUserVolumeCheckpoints[user].upperLookupRecent(blockHeight);
    }

    function getUserBuyVolumeAtBlock(address user, uint32 blockHeight) public view returns(uint256) {
        return quoteTokenUserVolumeCheckpoints[user].upperLookupRecent(blockHeight);
    }

    function getTotalDealedOrderNumber() public view returns(uint256) {
        return dealedOrderIdPairs.length;
    }

    function getDealedOrders(uint256 fromIndex, uint256 toIndex) public view returns(DealedOrder[] memory dealedOrders) {
        if (toIndex > dealedOrderIdPairs.length) toIndex = dealedOrderIdPairs.length;
        require(fromIndex < toIndex, "Orderbook: index is out of bound.");

        dealedOrders = new DealedOrder[](toIndex - fromIndex);
        for (uint256 i = toIndex - 1; i >= fromIndex; i--) {
            DealedOrderIdPair memory dealedOrderInfo = dealedOrderIdPairs[i];
            OrderList.OrderInfo memory orderInfo; 
            address takerAddress;
            uint256 dealedAmount; 
            uint256 dealedTime;
            uint256 baseTokenAmount;
            uint256 quoteTokenAmount;
            if (dealedOrderInfo.bSellList) {
                (orderInfo, takerAddress, dealedAmount, dealedTime) 
                    = sellList.getDealedOrderInfo(dealedOrderInfo.orderId, dealedOrderInfo.dealedIndex);
                baseTokenAmount = dealedAmount;
                quoteTokenAmount = dealedAmount * orderInfo.spotPrice / 1e18;
            } else {
                (orderInfo, takerAddress, dealedAmount, dealedTime) 
                    = buyList.getDealedOrderInfo(dealedOrderInfo.orderId, dealedOrderInfo.dealedIndex);
                baseTokenAmount = dealedAmount * 1e18 / orderInfo.spotPrice;
                quoteTokenAmount = dealedAmount;    
            }
            dealedOrders[toIndex - 1 - i] = DealedOrder(
                orderInfo.orderId,
                !dealedOrderInfo.bSellList,
                baseTokenAmount,
                quoteTokenAmount,
                orderInfo.spotPrice,
                orderInfo.askAddress,
                takerAddress,
                dealedTime
            );
            if (i == 0) break;
        }
    }
}
