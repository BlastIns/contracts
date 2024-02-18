// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "./SmartBlas.sol";
import "./YieldPool.sol";
import "./BlastClaim.sol";
import "./IBlast.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IAuction {
    function userWinTimes(address user) external returns(uint256);
}

contract DeployFactory is BlastClaim {
    using Strings for *;

    struct DeployInfo {
        string name;
        uint256 fee;
        uint256 limit;
        uint256 maxMints;
        address inscription;
    }

    struct SmartBlasInfo {
        uint256 mintCount;
        uint256 yield;
        uint256 gasFee; 
        address owner;
        uint256 yourInsAmount;
        uint256 yourTokenAmount; 
        uint256 birthTime;
        uint256 inscriptionBurnedBatches;
        uint256 tokenBurnedBatches;
        address yieldPool;
        uint256 totalYieldInPool;
    }

    mapping(string => DeployInfo) public nameDeployInfoMap;
    string[] public nameList;
    address public dev;
    IAuction public auction;
    mapping(address user => uint256 deployTimes) public userDeployTimesMap;

    event DEPLOY(
        address indexed to,
        string content
    );

    constructor(address _dev) BlastClaim(msg.sender) {
        dev = _dev;
    }

    function setAuction(address _auction) public onlyOwner {
        auction = IAuction(_auction);
    }

    function deploy(string memory name, uint256 fee, uint256 limit, uint256 maxMints) public {
        require(nameDeployInfoMap[name].inscription == address(0), "Exist!");

        if (address(auction) != address(0) && msg.sender != owner()) {
            uint256 maxDeployTimes = auction.userWinTimes(msg.sender);
            require(userDeployTimesMap[msg.sender] + 1 <= maxDeployTimes, "No auth to deploy inscription.");
            userDeployTimesMap[msg.sender] += 1;
        }

        SmartBlas smartBlas = new SmartBlas(msg.sender);           
        YieldPool yieldPool = new YieldPool(address(smartBlas), dev);

        smartBlas.initialize(address(yieldPool), name, fee, limit, maxMints);

        nameDeployInfoMap[name] = DeployInfo(name, fee, limit, maxMints, address(smartBlas));
        nameList.push(name);

        string memory deployInscription = 
            string(abi.encodePacked('data:,{"p":"bls-20","op":"deploy","tick":"', 
                                    name, 
                                    '","max":"', 
                                    (limit * maxMints).toString(), 
                                    '","lim":"', 
                                    limit.toString(), 
                                    '"}'));

        emit DEPLOY(msg.sender, deployInscription);
    }

    function totalInscriptionNum() view public returns(uint256) {
        return nameList.length;
    }

    function getInscriptions(uint256 fromIndex, uint256 toIndex) view public 
        returns(DeployInfo[] memory deployInfos, 
                SmartBlasInfo[] memory smartBlasInfos) {
        deployInfos = new DeployInfo[](toIndex - fromIndex);
        smartBlasInfos = new SmartBlasInfo[](toIndex - fromIndex);

        for (uint256 i = fromIndex; i < nameList.length && i < toIndex; i++) {
            (deployInfos[i - fromIndex], smartBlasInfos[i - fromIndex]) = getInscriptionByName(nameList[i]);
        }
    }

    function getInscriptionByName(string memory name) view public 
        returns(DeployInfo memory deployInfo, 
                SmartBlasInfo memory smartBlasInfo) {
        deployInfo = nameDeployInfoMap[name];

        SmartBlas blas = SmartBlas(payable (deployInfo.inscription));
        uint256 mintCount = blas.mintCounter();
        uint256 yield = IBlast(BLAST).readClaimableYield(deployInfo.inscription);
        (,uint256 gasFee,,) = IBlast(BLAST).readGasParams(deployInfo.inscription);
        address owner = blas.owner();
        uint256 yourInsAmount = blas.userMintInscriptionAmount(msg.sender);
        uint256 yourTokenAmount = blas.balanceOf(msg.sender);
        uint256 birthTime = blas.birthTime();
        uint256 inscriptionBurnedBatches = blas.inscriptionBurnedBatches();
        uint256 tokenBurnedBatches = blas.tokenBurnedBatches();
        address yieldPool = address(blas.yieldPool());
        uint256 totalYieldInPool = YieldPool(yieldPool).totalYield();

        smartBlasInfo = SmartBlasInfo(mintCount, yield, gasFee, owner, yourInsAmount, yourTokenAmount, 
                                      birthTime, inscriptionBurnedBatches, tokenBurnedBatches, 
                                      yieldPool, totalYieldInPool);
    }

    function claimFee(address recipient) external onlyOwner {
        payable(recipient).transfer(address(this).balance);
    }

    function claimAllYield() public {
        IBlast(BLAST).claimAllYield(address(this), address(this));
    }
}