// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ISoliumcoin {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract Staking {
    ISoliumcoin public token;
    address public admin;
    address public treasury;

    uint256 public constant MIN_LOCK_PERIOD = 7 days;
    uint256 public constant MAX_LOCK_PERIOD = 2 * 365 days;
    uint256 public rewardRate = 3000; // %30 APY (10000 = %100)
    uint256 public constant MIN_REWARD_RATE = 100; // %1
    uint256 public constant MAX_REWARD_RATE = 10000; // %100
    bool public stakingTerminated;

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 lockPeriod;
        uint256 rewardRate; // Stake’in oluşturulduğu andaki ödül oranı
    }

    mapping(address => Stake[]) public stakes;
    uint256 public bnbBalance;
    uint256 public totalStaked;

    event Staked(address indexed user, uint256 amount, uint256 lockPeriod, uint256 rewardRate, uint256 timestamp);
    event Unstaked(address indexed user, uint256 amount, uint256 reward, uint256 timestamp);
    event TreasuryUpdated(address indexed newTreasury, uint256 timestamp);
    event BNBDeposited(address indexed depositor, uint256 amount, uint256 timestamp);
    event BNBWithdrawn(address indexed recipient, uint256 amount, uint256 timestamp);
    event TokensDeposited(address indexed depositor, uint256 amount, uint256 timestamp);
    event TokensWithdrawn(address indexed recipient, uint256 amount, uint256 timestamp);
    event StakingTerminated(uint256 timestamp);
    event RewardRateUpdated(uint256 newRewardRate, uint256 timestamp);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    modifier whenNotTerminated() {
        require(!stakingTerminated, "Staking terminated");
        _;
    }

    constructor(address _token, address _treasury) {
        require(_token != address(0), "Invalid token address");
        require(_treasury != address(0), "Invalid treasury address");
        token = ISoliumcoin(_token);
        admin = msg.sender;
        treasury = _treasury;
    }

    // Hazine adresini güncelle
    function setTreasury(address _treasury) external onlyAdmin {
        require(_treasury != address(0), "Invalid treasury address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury, block.timestamp);
    }

    // Ödül oranını güncelle
    function setRewardRate(uint256 newRewardRate) external onlyAdmin {
        require(newRewardRate >= MIN_REWARD_RATE && newRewardRate <= MAX_REWARD_RATE, "Invalid reward rate");
        rewardRate = newRewardRate;
        emit RewardRateUpdated(newRewardRate, block.timestamp);
    }

    // BNB yatır (gas için)
    function depositBNB() external payable {
        require(msg.value > 0, "No BNB sent");
        bnbBalance += msg.value;
        emit BNBDeposited(msg.sender, msg.value, block.timestamp);
    }

    // BNB çek
    function withdrawBNB(address payable recipient, uint256 amount) external onlyAdmin {
        require(amount <= bnbBalance, "Insufficient BNB balance");
        bnbBalance -= amount;
        recipient.transfer(amount);
        emit BNBWithdrawn(recipient, amount, block.timestamp);
    }

    // Token ekle
    function depositTokens(uint256 amount) external onlyAdmin whenNotTerminated {
        require(amount > 0, "Invalid amount");
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        emit TokensDeposited(msg.sender, amount, block.timestamp);
    }

    // Token çek
    function withdrawTokens(address recipient, uint256 amount) external onlyAdmin {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        uint256 availableBalance = token.balanceOf(address(this)) - totalStaked;
        require(amount <= availableBalance, "Insufficient available tokens");
        require(token.transfer(recipient, amount), "Transfer failed");
        emit TokensWithdrawn(recipient, amount, block.timestamp);
    }

    // Staking yap
    function stake(uint256 amount, uint256 lockPeriod) external whenNotTerminated {
        require(amount > 0, "Invalid amount");
        require(lockPeriod >= MIN_LOCK_PERIOD && lockPeriod <= MAX_LOCK_PERIOD, "Invalid lock period");
        require(token.balanceOf(msg.sender) >= amount, "Not enough balance");
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        stakes[msg.sender].push(Stake({
            amount: amount,
            startTime: block.timestamp,
            lockPeriod: lockPeriod,
            rewardRate: rewardRate // Mevcut ödül oranı kaydedilir
        }));
        totalStaked += amount;

        emit Staked(msg.sender, amount, lockPeriod, rewardRate, block.timestamp);
    }

    // Unstake yap
    function unstake(uint256 stakeIndex) external {
        require(stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        Stake storage userStake = stakes[msg.sender][stakeIndex];
        require(block.timestamp >= userStake.startTime + userStake.lockPeriod, "Lock period not ended");

        uint256 amount = userStake.amount;
        uint256 reward = calculateReward(amount, userStake.startTime, userStake.lockPeriod, userStake.rewardRate);

        stakes[msg.sender][stakeIndex] = stakes[msg.sender][stakes[msg.sender].length - 1];
        stakes[msg.sender].pop();
        totalStaked -= amount;

        require(token.transfer(msg.sender, amount), "Token transfer failed");
        require(token.transferFrom(treasury, msg.sender, reward), "Reward transfer failed");

        emit Unstaked(msg.sender, amount, reward, block.timestamp);
    }

    // Erken unstake
    function earlyUnstake(uint256 stakeIndex) external {
        require(stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        Stake storage userStake = stakes[msg.sender][stakeIndex];

        uint256 amount = userStake.amount;

        stakes[msg.sender][stakeIndex] = stakes[msg.sender][stakes[msg.sender].length - 1];
        stakes[msg.sender].pop();
        totalStaked -= amount;

        require(token.transfer(msg.sender, amount), "Token transfer failed");

        emit Unstaked(msg.sender, amount, 0, block.timestamp);
    }

    // Staking sonlandır
    function terminateStaking() external onlyAdmin {
        require(!stakingTerminated, "Staking already terminated");
        stakingTerminated = true;

        uint256 availableBalance = token.balanceOf(address(this)) - totalStaked;
        if (availableBalance > 0) {
            require(token.transfer(treasury, availableBalance), "Transfer failed");
            emit TokensWithdrawn(treasury, availableBalance, block.timestamp);
        }

        emit StakingTerminated(block.timestamp);
    }

    // Ödülü hesapla
    function calculateReward(uint256 amount, uint256 startTime, uint256 lockPeriod, uint256 rewardRate) public view returns (uint256) {
        uint256 duration = block.timestamp - startTime;
        if (duration > lockPeriod) {
            duration = lockPeriod;
        }
        return (amount * rewardRate * duration) / (365 days * 10000);
    }

    // Kullanıcının stake'lerini ve ödüllerini görüntüle
    function getStakes(address user) external view returns (Stake[] memory, uint256[] memory) {
        uint256[] memory rewards = new uint256[](stakes[user].length);
        for (uint256 i = 0; i < stakes[user].length; i++) {
            rewards[i] = calculateReward(
                stakes[user][i].amount,
                stakes[user][i].startTime,
                stakes[user][i].lockPeriod,
                stakes[user][i].rewardRate
            );
        }
        return (stakes[user], rewards);
    }

    // Kalan kilit süresini görüntüle
    function getRemainingLockTime(address user, uint256 stakeIndex) external view returns (uint256) {
        require(stakeIndex < stakes[user].length, "Invalid stake index");
        Stake storage userStake = stakes[user][stakeIndex];
        if (block.timestamp >= userStake.startTime + userStake.lockPeriod) {
            return 0;
        }
        return (userStake.startTime + userStake.lockPeriod) - block.timestamp;
    }
}
