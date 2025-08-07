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
    address public treasury; // Ödüller için hazine adresi

    uint256 public constant MIN_LOCK_PERIOD = 7 days; // Minimum kilit süresi
    uint256 public constant MAX_LOCK_PERIOD = 2 * 365 days; // Maksimum kilit süresi
    uint256 public constant BASE_REWARD_RATE = 100; // %1 için baz oran (100 = %1)
    uint256 public constant MAX_REWARD_RATE = 2000; // Maksimum %20 yıllık ödül

    struct Stake {
        uint256 amount; // Stake edilen miktar
        uint256 startTime; // Başlangıç zamanı
        uint256 lockPeriod; // Kilit süresi (saniye)
        uint256 rewardRate; // Yıllık ödül oranı (%)
    }

    mapping(address => Stake[]) public stakes;
    uint256 public bnbBalance; // Sözleşmedeki BNB havuzu (gas için)

    event Staked(address indexed user, uint256 amount, uint256 lockPeriod, uint256 rewardRate, uint256 timestamp);
    event Unstaked(address indexed user, uint256 amount, uint256 reward, uint256 timestamp);
    event TreasuryUpdated(address indexed newTreasury, uint256 timestamp);
    event BNBDeposited(address indexed depositor, uint256 amount, uint256 timestamp);
    event BNBWithdrawn(address indexed recipient, uint256 amount, uint256 timestamp);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
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

    // BNB yatır (gas için)
    function depositBNB() external payable {
        require(msg.value > 0, "No BNB sent");
        bnbBalance += msg.value;
        emit BNBDeposited(msg.sender, msg.value, block.timestamp);
    }

    // BNB çek (sadece admin)
    function withdrawBNB(address payable recipient, uint256 amount) external onlyAdmin {
        require(amount <= bnbBalance, "Insufficient BNB balance");
        bnbBalance -= amount;
        recipient.transfer(amount);
        emit BNBWithdrawn(recipient, amount, block.timestamp);
    }

    // Staking yap
    function stake(uint256 amount, uint256 lockPeriod) external {
        require(amount > 0, "Invalid amount");
        require(lockPeriod >= MIN_LOCK_PERIOD && lockPeriod <= MAX_LOCK_PERIOD, "Invalid lock period");
        require(token.balanceOf(msg.sender) >= amount, "Not enough balance");
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        // Ödül oranı: Her 30 gün için %1, maksimum %20
        uint256 rewardRate = (lockPeriod / 30 days) * BASE_REWARD_RATE;
        if (rewardRate > MAX_REWARD_RATE) {
            rewardRate = MAX_REWARD_RATE;
        }

        stakes[msg.sender].push(Stake({
            amount: amount,
            startTime: block.timestamp,
            lockPeriod: lockPeriod,
            rewardRate: rewardRate
        }));

        emit Staked(msg.sender, amount, lockPeriod, rewardRate, block.timestamp);
    }

    // Unstake yap (kilit süresi dolduysa)
    function unstake(uint256 stakeIndex) external {
        require(stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        Stake storage userStake = stakes[msg.sender][stakeIndex];
        require(block.timestamp >= userStake.startTime + userStake.lockPeriod, "Lock period not ended");

        uint256 amount = userStake.amount;
        uint256 reward = calculateReward(amount, userStake.startTime, userStake.lockPeriod, userStake.rewardRate);

        // Stake'i sil
        stakes[msg.sender][stakeIndex] = stakes[msg.sender][stakes[msg.sender].length - 1];
        stakes[msg.sender].pop();

        // Ana token ve ödülü gönder
        require(token.transfer(msg.sender, amount), "Token transfer failed");
        require(token.transferFrom(treasury, msg.sender, reward), "Reward transfer failed");

        emit Unstaked(msg.sender, amount, reward, block.timestamp);
    }

    // Erken unstake (ödül yok, ceza yok)
    function earlyUnstake(uint256 stakeIndex) external {
        require(stakeIndex < stakes[msg.sender].length, "Invalid stake index");
        Stake storage userStake = stakes[msg.sender][stakeIndex];

        uint256 amount = userStake.amount;

        // Stake'i sil
        stakes[msg.sender][stakeIndex] = stakes[msg.sender][stakes[msg.sender].length - 1];
        stakes[msg.sender].pop();

        // Sadece ana token gönderilir, ödül yok
        require(token.transfer(msg.sender, amount), "Token transfer failed");

        emit Unstaked(msg.sender, amount, 0, block.timestamp);
    }

    // Ödülü hesapla
    function calculateReward(uint256 amount, uint256 startTime, uint256 lockPeriod, uint256 rewardRate) public view returns (uint256) {
        uint256 duration = block.timestamp - startTime;
        if (duration > lockPeriod) {
            duration = lockPeriod;
        }
        return (amount * rewardRate * duration) / (365 days * 10000); // Yıllık % oran, 10000 = %100
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
}
