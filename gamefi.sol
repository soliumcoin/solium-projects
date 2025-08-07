// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ISoliumcoin {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function paused() external view returns (bool);
    function burn(uint256 amount) external;
}

interface IERC721 {
    function safeMint(address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract SoliumGameFi {
    ISoliumcoin public token;
    IERC721 public nftContract;
    address public owner;
    address public treasury;
    uint256 public rewardPoolBalance; // Ödül havuzu bakiyesi

    bool public gameActive = true;
    uint256 public nextTaskId = 1;
    uint256 public nextNftId = 1;
    uint256 public burnPercentage = 10; // Ödüllerin %10’u yakılır

    struct Task {
        uint256 rewardAmount; // SLM ödülü
        uint256 nftId; // NFT ödülü (0 = yok)
        bool active; // Görev aktif mi
    }

    mapping(uint256 => Task) public tasks;
    mapping(address => mapping(uint256 => bool)) public completedTasks;

    event TaskCreated(uint256 indexed taskId, uint256 rewardAmount, uint256 nftId, uint256 timestamp);
    event TaskCompleted(address indexed player, uint256 indexed taskId, uint256 rewardAmount, uint256 nftId, uint256 timestamp);
    event GamePaused(uint256 timestamp);
    event GameUnpaused(uint256 timestamp);
    event BurnPercentageUpdated(uint256 newPercentage, uint256 timestamp);
    event TokenContractUpdated(address indexed newToken, uint256 timestamp);
    event RewardTokensDeposited(address indexed depositor, uint256 amount, uint256 timestamp);
    event RewardTokensWithdrawn(address indexed recipient, uint256 amount, uint256 timestamp);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier whenNotPaused() {
        require(!token.paused(), "Soliumcoin is paused");
        require(gameActive, "Game is paused");
        _;
    }

    constructor(address _token, address _treasury, address _nftContract) {
        require(_token != address(0), "Invalid token address");
        require(_treasury != address(0), "Invalid treasury address");
        token = ISoliumcoin(_token);
        treasury = _treasury;
        nftContract = IERC721(_nftContract);
        owner = msg.sender;
    }

    // Token sözleşmesini güncelle
    function setTokenContract(address newToken) external onlyOwner {
        require(newToken != address(0), "Invalid token address");
        token = ISoliumcoin(newToken);
        emit TokenContractUpdated(newToken, block.timestamp);
    }

    // Ödül havuzuna token yatır
    function depositRewardTokens(uint256 amount) external onlyOwner whenNotPaused {
        require(amount > 0, "Invalid amount");
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        rewardPoolBalance += amount;
        emit RewardTokensDeposited(msg.sender, amount, block.timestamp);
    }

    // Ödül havuzundan token çek
    function withdrawRewardTokens(address recipient, uint256 amount) external onlyOwner whenNotPaused {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        require(amount <= rewardPoolBalance, "Insufficient reward pool balance");
        rewardPoolBalance -= amount;
        require(token.transfer(recipient, amount), "Transfer failed");
        emit RewardTokensWithdrawn(recipient, amount, block.timestamp);
    }

    // Oyunu duraklat
    function pauseGame() external onlyOwner {
        require(gameActive, "Game already paused");
        gameActive = false;
        emit GamePaused(block.timestamp);
    }

    // Oyunu aktif et
    function unpauseGame() external onlyOwner {
        require(!gameActive, "Game not paused");
        gameActive = true;
        emit GameUnpaused(block.timestamp);
    }

    // Yakma yüzdesini güncelle
    function setBurnPercentage(uint256 newPercentage) external onlyOwner {
        require(newPercentage <= 100, "Invalid percentage");
        burnPercentage = newPercentage;
        emit BurnPercentageUpdated(newPercentage, block.timestamp);
    }

    // Yeni görev oluştur
    function createTask(uint256 rewardAmount, uint256 nftId) external onlyOwner {
        require(rewardAmount <= rewardPoolBalance, "Insufficient reward pool balance");
        tasks[nextTaskId] = Task({
            rewardAmount: rewardAmount,
            nftId: nftId,
            active: true
        });
        rewardPoolBalance -= rewardAmount; // Ödül rezerve edilir
        emit TaskCreated(nextTaskId, rewardAmount, nftId, block.timestamp);
        nextTaskId++;
    }

    // Görevi tamamla ve ödül al
    function completeTask(uint256 taskId) external whenNotPaused {
        require(tasks[taskId].active, "Task not active");
        require(!completedTasks[msg.sender][taskId], "Task already completed");

        Task storage task = tasks[taskId];
        completedTasks[msg.sender][taskId] = true;

        // SLM ödülü
        if (task.rewardAmount > 0) {
            uint256 burnAmount = (task.rewardAmount * burnPercentage) / 100;
            uint256 playerAmount = task.rewardAmount - burnAmount;

            // Yakma
            if (burnAmount > 0) {
                token.burn(burnAmount);
            }

            // Oyuncuya transfer
            require(token.transfer(msg.sender, playerAmount), "Reward transfer failed");
        }

        // NFT ödülü
        if (task.nftId > 0) {
            require(nftContract.ownerOf(task.nftId) == address(0), "NFT already minted");
            nftContract.safeMint(msg.sender, task.nftId);
            nextNftId++;
        }

        emit TaskCompleted(msg.sender, taskId, task.rewardAmount, task.nftId, block.timestamp);
    }

    // Görevi devre dışı bırak
    function deactivateTask(uint256 taskId) external onlyOwner {
        require(tasks[taskId].active, "Task not active");
        tasks[taskId].active = false;
        rewardPoolBalance += tasks[taskId].rewardAmount; // Rezerve edilen ödül geri alınır
    }
}
