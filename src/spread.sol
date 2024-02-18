// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IMinter {
    function userMintInscriptionAmount(address) external view returns(uint256);
}

contract Spread is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => address) public spreadMap;  // Referee => Referrer
    IMinter public minter;
    mapping (address => EnumerableSet.AddressSet) private referrer2Referees;
    EnumerableSet.AddressSet private referrers;

    event SetReferrer(address indexed referee, address indexed referrer);

    constructor (address _minter) Ownable(_msgSender()) {
        minter = IMinter(_minter);
    }

    function setReferrer(address referrer) public {
        require(spreadMap[msg.sender] == address(0), "!Referrer");

        spreadMap[msg.sender] = referrer;
        referrer2Referees[referrer].add(msg.sender);
        referrers.add(referrer);
    }

    function getAllReferrersNumber() view public returns(uint256) {
        return referrers.length();
    }

    function getReferrersMintStat(uint256 fromIndex, uint256 toIndex) view public returns(uint256) {
        uint256 totalMintAmount = 0;
        for (uint256 i = fromIndex; i < toIndex; i++) {
            address referrer = referrers.at(i);
            totalMintAmount += getReferrerMintStat(referrer);
        }
        return totalMintAmount;
    }

    function getReferrerMintStat(address referrer) view public returns(uint256) {
        uint256 totalMintAmount = 0;
        uint256 refereeNumber = referrer2Referees[referrer].length();
        for (uint256 j = 0; j < refereeNumber; j++) {
            address referee = referrer2Referees[referrer].at(j);
            totalMintAmount += minter.userMintInscriptionAmount(referee);
        }
        return totalMintAmount;
    }

    function getReferrersWalletStat(uint256 fromIndex, uint256 toIndex) view public returns(uint256) {
        uint256 totalWalletAmount = 0;
        for (uint256 i = fromIndex; i < toIndex; i++) {
            address referrer = referrers.at(i);
            totalWalletAmount += getReferrerWalletStat(referrer);
        }
        return totalWalletAmount;
    }

    function getReferrerWalletStat(address referrer) view public returns(uint256) {
        uint256 totalWalletAmount = 0;
        uint256 refereeNumber = referrer2Referees[referrer].length();
        for (uint256 j = 0; j < refereeNumber; j++) {
            address referee = referrer2Referees[referrer].at(j);
            totalWalletAmount += minter.userMintInscriptionAmount(referee) > 0 ? 1 : 0;
        }
        return totalWalletAmount;
    }
}