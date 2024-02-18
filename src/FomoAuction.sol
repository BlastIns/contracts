// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./BlastClaimWithYield.sol";

contract FomoAuction is BlastClaimWithYield {

    struct AuctionInfo {
        address lastUser;
        uint256 lastAmount;
        uint256 startTime;
        uint256 lastTime;
        uint256 totalPoints;
        uint256 accFeePerPoint;
        bool claimedByOwner;
    }

    struct UserInfo {
        uint256 points;
        uint256 rewardDebt;  
        uint256 leftAmount;
        bool claimed;
    }

    uint256 public curRound = 0;
    mapping(uint256 round => AuctionInfo) public roundAuctionMap;
    mapping(address user => uint256 winTimes) public userWinTimes;
    mapping(uint256 round => mapping(address user => UserInfo)) public userInfoMap;
    uint256 public startAmount = 0.005 ether;
    uint256 public constant MinAdditionalAmount = 0.005 ether;
    uint256 public constant feeRate = 10;
    uint256 public constant PeriodPerRound = 24 * 3600;  // 24 hours
    uint256 public constant MinDuration = 5 * 60;    // 5 minutes

    event EnterNextRound(uint256 round);
    event Bid(address bidder, uint256 round, uint256 bidAmount);

    constructor () BlastClaimWithYield(_msgSender()) {
    }

    function startNextRound() external {
        if (curRound == 0) {
            require(msg.sender == owner(), "Only owner could start the first round");
        } else {
            AuctionInfo memory auctionInfo = roundAuctionMap[curRound];
            uint256 endTime = getEndTime(curRound);
            require(block.timestamp > endTime, "Not end!");
            userWinTimes[auctionInfo.lastUser] += 1;
        }

        curRound += 1;
        roundAuctionMap[curRound] = AuctionInfo(
            address(0),
            0,
            block.timestamp,
            block.timestamp,
            0,
            0,
            false
        );

        emit EnterNextRound(curRound);
    }
    
    function bid() external payable {
        require(curRound > 0, "Not start");
        AuctionInfo storage auctionInfo = roundAuctionMap[curRound];
        uint256 endTime = getEndTime(curRound);
        require(endTime > block.timestamp, "Current round end!");

        UserInfo storage userInfo = userInfoMap[curRound][msg.sender];
        uint256 curPaid = msg.value + userInfo.leftAmount;
        require(curPaid - auctionInfo.lastAmount >= MinAdditionalAmount, 
            "The minimum additional cost is 0.005 ETH.");

        uint256 curFee = 0;
        uint256 curFeePerPoint = 0;
        uint256 accFeePerPoint = auctionInfo.accFeePerPoint;
        if (auctionInfo.totalPoints > 0) {
            curFee = curPaid / feeRate;
            curFeePerPoint = curFee / auctionInfo.totalPoints;
            accFeePerPoint += curFeePerPoint;
        }

        auctionInfo.lastUser = msg.sender;
        auctionInfo.lastAmount = curPaid;
        auctionInfo.lastTime = block.timestamp;
        auctionInfo.totalPoints += 1;
        auctionInfo.accFeePerPoint = accFeePerPoint;
        
        userInfo.rewardDebt += accFeePerPoint;
        userInfo.points += 1;
        userInfo.leftAmount = curPaid - curFee;

        emit Bid(msg.sender, curRound, curPaid);
    }

    function getEndTime(uint256 round) public view returns(uint256) {
        AuctionInfo memory auctionInfo = roundAuctionMap[round];
        uint256 timePoint1 = auctionInfo.startTime + PeriodPerRound;
        uint256 timePoint2 = auctionInfo.lastTime + MinDuration;
        uint256 lastTime = timePoint1 > timePoint2 ? timePoint1 : timePoint2;
        return lastTime;
    }

    function claimableReward(address user, uint256 round) public view returns(uint256) {
        AuctionInfo memory auctionInfo = roundAuctionMap[round];
        UserInfo memory userInfo = userInfoMap[round][user];

        if (auctionInfo.lastUser == address(0) || userInfo.points == 0) return 0;

        return auctionInfo.accFeePerPoint * userInfo.points - userInfo.rewardDebt;
    }

    function claimRewardAndPaidAmount(uint256 round) external {
        require(round < curRound, "Can claim the reward only in completed round.");
        UserInfo storage userInfo = userInfoMap[round][msg.sender];
        require(!userInfo.claimed, "Claimed!");
        uint256 reward = claimableReward(msg.sender, round);

        uint256 totalClaimableAmount = reward;
        AuctionInfo memory auctionInfo = roundAuctionMap[round];
        if (auctionInfo.lastUser != msg.sender) {
            totalClaimableAmount += userInfo.leftAmount;
        }

        userInfo.claimed = true;
        payable (msg.sender).transfer(totalClaimableAmount);
    }

    function claimAuctionFee(uint256 round, address receipt) onlyOwner external {
        require(round < curRound, "Can't claim reward at current round");
        AuctionInfo storage auctionInfo = roundAuctionMap[round];
        require(!auctionInfo.claimedByOwner, "Claimed!");

        auctionInfo.claimedByOwner = true;

        uint256 amount = auctionInfo.lastAmount - auctionInfo.lastAmount / feeRate;
        payable (receipt).transfer(amount);
    }
}