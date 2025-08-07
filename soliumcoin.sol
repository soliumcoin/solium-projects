// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract Soliumcoin {
    string public name = "SOLIUM CHAIN";
    string public symbol = "SLM";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    address public owner;
    bool public paused;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Paused(address indexed owner, uint256 timestamp);
    event Unpaused(address indexed owner, uint256 timestamp);
    event OwnershipRenounced(address indexed previousOwner, uint256 timestamp);
    event Burn(address indexed burner, uint256 amount, uint256 timestamp);

    modifier onlyOwner() {
        require(msg.sender == owner, "You are not the owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    constructor() {
        owner = msg.sender;
        totalSupply = 100000000 * (10 ** uint256(decimals)); // 100M SLM
        balanceOf[owner] = totalSupply;
        paused = false;
        emit Transfer(address(0), owner, totalSupply);
    }

    // Sözleşmenin duraklatılma durumunu döndür
    function paused() external view returns (bool) {
        return paused;
    }

    // Sözleşmeyi duraklat
    function pause() external onlyOwner {
        require(!paused, "Already paused");
        paused = true;
        emit Paused(msg.sender, block.timestamp);
    }

    // Sözleşmeyi aktif et
    function unpause() external onlyOwner {
        require(paused, "Not paused");
        paused = false;
        emit Unpaused(msg.sender, block.timestamp);
    }

    // Sahipliği bırak
    function renounceOwnership() external onlyOwner {
        emit OwnershipRenounced(owner, block.timestamp);
        owner = address(0);
    }

    // Token yak
    function burn(uint256 amount) external whenNotPaused {
        require(amount > 0, "Invalid amount");
        require(balanceOf[msg.sender] >= amount, "Not enough balance");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit Burn(msg.sender, amount, block.timestamp);
        emit Transfer(msg.sender, address(0), amount); // Yakma işlemi Transfer event'i ile
    }

    function transfer(address to, uint256 amount) external whenNotPaused returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Not enough balance");
        _transfer(msg.sender, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(to != address(0), "Invalid address");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    function approve(address spender, uint256 amount) external whenNotPaused returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external whenNotPaused returns (bool) {
        require(balanceOf[from] >= amount, "Not enough balance");
        require(allowance[from][msg.sender] >= amount, "Not approved");
        allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }
}
