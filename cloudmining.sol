// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ISoliumcoin {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function paused() external view returns (bool);
}

contract CloudMining {
    ISoliumcoin public token; // SLM tokenı
    address public owner;
    address public treasury;
    uint256 public miningPoolBalance; // SLM ödül havuzu
    uint256 public bnbBalance; // BNB havuzu
    bool public active = true;
    uint256 public nextContractId = 1;
    uint256 public constant PROFIT_RATE = 10; // Aylık %10 kâr
    uint256 public constant CONTRACT_DURATION = 30 days; // 30 gün

    struct MiningPlan {
        uint256 amount; // Gerekli SLM miktarı
        bool active;
    }

    struct UserContract {
        address user;
        uint256 planId;
        uint256 amount; // Yatırılan SLM
        uint256 reward; // Toplam ödül (amount + %10)
        uint256 startTime;
        bool active;
    }

    mapping(uint256 => MiningPlan) public miningPlans;
    mapping(uint256 => UserContract) public userContracts;
    mapping(address => uint256[]) public userContractIds;
    uint256 public nextPlanId = 1;

    event MiningPlanCreated(uint256 indexed planId, uint256 amount, uint256 timestamp);
    event MiningContractPurchased(uint256 indexed contractId, address indexed user, uint256 planId, uint256 amount, uint256 reward, uint256 timestamp);
    event MiningRewardClaimed(uint256 indexed contractId, address indexed user, uint256 reward, uint256 timestamp);
    event ContractPaused(uint256 timestamp);
    event ContractUnpaused(uint256 timestamp);
    event TokensDeposited(address indexed depositor, uint256 amount, uint256 timestamp);
    event TokensWithdrawn(address indexed recipient, uint256 amount, uint256 timestamp);
    event BNBDeposited(address indexed depositor, uint256 amount, uint256 timestamp);
    event BNBWithdrawn(address indexed recipient, uint256 amount, uint256 timestamp);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!token.paused(), "Soliumcoin is paused");
        require(active, "Contract is paused");
        _;
    }

    constructor(address _token, address _treasury) {
        require(_token != address(0) && _treasury != address(0), "Invalid address");
        token = ISoliumcoin(_token);
        treasury = _treasury;
        owner = msg.sender;
    }

    // Madencilik planı oluştur
    function createMiningPlan(uint256 amount) external onlyOwner {
        require(amount > 0, "Invalid amount");
        miningPlans[nextPlanId] = MiningPlan({
            amount: amount,
            active: true
        });
        emit MiningPlanCreated(nextPlanId, amount, block.timestamp);
        nextPlanId++;
    }

    // Madencilik kontratı satın al
    function purchaseMiningContract(uint256 planId) external whenNotPaused {
        require(miningPlans[planId].active, "Plan not active");
        MiningPlan storage plan = miningPlans[planId];
        require(token.transferFrom(msg.sender, address(this), plan.amount), "Transfer failed");

        uint256 reward = plan.amount + (plan.amount * PROFIT_RATE) / 100; // %10 kâr
        miningPoolBalance += plan.amount;

        userContracts[nextContractId] = UserContract({
            user: msg.sender,
            planId: planId,
            amount: plan.amount,
            reward: reward,
            startTime: block.timestamp,
            active: true
        });
        userContractIds[msg.sender].push(nextContractId);

        emit MiningContractPurchased(nextContractId, msg.sender, planId, plan.amount, reward, block.timestamp);
        nextContractId++;
    }

    // Ödülleri talep et
    function claimRewards(uint256 contractId) external whenNotPaused {
        UserContract storage contract = userContracts[contractId];
        require(contract.user == msg.sender, "Not contract owner");
        require(contract.active, "Contract not active");
        require(block.timestamp >= contract.startTime + CONTRACT_DURATION, "Contract not expired");

        uint256 reward = contract.reward;
        require(miningPoolBalance >= reward, "Insufficient pool balance");

        contract.active = false;
        miningPoolBalance -= reward;
        require(token.transfer(msg.sender, reward), "Reward transfer failed");

        emit MiningRewardClaimed(contractId, msg.sender, reward, block.timestamp);
    }

    // Planı devre dışı bırak
    function deactivateMiningPlan(uint256 planId) external onlyOwner {
        require(miningPlans[planId].active, "Plan not active");
        miningPlans[planId].active = false;
    }

    // Kontratı duraklat
    function pauseContract() external onlyOwner {
        require(active, "Already paused");
        active = false;
        emit ContractPaused(block.timestamp);
    }

    // Kontratı aktif et
    function unpauseContract() external onlyOwner {
        require(!active, "Not paused");
        active = true;
        emit ContractUnpaused(block.timestamp);
    }

    // Havuza token yatır
    function depositTokens(uint256 amount) external onlyOwner whenNotPaused {
        require(amount > 0, "Invalid amount");
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        miningPoolBalance += amount;
        emit TokensDeposited(msg.sender, amount, block.timestamp);
    }

    // Havuza BNB yatır
    function depositBNB() external payable onlyOwner whenNotPaused {
        require(msg.value > 0, "Invalid amount");
        bnbBalance += msg.value;
        emit BNBDeposited(msg.sender, msg.value, block.timestamp);
    }

    // Havuzdan token çek (kısmi)
    function withdrawTokensPartial(address recipient, uint256 amount) external onlyOwner whenNotPaused {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0 && amount <= miningPoolBalance, "Invalid amount");
        miningPoolBalance -= amount;
        require(token.transfer(recipient, amount), "Transfer failed");
        emit TokensWithdrawn(recipient, amount, block.timestamp);
    }

    // Havuzdan BNB çek (kısmi)
    function withdrawBNBPartial(address payable recipient, uint256 amount) external onlyOwner whenNotPaused {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0 && amount <= bnbBalance, "Invalid amount");
        bnbBalance -= amount;
        recipient.transfer(amount);
        emit BNBWithdrawn(recipient, amount, block.timestamp);
    }

    // Havuzdan tüm tokenları çek
    function withdrawAllTokens(address recipient) external onlyOwner whenNotPaused {
        require(recipient != address(0), "Invalid recipient");
        require(miningPoolBalance > 0, "No tokens to withdraw");
        uint256 amount = miningPoolBalance;
        miningPoolBalance = 0;
        require(token.transfer(recipient, amount), "Transfer failed");
        emit TokensWithdrawn(recipient, amount, block.timestamp);
    }

    // Havuzdan tüm BNB’yi çek
    function withdrawAllBNB(address payable recipient) external onlyOwner whenNotPaused {
        require(recipient != address(0), "Invalid recipient");
        require(bnbBalance > 0, "No BNB to withdraw");
        uint256 amount = bnbBalance;
        bnbBalance = 0;
        recipient.transfer(amount);
        emit BNBWithdrawn(recipient, amount, block.timestamp);
    }
}
