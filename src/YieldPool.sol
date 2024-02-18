// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IBlast.sol";
import "./BlastClaim.sol";     
import "./ISmartBlas.sol";       


contract YieldPool is BlastClaim {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;  
    }

    struct PoolInfo {
        IERC20 lpToken;           
        uint256 allocPoint;      
        uint256 accYieldPerShare;   
    }

    PoolInfo[] public poolList;        
    
    mapping (uint256 => mapping (address => UserInfo)) public userInfoMap; 
    
    uint256 public constant FACTOR = 1e18;
    uint256 public constant PLATFORM_FEE = 500;  // 5%
    uint256 public totalAllocPoint = 0;
    ISmartBlas public iSmartBlas;
    uint256 public totalYield = 0;
    
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, uint256 reward);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(address _iSmartBlas, address owner) BlastClaim(owner) {
        iSmartBlas = ISmartBlas(_iSmartBlas);
        poolList.push(PoolInfo({
            lpToken: (IERC20)(_iSmartBlas),
            allocPoint: 10000,
            accYieldPerShare: 0
        }));
        totalAllocPoint += 10000;
    }    

    function poolLength() external view returns (uint256) {
        return poolList.length;
    }

    function addPool(uint256 _allocPoint, address _lpToken) public onlyOwner {
        totalAllocPoint += _allocPoint;
        poolList.push(PoolInfo({
            lpToken: (IERC20)(_lpToken),
            allocPoint: _allocPoint,
            accYieldPerShare: 0
        }));
    }

    function setPoolPoint(uint256 _pid, uint256 _allocPoint) public onlyOwner {
        totalAllocPoint = totalAllocPoint - poolList[_pid].allocPoint + _allocPoint;
        poolList[_pid].allocPoint = _allocPoint;
    }

    function userPendingYield(uint256 _pid, address _user) external view returns (uint256) {
        if (poolList.length <= _pid) return 0;
        PoolInfo memory poolInfo = poolList[_pid];
        UserInfo memory user = userInfoMap[_pid][_user];
        if (user.amount == 0) return 0;

        uint256 yieldPerShareNotClaimed = 0;
        uint256 yieldNotClaimed = 
            IBlast(BLAST).readClaimableYield(address(iSmartBlas)) + IBlast(BLAST).readClaimableYield(address(this));
        if (yieldNotClaimed > 0) {
            uint256 poolYield = yieldNotClaimed * poolInfo.allocPoint / totalAllocPoint;
            uint256 lpSupply = poolInfo.lpToken.balanceOf(address(this)); 
            yieldPerShareNotClaimed = poolYield * FACTOR / lpSupply;
        }

        uint256 accYieldPerShare = poolInfo.accYieldPerShare + yieldPerShareNotClaimed;
        return user.amount * accYieldPerShare / FACTOR - user.rewardDebt; 
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        if (checkPoolsHasToken())
            claimAllYield();

        PoolInfo storage pool = poolList[_pid];
        UserInfo storage user = userInfoMap[_pid][msg.sender];
        if (user.amount > 0) {            
            uint256 pendingYield = user.amount * pool.accYieldPerShare / FACTOR - user.rewardDebt;
            withdrawYield(pendingYield);
        }
        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        user.amount += _amount;
        user.rewardDebt = user.amount * pool.accYieldPerShare / FACTOR;    
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _lpAmount) public {
        claimAllYield();

        PoolInfo storage pool = poolList[_pid];
        UserInfo storage user = userInfoMap[_pid][msg.sender];
        require(user.amount >= _lpAmount, "withdraw: not good");
               
        uint256 pendingYield = user.amount * pool.accYieldPerShare / FACTOR - user.rewardDebt;
        if (pendingYield > 0) {
            withdrawYield(pendingYield);
        }
        if (_lpAmount > 0) {
            user.amount -= _lpAmount;
            pool.lpToken.safeTransfer(address(msg.sender), _lpAmount);  
        }
        user.rewardDebt = user.amount * pool.accYieldPerShare / FACTOR;
        emit Withdraw(msg.sender, _pid, _lpAmount, pendingYield);
    }

    function claimAllYield() public {
        iSmartBlas.claimAllYield2Pool();
        depositSelfYield();
    }

    function depositYield() payable external {
        depositYieldOnce(msg.value);
    }

    function depositSelfYield() public {
        if (IBlast(BLAST).readClaimableYield(address(this)) > 0) {
            uint256 ethBeforeClaim = address(this).balance;
            IBlast(BLAST).claimAllYield(address(this), address(this));
            uint256 ethYield = address(this).balance - ethBeforeClaim;
            depositYieldOnce(ethYield);
        }
    }

    function depositYieldOnce(uint256 yieldAmount) internal {
        totalYield += yieldAmount;
        for (uint256 i = 0; i < poolList.length; i++) {
            PoolInfo storage poolInfo = poolList[i];
            uint256 poolYield = yieldAmount * poolInfo.allocPoint / totalAllocPoint;
            uint256 lpSupply = poolInfo.lpToken.balanceOf(address(this)); 
            require(lpSupply > 0, "The supply of token in pool must be larger than zero.");
            poolInfo.accYieldPerShare += poolYield * FACTOR / lpSupply;
        }
    }

    function withdrawYield(uint256 yieldAmount) internal {
        uint256 platformFee = yieldAmount * PLATFORM_FEE / 10000;
        payable (owner()).transfer(platformFee);
        payable (msg.sender).transfer(yieldAmount - platformFee);
    }

    function checkPoolsHasToken() internal view returns(bool) {
        for (uint256 i = 0; i < poolList.length; i++) {
            PoolInfo memory poolInfo = poolList[i];
            uint256 lpSupply = poolInfo.lpToken.balanceOf(address(this)); 
            
            if (lpSupply == 0) return false;
        }

        return true;
    }
}