// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface IBEP20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract TokenPresale {
    address public owner;
    AggregatorV3Interface public priceFeed;
    address public defaultSaleToken; // Varsayılan satış tokenı (receive için)

    // Satışa sunulan tokenlar ve özellikleri
    struct SaleToken {
        bool isActive;
        uint256 tokenPrice; // Wei cinsinden fiyat (BNB)
        uint256 tokensPerUnit; // Birim başına token miktarı
    }
    mapping(address => SaleToken) public supportedSaleTokens;

    // Desteklenen stablecoin'ler
    mapping(address => bool) public supportedStablecoins;
    mapping(address => uint256) public stablecoinContributions;

    bool public saleEnded = false;
    bool public salePaused = false;

    uint256 public softCap = 1 ether;
    uint256 public hardCap = 5000 ether;
    uint256 public totalRaised = 0; // BNB cinsinden toplam toplanan miktar

    // Sabit stablecoin adresleri
    address public constant USDT_ADDRESS = 0x55d398326f99059fF775485246999027B3197955; // BSC USDT
    address public constant BUSD_ADDRESS = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56; // BSC BUSD
    address public constant USD1_ADDRESS = 0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d; // BSC USD1

    event TokensPurchased(address indexed buyer, address indexed currency, uint256 amount, address indexed saleToken, uint256 tokenAmount, uint256 timestamp);
    event SaleEnded();
    event SaleStarted();
    event SalePaused();
    event SalePlayed();
    event TokenPriceUpdated(address indexed saleToken, uint256 newPrice, uint256 timestamp);
    event StablecoinAdded(address indexed token);
    event StablecoinRemoved(address indexed token);
    event SaleTokenAdded(address indexed token, uint256 tokenPrice, uint256 tokensPerUnit);
    event SaleTokenRemoved(address indexed token);
    event TokensWithdrawn(address indexed token, uint256 amount, uint256 timestamp);
    event FundsWithdrawn(address indexed currency, uint256 amount, uint256 timestamp);
    event DefaultSaleTokenUpdated(address indexed newToken, uint256 timestamp);

    constructor(address _priceFeed, address[] memory _saleTokens, uint256[] memory _tokenPrices, uint256[] memory _tokensPerUnit) {
        require(_priceFeed != address(0), "Invalid price feed address");
        require(_saleTokens.length == _tokenPrices.length && _saleTokens.length == _tokensPerUnit.length, "Invalid input lengths");
        require(_saleTokens.length > 0, "At least one sale token required");
        owner = msg.sender;
        priceFeed = AggregatorV3Interface(_priceFeed);
        defaultSaleToken = _saleTokens[0]; // İlk token varsayılan olarak ayarlanır

        // Başlangıçta satış tokenlarını ekle
        for (uint256 i = 0; i < _saleTokens.length; i++) {
            require(_saleTokens[i] != address(0), "Invalid token address");
            require(_tokenPrices[i] > 0, "Invalid price");
            require(_tokensPerUnit[i] > 0, "Invalid tokens per unit");
            supportedSaleTokens[_saleTokens[i]] = SaleToken(true, _tokenPrices[i], _tokensPerUnit[i]);
            emit SaleTokenAdded(_saleTokens[i], _tokenPrices[i], _tokensPerUnit[i]);
        }

        // Stablecoin'leri ekle
        supportedStablecoins[USDT_ADDRESS] = true;
        supportedStablecoins[BUSD_ADDRESS] = true;
        supportedStablecoins[USD1_ADDRESS] = true;
        emit StablecoinAdded(USDT_ADDRESS);
        emit StablecoinAdded(BUSD_ADDRESS);
        emit StablecoinAdded(USD1_ADDRESS);

        emit DefaultSaleTokenUpdated(defaultSaleToken, block.timestamp);
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

    // Varsayılan satış tokenını güncelle
    function setDefaultSaleToken(address _token) external onlyOwner {
        require(supportedSaleTokens[_token].isActive, "Token not supported");
        defaultSaleToken = _token;
        emit DefaultSaleTokenUpdated(_token, block.timestamp);
    }

    // BNB/USD fiyatını al
    function getBNBPrice() public view returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price feed");
        return uint256(price); // 8 ondalık basamak
    }

    // Yeni satış tokenı ekle
    function addSaleToken(address _token, uint256 _price, uint256 _tokensPerUnit) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        require(_price > 0, "Invalid price");
        require(_tokensPerUnit > 0, "Invalid tokens per unit");
        require(!supportedSaleTokens[_token].isActive, "Token already added");
        supportedSaleTokens[_token] = SaleToken(true, _price, _tokensPerUnit);
        emit SaleTokenAdded(_token, _price, _tokensPerUnit);
    }

    // Satış tokenını kaldır
    function removeSaleToken(address _token) external onlyOwner {
        require(supportedSaleTokens[_token].isActive, "Token not supported");
        require(_token != defaultSaleToken, "Cannot remove default sale token");
        supportedSaleTokens[_token].isActive = false;
        emit SaleTokenRemoved(_token);
    }

    function setTokenPrice(address _token, uint256 _price) external onlyOwner {
        require(supportedSaleTokens[_token].isActive, "Token not supported");
        require(_price > 0, "Invalid price");
        supportedSaleTokens[_token].tokenPrice = _price;
        emit TokenPriceUpdated(_token, _price, block.timestamp);
    }

    function setTokenPriceInBNBDecimal(address _token, string memory _price) external onlyOwner {
        require(supportedSaleTokens[_token].isActive, "Token not supported");
        require(bytes(_price).length > 0, "Empty price string");
        (uint256 whole, uint256 decimal, uint8 decimalPlaces) = _parseDecimalString(_price);
        uint256 priceInWei = (whole * 10**18) + (decimal * 10**(18 - decimalPlaces));
        require(priceInWei > 0, "Price too low");
        supportedSaleTokens[_token].tokenPrice = priceInWei;
        emit TokenPriceUpdated(_token, priceInWei, block.timestamp);
    }

    function _parseDecimalString(string memory _price) private pure returns (uint256 whole, uint256 decimal, uint8 decimalPlaces) {
        bytes memory priceBytes = bytes(_price);
        bool foundDecimal = false;
        uint256 i;

        for (i = 0; i < priceBytes.length; i++) {
            if (priceBytes[i] == '.') {
                foundDecimal = true;
                break;
            }
            require(priceBytes[i] >= '0' && priceBytes[i] <= '9', "Invalid character");
            whole = whole * 10 + (uint8(priceBytes[i]) - uint8(bytes1('0')));
        }

        if (foundDecimal) {
            for (uint256 j = i + 1; j < priceBytes.length; j++) {
                require(priceBytes[j] >= '0' && priceBytes[j] <= '9', "Invalid character");
                decimal = decimal * 10 + (uint8(priceBytes[j]) - uint8(bytes1('0')));
                decimalPlaces++;
            }
            require(decimalPlaces <= 18, "Too many decimal places");
        } else {
            decimalPlaces = 0;
            decimal = 0;
        }
    }

    function setTokensPerUnit(address _token, uint256 _amount) external onlyOwner {
        require(supportedSaleTokens[_token].isActive, "Token not supported");
        require(_amount > 0, "Invalid amount");
        supportedSaleTokens[_token].tokensPerUnit = _amount;
    }

    function buyTokens(address _saleToken) public payable saleActive {
        require(supportedSaleTokens[_saleToken].isActive, "Token not supported");
        uint256 tokenPrice = supportedSaleTokens[_saleToken].tokenPrice;
        uint256 tokensPerUnit = supportedSaleTokens[_saleToken].tokensPerUnit;

        require(msg.value >= tokenPrice, "Not enough BNB sent");
        require(totalRaised + msg.value <= hardCap, "Hardcap reached");

        uint256 units = msg.value / tokenPrice;
        uint256 totalTokens = units * tokensPerUnit;

        (bool success1, bytes memory data1) = _saleToken.call(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        require(success1, "balanceOf failed");
        uint256 tokenBalance = abi.decode(data1, (uint256));
        require(tokenBalance >= totalTokens, "Not enough tokens");

        totalRaised += msg.value;

        (bool success2, ) = _saleToken.call(
            abi.encodeWithSignature("transfer(address,uint256)", msg.sender, totalTokens)
        );
        require(success2, "Token transfer failed");

        emit TokensPurchased(msg.sender, address(0), msg.value, _saleToken, totalTokens, block.timestamp);
    }

    function buyTokensWithStablecoin(address _stablecoin, uint256 _amount, address _saleToken) external saleActive {
        require(supportedStablecoins[_stablecoin], "Unsupported stablecoin");
        require(supportedSaleTokens[_saleToken].isActive, "Token not supported");
        require(_amount > 0, "Invalid amount");

        uint256 tokenPrice = supportedSaleTokens[_saleToken].tokenPrice;
        uint256 tokensPerUnit = supportedSaleTokens[_saleToken].tokensPerUnit;

        IBEP20 stablecoin = IBEP20(_stablecoin);
        require(stablecoin.allowance(msg.sender, address(this)) >= _amount, "Insufficient allowance");
        require(stablecoin.balanceOf(msg.sender) >= _amount, "Insufficient balance");

        uint256 usdAmount = _amount; // Stablecoin'ler 18 ondalık basamak, 1:1 USD
        uint256 bnbPrice = getBNBPrice(); // 8 ondalık basamak
        uint256 bnbAmount = (usdAmount * 10**8) / bnbPrice * 10**10;

        require(bnbAmount >= tokenPrice, "Not enough stablecoin sent");
        require(totalRaised + bnbAmount <= hardCap, "Hardcap reached");

        uint256 units = bnbAmount / tokenPrice;
        uint256 totalTokens = units * tokensPerUnit;

        (bool success1, bytes memory data1) = _saleToken.call(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        require(success1, "balanceOf failed");
        uint256 tokenBalance = abi.decode(data1, (uint256));
        require(tokenBalance >= totalTokens, "Not enough tokens");

        require(stablecoin.transferFrom(msg.sender, address(this), _amount), "Stablecoin transfer failed");

        (bool success2, ) = _saleToken.call(
            abi.encodeWithSignature("transfer(address,uint256)", msg.sender, totalTokens)
        );
        require(success2, "Token transfer failed");

        totalRaised += bnbAmount;
        stablecoinContributions[_stablecoin] += _amount;

        emit TokensPurchased(msg.sender, _stablecoin, _amount, _saleToken, totalTokens, block.timestamp);
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

    // Tüm satılmamış tokenları çek
    function withdrawUnsoldTokens(address _saleToken) external onlyOwner {
        require(supportedSaleTokens[_saleToken].isActive, "Token not supported");

        (bool success1, bytes memory data1) = _saleToken.call(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        require(success1, "balanceOf failed");
        uint256 tokenBalance = abi.decode(data1, (uint256));
        require(tokenBalance > 0, "No tokens to withdraw");

        (bool success2, ) = _saleToken.call(
            abi.encodeWithSignature("transfer(address,uint256)", owner, tokenBalance)
        );
        require(success2, "Transfer failed");

        emit TokensWithdrawn(_saleToken, tokenBalance, block.timestamp);
    }

    // Belirli miktarda satılmamış tokenları çek
    function withdrawPartialUnsoldTokens(address _saleToken, uint256 _amount) external onlyOwner {
        require(supportedSaleTokens[_saleToken].isActive, "Token not supported");
        require(_amount > 0, "Invalid amount");

        (bool success1, bytes memory data1) = _saleToken.call(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        require(success1, "balanceOf failed");
        uint256 tokenBalance = abi.decode(data1, (uint256));
        require(tokenBalance >= _amount, "Not enough tokens");

        (bool success2, ) = _saleToken.call(
            abi.encodeWithSignature("transfer(address,uint256)", owner, _amount)
        );
        require(success2, "Transfer failed");

        emit TokensWithdrawn(_saleToken, _amount, block.timestamp);
    }

    // BNB çek
    function withdrawBNB() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No BNB to withdraw");
        payable(owner).transfer(balance);
        emit FundsWithdrawn(address(0), balance, block.timestamp);
    }

    // USDT çek
    function withdrawUSDT() external onlyOwner {
        IBEP20 usdt = IBEP20(USDT_ADDRESS);
        uint256 balance = usdt.balanceOf(address(this));
        require(balance > 0, "No USDT to withdraw");
        require(usdt.transfer(owner, balance), "USDT transfer failed");
        emit FundsWithdrawn(USDT_ADDRESS, balance, block.timestamp);
    }

    // BUSD çek
    function withdrawBUSD() external onlyOwner {
        IBEP20 busd = IBEP20(BUSD_ADDRESS);
        uint256 balance = busd.balanceOf(address(this));
        require(balance > 0, "No BUSD to withdraw");
        require(busd.transfer(owner, balance), "BUSD transfer failed");
        emit FundsWithdrawn(BUSD_ADDRESS, balance, block.timestamp);
    }

    // USD1 çek
    function withdrawUSD1() external onlyOwner {
        IBEP20 usd1 = IBEP20(USD1_ADDRESS);
        uint256 balance = usd1.balanceOf(address(this));
        require(balance > 0, "No USD1 to withdraw");
        require(usd1.transfer(owner, balance), "USD1 transfer failed");
        emit FundsWithdrawn(USD1_ADDRESS, balance, block.timestamp);
    }

    function addStablecoin(address _stablecoin) external onlyOwner {
        require(_stablecoin != address(0), "Invalid stablecoin address");
        require(!supportedStablecoins[_stablecoin], "Stablecoin already supported");
        supportedStablecoins[_stablecoin] = true;
        emit StablecoinAdded(_stablecoin);
    }

    function removeStablecoin(address _stablecoin) external onlyOwner {
        require(supportedStablecoins[_stablecoin], "Stablecoin not supported");
        supportedStablecoins[_stablecoin] = false;
        emit StablecoinRemoved(_stablecoin);
    }

    function getTotalBNB() public view returns (uint256) {
        return address(this).balance;
    }

    function getRemainingTokens(address _saleToken) public view returns (uint256) {
        require(supportedSaleTokens[_saleToken].isActive, "Token not supported");
        (bool success, bytes memory data) = _saleToken.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
        require(success, "balanceOf failed");
        return abi.decode(data, (uint256));
    }

    function withdrawForeignTokens(address _token) external onlyOwner {
        require(!supportedSaleTokens[_token].isActive, "Cannot withdraw sale token");
        require(!supportedStablecoins[_token], "Cannot withdraw supported stablecoin");
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
        emit TokensWithdrawn(_token, tokenBalance, block.timestamp);
    }

    receive() external payable {
        require(defaultSaleToken != address(0), "No default sale token set");
        buyTokens(defaultSaleToken);
    }
}
