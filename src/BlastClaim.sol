// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IBlast.sol";


contract BlastClaim is Ownable {
    address public constant BLAST = 0x4300000000000000000000000000000000000002;
    
    constructor (address owner) Ownable(owner) {    
        IBlast(BLAST).configureClaimableYield();
        IBlast(BLAST).configureGovernor(address(this));
        IBlast(BLAST).configureClaimableGas();
    }

    function claimAllGas(address recipient) external onlyOwner {
		  IBlast(BLAST).claimAllGas(address(this), recipient);
    }

    function claimMaxGas(address recipient) external onlyOwner {
		  IBlast(BLAST).claimMaxGas(address(this), recipient);
    }

    function claimGasAtMinClaimRate(address recipient, uint256 minClaimRateBips ) external onlyOwner {
      IBlast(BLAST).claimGasAtMinClaimRate(address(this), recipient, minClaimRateBips);
    }
}