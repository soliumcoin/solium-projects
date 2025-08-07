// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ISoliumcoin {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function paused() external view returns (bool);
}

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface IERC721 {
    function safeMint(address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract SoliumGameFi {
    ISoliumcoin public token; // Ödül tokenı (SLM)
    IERC20 public betToken; // Bahis tokenı (SLM veya başka)
    IERC20 public usdt; // USDT tokenı
    IERC721 public nftContract;
    address public owner;
    address public treasury;
    uint256 public rewardPoolBalance; // SLM ödül havuzu
    uint256 public bnbBalance; // BNB havuzu
    uint256 public usdtBalance; // USDT havuzu
    uint256 public betTokenBalance; // Bahis token havuzu
    uint256 public houseBalance; // Kasa havuzu (SLM)
    uint256 public houseEdge = 5; // Kasa oranı %5

    bool public gameActive = true;
    uint256 public nextTaskId = 1;
    uint256 public nextNftId = 1;
    uint256 public nextBetId = 1;

    struct Task {
        uint256 rewardAmount;
        uint256 nftId;
        bool active;
    }

    struct RouletteBet {
        address player;
        uint256 amount;
        uint8 number; // 0-36
        uint256 blockNumber;
        bool resolved;
        uint8 betType; // 0: SLM, 1: BNB, 2: USDT
    }

    mapping(uint256 => Task) public tasks;
    mapping(address => mapping(uint256 => bool)) public completedTasks;
    mapping(uint256 => RouletteBet) public bets;

    event TaskCreated(uint256 indexed taskId, uint256 rewardAmount, uint256 nftId, uint256 timestamp);
    event TaskCompleted(address indexed player, uint256 indexed taskId, uint256 rewardAmount, uint256 nftId, uint256 timestamp);
    event GamePaused(uint256 timestamp);
    event GameUnpaused(uint256 timestamp);
    event HouseEdgeUpdated(uint256 newPercentage, uint256 timestamp);
    event TokenContractUpdated(address indexed newToken, uint256 timestamp);
    event BetTokenContractUpdated(address indexed newBetToken, uint256 timestamp);
    event RewardTokensDeposited(address indexed depositor, uint256 amount, uint256 timestamp);
    event RewardTokensWithdrawn(address indexed recipient, uint256 amount, uint256 timestamp);
    event BetTokensDeposited(address indexed depositor, uint256 amount, uint256 timestamp);
    event BetTokensWithdrawn(address indexed recipient, uint256 amount, uint256 timestamp);
    event USDTDeposited(address indexed depositor, uint256 amount, uint256 timestamp);
    event USDTWithdrawn(address indexed recipient, uint256 amount, uint256 timestamp);
    event BNBDeposited(address indexed depositor, uint256 amount, uint256 timestamp);
    event BNBWithdrawn(address indexed recipient, uint256 amount, uint256 timestamp);
    event HouseBalanceWithdrawn(address indexed recipient, uint256 amount, uint256 timestamp);
    event HouseBalanceToRewardPool(uint256 amount, uint256 timestamp);
    event RouletteBetPlaced(uint256 indexed betId, address indexed player, uint256 amount, uint8 number, uint8 betType, uint256 timestamp);
    event RouletteBetResolved(uint256 indexed betId, address indexed player, uint256 winnings, uint8 result, uint256 timestamp);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!token.paused(), "Soliumcoin is paused");
        require(gameActive, "Game is paused");
        _;
    }

    constructor(address _token, address _betToken, address _usdt, address _treasury, address _nftContract) {
        require(_token != address(0) && _betToken != address(0) && _usdt != address(0), "Invalid token address");
        require(_treasury != address(0), "Invalid treasury address");
        token = ISoliumcoin(_token);
        betToken = IERC20(_betToken);
        usdt = IERC20(_usdt);
        treasury = _treasury;
        nftContract = IERC721(_nftContract);
        owner = msg.sender;
    }

    // Token sözleşmelerini güncelle
    function setTokenContract(address newToken) external onlyOwner {
        require(newToken != address(0), "Invalid token address");
        token = ISoliumcoin(newToken);
        emit TokenContractUpdated(newToken, block.timestamp);
    }

    function setBetTokenContract(address newBetToken) external onlyOwner {
        require(newBetToken != address(0), "Invalid token address");
        betToken = IERC20(newBetToken);
        emit BetTokenContractUpdated(newBetToken, block.timestamp);
    }

    // Kasa oranını güncelle
    function setHouseEdge(uint256 newPercentage) external onlyOwner {
        require(newPercentage <= 100, "Invalid percentage");
        houseEdge = newPercentage;
        emit HouseEdgeUpdated(newPercentage, block.timestamp);
    }

    // Deposit fonksiyonları
    function depositRewardTokens(uint256 amount) external onlyOwner whenNotPaused {
        require(amount > 0, "Invalid amount");
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        rewardPoolBalance += amount;
        emit RewardTokensDeposited(msg.sender, amount, block.timestamp);
    }

    function depositBetTokens(uint256 amount) external onlyOwner whenNotPaused {
        require(amount > 0, "Invalid amount");
        require(betToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        betTokenBalance += amount;
        emit BetTokensDeposited(msg.sender, amount, block.timestamp);
    }

    function depositUSDT(uint256 amount) external onlyOwner whenNotPaused {
        require(amount > 0, "Invalid amount");
        require(usdt.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        usdtBalance += amount;
        emit USDTDeposited(msg.sender, amount, block.timestamp);
    }

    function depositBNB() external payable onlyOwner whenNotPaused {
        require(msg.value > 0, "Invalid amount");
        bnbBalance += msg.value;
        emit BNBDeposited(msg.sender, msg.value, block.timestamp);
    }

    // Withdraw fonksiyonları (kısmi)
    function withdrawRewardTokens(address recipient, uint256 amount) external onlyOwner whenNotPaused {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0 && amount <= rewardPoolBalance, "Invalid amount");
        rewardPoolBalance -= amount;
        require(token.transfer(recipient, amount), "Transfer failed");
        emit RewardTokensWithdrawn(recipient, amount, block.timestamp);
    }

    function withdrawBetTokens(address recipient, uint256 amount) external onlyOwner whenNotPaused {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0 && amount <= betTokenBalance, "Invalid amount");
        betTokenBalance -= amount;
        require(betToken.transfer(recipient, amount), "Transfer failed");
        emit BetTokensWithdrawn(recipient, amount, block.timestamp);
    }

    function withdrawUSDT(address recipient, uint256 amount) external onlyOwner whenNotPaused {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0 && amount <= usdtBalance, "Invalid amount");
        usdtBalance -= amount;
        require(usdt.transfer(recipient, amount), "Transfer failed");
        emit USDTWithdrawn(recipient, amount, block.timestamp);
    }

    function withdrawBNB(address payable recipient, uint256 amount) external onlyOwner whenNotPaused {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0 && amount <= bnbBalance, "Invalid amount");
        bnbBalance -= amount;
        recipient.transfer(amount);
        emit BNBWithdrawn(recipient, amount, block.timestamp);
    }

    // Withdraw fonksiyonları (tamamı)
    function withdrawAllRewardTokens(address recipient) external onlyOwner whenNotPaused {
        require(recipient != address(0), "Invalid recipient");
        require(rewardPoolBalance > 0, "No tokens to withdraw");
        uint256 amount = rewardPoolBalance;
        rewardPoolBalance = 0;
        require(token.transfer(recipient, amount), "Transfer failed");
        emit RewardTokensWithdrawn(recipient, amount, block.timestamp);
    }

    function withdrawAllBetTokens(address recipient) external onlyOwner whenNotPaused {
        require(recipient != address(0), "Invalid recipient");
        require(betTokenBalance > 0, "No tokens to withdraw");
        uint256 amount = betTokenBalance;
        betTokenBalance = 0;
        require(betToken.transfer(recipient, amount), "Transfer failed");
        emit BetTokensWithdrawn(recipient, amount, block.timestamp);
    }

    function withdrawAllUSDT(address recipient) external onlyOwner whenNotPaused {
        require(recipient != address(0), "Invalid recipient");
        require(usdtBalance > 0, "No USDT to withdraw");
        uint256 amount = usdtBalance;
        usdtBalance = 0;
        require(usdt.transfer(recipient, amount), "Transfer failed");
        emit USDTWithdrawn(recipient, amount, block.timestamp);
    }

    function withdrawAllBNB(address payable recipient) external onlyOwner whenNotPaused {
        require(recipient != address(0), "Invalid recipient");
        require(bnbBalance > 0, "No BNB to withdraw");
        uint256 amount = bnbBalance;
        bnbBalance = 0;
        recipient.transfer(amount);
        emit BNBWithdrawn(recipient, amount, block.timestamp);
    }

    // Kasa havuzunu çek
    function withdrawHouseBalance(address recipient, uint256 amount) external onlyOwner whenNotPaused {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0 && amount <= houseBalance, "Invalid amount");
        houseBalance -= amount;
        require(token.transfer(recipient, amount), "Transfer failed");
        emit HouseBalanceWithdrawn(recipient, amount, block.timestamp);
    }

    // Kasa havuzunu ödül havuzuna aktar
    function transferHouseToRewardPool(uint256 amount) external onlyOwner whenNotPaused {
        require(amount > 0 && amount <= houseBalance, "Invalid amount");
        houseBalance -= amount;
        rewardPoolBalance += amount;
        emit HouseBalanceToRewardPool(amount, block.timestamp);
    }

    function pauseGame() external onlyOwner {
        require(gameActive, "Game already paused");
        gameActive = false;
        emit GamePaused(block.timestamp);
    }

    function unpauseGame() external onlyOwner {
        require(!gameActive, "Game not paused");
        gameActive = true;
        emit GameUnpaused(block.timestamp);
    }

    function createTask(uint256 rewardAmount, uint256 nftId) external onlyOwner {
        require(rewardAmount <= rewardPoolBalance, "Insufficient reward pool balance");
        tasks[nextTaskId] = Task({
            rewardAmount: rewardAmount,
            nftId: nftId,
            active: true
        });
        rewardPoolBalance -= rewardAmount;
        emit TaskCreated(nextTaskId, rewardAmount, nftId, block.timestamp);
        nextTaskId++;
    }

    function completeTask(uint256 taskId) external whenNotPaused {
        require(tasks[taskId].active, "Task not active");
        require(!completedTasks[msg.sender][taskId], "Task already completed");

        Task storage task = tasks[taskId];
        completedTasks[msg.sender][taskId] = true;

        if (task.rewardAmount > 0) {
            require(token.transfer(msg.sender, task.rewardAmount), "Reward transfer failed");
        }

        if (task.nftId > 0) {
            require(nftContract.ownerOf(task.nftId) == address(0), "NFT already minted");
            nftContract.safeMint(msg.sender, task.nftId);
            nextNftId++;
        }

        emit TaskCompleted(msg.sender, taskId, task.rewardAmount, task.nftId, block.timestamp);
    }

    function deactivateTask(uint256 taskId) external onlyOwner {
        require(tasks[taskId].active, "Task not active");
        tasks[taskId].active = false;
        rewardPoolBalance += tasks[taskId].rewardAmount;
    }

    // Rulet bahisleri
    function placeRouletteBetToken(uint256 amount, uint8 number) external whenNotPaused {
        require(amount > 0, "Invalid amount");
        require(number <= 36, "Invalid number");
        require(rewardPoolBalance >= amount * 36, "Insufficient pool for payout");
        require(betToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        uint256 houseAmount = (amount * houseEdge) / 100;
        uint256 playerAmount = amount - houseAmount;

        betTokenBalance += playerAmount;
        houseBalance += houseAmount; // Kasa payı (SLM)

        bets[nextBetId] = RouletteBet({
            player: msg.sender,
            amount: amount,
            number: number,
            blockNumber: block.number + 1,
            resolved: false,
            betType: 0 // SLM veya betToken
        });

        emit RouletteBetPlaced(nextBetId, msg.sender, amount, number, 0, block.timestamp);
        nextBetId++;
    }

    function placeRouletteBetUSDT(uint256 amount, uint8 number) external whenNotPaused {
        require(amount > 0, "Invalid amount");
        require(number <= 36, "Invalid number");
        require(rewardPoolBalance >= (amount * 36) / 10**12, "Insufficient pool for payout"); // USDT: 6 decimals
        require(usdt.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        uint256 houseAmount = (amount * houseEdge) / 100;
        uint256 playerAmount = amount - houseAmount;

        usdtBalance += playerAmount;
        houseBalance += houseAmount / 10**12; // USDT’yi SLM’ye çevir (basit oran)

        bets[nextBetId] = RouletteBet({
            player: msg.sender,
            amount: amount,
            number: number,
            blockNumber: block.number + 1,
            resolved: false,
            betType: 2 // USDT
        });

        emit RouletteBetPlaced(nextBetId, msg.sender, amount, number, 2, block.timestamp);
        nextBetId++;
    }

    function placeRouletteBetBNB(uint8 number) external payable whenNotPaused {
        require(msg.value > 0, "Invalid amount");
        require(number <= 36, "Invalid number");
        require(rewardPoolBalance >= msg.value * 36, "Insufficient pool for payout");

        uint256 houseAmount = (msg.value * houseEdge) / 100;
        uint256 playerAmount = msg.value - houseAmount;

        bnbBalance += playerAmount;
        houseBalance += houseAmount; // BNB’yi SLM’ye çevir (basit oran)

        bets[nextBetId] = RouletteBet({
            player: msg.sender,
            amount: msg.value,
            number: number,
            blockNumber: block.number + 1,
            resolved: false,
            betType: 1 // BNB
        });

        emit RouletteBetPlaced(nextBetId, msg.sender, msg.value, number, 1, block.timestamp);
        nextBetId++;
    }

    function resolveRouletteBet(uint256 betId) external whenNotPaused {
        require(betId < nextBetId, "Invalid bet ID");
        RouletteBet storage bet = bets[betId];
        require(!bet.resolved, "Bet already resolved");
        require(block.number > bet.blockNumber, "Wait for next block");

        bet.resolved = true;
        uint256 seed = uint256(keccak256(abi.encodePacked(blockhash(bet.blockNumber), bet.player, betId)));
        uint8 result = uint8(seed % 37);

        uint256 winnings = 0;
        if (result == bet.number) {
            winnings = bet.amount * 36;
            if (bet.betType == 2) { // USDT: 6 decimals
                winnings = winnings / 10**12;
            }
            require(rewardPoolBalance >= winnings, "Insufficient pool balance");
            rewardPoolBalance -= winnings;
            require(token.transfer(bet.player, winnings), "Payout failed");
        }

        emit RouletteBetResolved(betId, bet.player, winnings, result, block.timestamp);
    }
}
