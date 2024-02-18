// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./IBlast.sol";
import "./IYieldPool.sol";
import "./BlastClaim.sol";


contract SmartBlas is BlastClaim, ERC20 {
    using Strings for *;

    string  public mintInscription;
    string  public inscriptionName;
    uint256 public FEE;
    uint256 public Limit;
    uint256 public MAX_MINT;
    uint256 public mintCounter = 0;
    mapping(address => uint256) public userMintInscriptionAmount;
    uint256 public birthTime;
    uint256 public inscriptionBurnedBatches;
    uint256 public tokenBurnedBatches;
    IYieldPool public yieldPool;

    event MINT(
        address indexed to,
        string content
    );

    event TRANSFER(
        address indexed from,
        address indexed to,
        string content
    );

    event MAP(
        address indexed from,
        uint256 amount
    );

    event RMAP(
        address indexed from,
        uint256 amount
    );

    event BURN(
        address indexed from,
        uint256 batches,
        bool bInscriptionOrToken
    );
    
    constructor (address owner) BlastClaim(owner) ERC20("Blast Smart Inscription", "BLAS") {    
        birthTime = block.timestamp;    
    }

    receive() external payable {
        require(msg.value >= FEE, "Minter: fee not enough");
        require(mintCounter < MAX_MINT, "Minter: max mint reached");
        require(msg.sender == tx.origin, "Only EOA");
        mint();
    }

    function claimAllYield2Pool() external {
        if (IBlast(BLAST).readClaimableYield(address(this)) > 0) {
            uint256 ethBeforeClaim = address(this).balance;
            IBlast(BLAST).claimAllYield(address(this), address(this));
            uint256 yieldValue = address(this).balance - ethBeforeClaim;

            yieldPool.depositYield{value: yieldValue}();
        }
    }

    function initialize(address _yieldPool, string memory _inscriptionName, uint256 fee, uint256 limit, uint256 maxMint) public {           
        require(bytes(_inscriptionName).length >= 3 && bytes(_inscriptionName).length < 6, "length of name should be [3, 6)");     
        require(checkName(_inscriptionName), "Invalid inscription name string");
        yieldPool = IYieldPool(_yieldPool);
        inscriptionName = _inscriptionName;
        mintInscription = 
            string(abi.encodePacked('data:,{"p":"bls-20","op":"mint","tick":"', 
                                    inscriptionName, 
                                    '",', 
                                    '"amt":"', 
                                    limit.toString(), 
                                    '"}'));
        FEE = fee;
        Limit = limit;
        MAX_MINT = maxMint;
    }

    function symbol() public view override virtual returns (string memory) {
        return inscriptionName;
    }

    function mint() private {
        emit MINT(msg.sender, mintInscription);
        mintCounter++;
        userMintInscriptionAmount[msg.sender] += Limit;
    }

    function transferInscription(address to, uint256 amount) public {
        require(userMintInscriptionAmount[msg.sender] >= amount, "Amount of your inscription NOT enough!");
        
        userMintInscriptionAmount[msg.sender] -= amount;
        userMintInscriptionAmount[to] += amount;
        
        string memory transferIns = 
            string(abi.encodePacked('data:,{"p":"bls-20","op":"transfer","tick":"', 
                                    inscriptionName,
                                    '","amt":"', 
                                    amount.toString(), 
                                    '"}'));

        emit TRANSFER(msg.sender, to, transferIns);
    }

    function mapInsToERC20(uint256 amount) public {
        require(userMintInscriptionAmount[msg.sender] >= amount, "Not enough inscription amount");
        userMintInscriptionAmount[msg.sender] -= amount;
        _mint(msg.sender, amount * 1 ether);

        emit MAP(msg.sender, amount);
    }

    function mapERC20ToIns(uint256 amount) public {
        require(balanceOf(msg.sender) >= amount, "Not enough ERC20 amount");   
        amount = amount / 1 ether * 1 ether;     
        _burn(msg.sender, amount);
        userMintInscriptionAmount[msg.sender] += amount / 1 ether;
        emit RMAP(msg.sender, amount);
    }

    function burnERC20(uint256 batches) public {
        uint256 totalBurnAmount = batches * Limit * 1 ether;
        require(balanceOf(msg.sender) >= totalBurnAmount, "Not enough ERC20 token!");
        _burn(msg.sender, totalBurnAmount);
        if (FEE > 0)
            payable(msg.sender).transfer(FEE * batches);
        tokenBurnedBatches += batches;

        emit BURN(msg.sender, batches, false);
    }

    function burnInscription(uint256 batches) public {
        uint256 totalBurnAmount = batches * Limit;
        require(userMintInscriptionAmount[msg.sender] >= totalBurnAmount, "Not enough inscription!");
        userMintInscriptionAmount[msg.sender] -= totalBurnAmount;
        if (FEE > 0)
            payable(msg.sender).transfer(FEE * batches);
        inscriptionBurnedBatches += batches;

        emit BURN(msg.sender, batches, true);
    }

    function checkName(string memory _name) public pure returns(bool){
        uint256 allowedChars = 0;
        bytes memory byteString = bytes(_name);
        bytes memory allowed = bytes("abcdefghijklmnopqrstuvwxyz0123456789");  //here you put what character are allowed to use
        for(uint256 i = 0; i < byteString.length; i++){
           for(uint256 j = 0; j < allowed.length; j++){
              if (byteString[i] == allowed[j])
                allowedChars++;         
           }
        }
        return allowedChars == byteString.length;
    }
}