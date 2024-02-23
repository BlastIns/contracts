// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./BlastClaim.sol";

contract Spread is BlastClaim {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => address) public spreadMap;  // Referee => Referrer
    mapping (address => EnumerableSet.AddressSet) private referrer2Referees;
    EnumerableSet.AddressSet private referrers;

    event SetReferrer(address indexed referee, address indexed referrer, uint256 timestamp);

    constructor () BlastClaim(_msgSender()) {
        spreadMap[_msgSender()] = _msgSender();
    }

    function setReferrer(address referrer) public {
        require(spreadMap[referrer] != address(0), "Invalid Referrer");
        require(spreadMap[msg.sender] == address(0), "Have Referred!");

        spreadMap[msg.sender] = referrer;
        referrer2Referees[referrer].add(msg.sender);
        referrers.add(referrer);

        emit SetReferrer(msg.sender, referrer, block.timestamp);
    }

    function getAllReferrersNumber() view public returns(uint256) {
        return referrers.length();
    }

    function getAllRefereesNumber(address referrer) view public returns(uint256) {
        return referrer2Referees[referrer].length();
    }

    function getReferrersStat(uint256 fromIndex, uint256 toIndex) view public 
        returns(address[] memory referrerAddrs, uint256[] memory refereeNumbers) {    
        referrerAddrs = new address[](toIndex - fromIndex);
        refereeNumbers = new uint256[](toIndex - fromIndex);
        for (uint256 i = fromIndex; i < toIndex; i++) {
            address referrer = referrers.at(i);
            referrerAddrs[i - fromIndex] = referrer;
            refereeNumbers[i - fromIndex] = getAllRefereesNumber(referrer);
        }
    }
}