/**
 *Submitted for verification at BscScan.com on 2025-04-14
*/

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

contract TokenPresale {
    address public owner;
    address public saleToken;

    uint256 public tokenPrice = 0.01 ether;
    uint256 public tokensPerUnit = 100 * 10**18;

    bool public saleEnded = false;
    bool public salePaused = false;

    uint256 public softCap = 1 ether;
    uint256 public hardCap = 5000 ether;
    uint256 public totalRaised = 0;

    event TokensPurchased(address indexed buyer, uint256 bnbAmount, uint256 tokenAmount, uint256 timestamp);
    event SaleEnded();
    event SaleStarted();
    event SalePaused();
    event SalePlayed();

    constructor(address _token) {
        require(_token != address(0), "Invalid token address");
        owner = msg.sender;
        saleToken = _token;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier saleActive() {
        require(!saleEnded, "Sale ended");
        require(!salePaused, "Sale paused");
        _;
    }

    function setTokenAddress(address _token) external onlyOwner {
        require(_token != address(0), "Zero token address");
        saleToken = _token;
    }

    function setTokenPrice(uint256 _price) external onlyOwner {
        require(_price > 0, "Invalid price");
        tokenPrice = _price;
    }

    function setTokensPerUnit(uint256 _amount) external onlyOwner {
        require(_amount > 0, "Invalid amount");
        tokensPerUnit = _amount;
    }

    function buyTokens() public payable saleActive {
        require(msg.value >= tokenPrice, "Not enough BNB sent");
        require(totalRaised + msg.value <= hardCap, "Hardcap reached");

        uint256 units = msg.value / tokenPrice;
        uint256 totalTokens = units * tokensPerUnit;

        // balanceOf(address(this))
        (bool success1, bytes memory data1) = saleToken.call(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        require(success1, "balanceOf failed");
        uint256 tokenBalance = abi.decode(data1, (uint256));
        require(tokenBalance >= totalTokens, "Not enough tokens");

        totalRaised += msg.value;

        // transfer(msg.sender, totalTokens)
        (bool success2, ) = saleToken.call(
            abi.encodeWithSignature("transfer(address,uint256)", msg.sender, totalTokens)
        );
        require(success2, "Token transfer failed");

        emit TokensPurchased(msg.sender, msg.value, totalTokens, block.timestamp);
    }

    function endSale() external onlyOwner {
        saleEnded = true;
        emit SaleEnded();
    }

    function startSale() external onlyOwner {
        saleEnded = false;
        salePaused = false;
        emit SaleStarted();
    }

    function pauseSale() external onlyOwner {
        salePaused = true;
        emit SalePaused();
    }

    function playSale() external onlyOwner {
        require(salePaused, "Sale not paused");
        salePaused = false;
        emit SalePlayed();
    }

    function withdrawUnsoldTokens() external onlyOwner {
        require(saleEnded, "Sale not ended");
        (bool success1, bytes memory data1) = saleToken.call(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        require(success1, "balanceOf failed");
        uint256 tokenBalance = abi.decode(data1, (uint256));
        require(tokenBalance > 0, "No tokens to withdraw");

        (bool success2, ) = saleToken.call(
            abi.encodeWithSignature("transfer(address,uint256)", owner, tokenBalance)
        );
        require(success2, "Transfer failed");
    }

    function withdrawRaisedBNB() external onlyOwner {
        require(saleEnded, "Sale not ended");
        payable(owner).transfer(address(this).balance);
    }

    // --- New Functions Added ---

    /// @notice Returns the amount of BNB in ​​the contract.
    function getTotalBNB() public view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Returns the remaining (unsold) amount in the contract from the tokens offered for sale.
    function getRemainingTokens() public view returns (uint256) {
        (bool success, bytes memory data) = saleToken.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        require(success, "balanceOf failed");
        uint256 remaining = abi.decode(data, (uint256));
        return remaining;
    }

    /// @notice Used to withdraw tokens other than the sale token that were accidentally sent to the contract.
    /// @param _token The address of the token you want to withdraw.
    function withdrawForeignTokens(address _token) external onlyOwner {
        require(_token != saleToken, "Cannot withdraw sale token");
        (bool success, bytes memory data) = _token.call(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        require(success, "balanceOf failed");
        uint256 tokenBalance = abi.decode(data, (uint256));
        require(tokenBalance > 0, "No tokens to withdraw");
        (bool success2, ) = _token.call(
            abi.encodeWithSignature("transfer(address,uint256)", owner, tokenBalance)
        );
        require(success2, "Token transfer failed");
    }

    receive() external payable {
        buyTokens();
    }
}
