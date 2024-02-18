// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./IBlast.sol";
import "./BlastClaim.sol";


contract BlastClaimWithYield is BlastClaim {
    constructor (address owner) BlastClaim(owner) {    
    }

    function claimAllYield(address recipient) external onlyOwner {
        IBlast(BLAST).claimAllYield(address(this), recipient);
    }
}