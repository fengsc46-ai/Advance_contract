// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}
// Uniswap V2 Router接口（简化版）
interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
}

/**
 * Meme 代币合约  SHIB风格。合约需包含以下功能：
 * 实现代币税机制、流动性池集成和交易限制功能
*/
contract MeMeToken is ERC20, Ownable {

    // 税费相关变量
    uint256 public buyTax; // 买入税百分比
    uint256 public sellTax; // 卖出税百分比
    uint256 public transferTax; // 转账税百分比
    address public taxRecipient;   // 税费钱包
    mapping (address => bool) public isExcludedFromTax; // 免税地址列表

    // 税费的处理
    uint256 public burnedTax = 30; // 税费中用于销毁的百分比
    uint256 public liquidityTax = 70; // 税费中用于流动性池的百分比
    uint256 public recipientTax = 0; // 税费中用于接收地址的百分比

    // 交易限制参数
    uint256 public maxTransactionAmount = 1000000 * 10**18; // 单笔最大交易量
    uint256 public maxWalletBalance = 5000000 * 10**18; // 单个钱包最大持币量
    uint256 public cooldownPeriod = 300; // 交易冷却时间（秒）
    mapping(address => uint256) private _lastTransactionTime; // 记录上次交易时间
    mapping (address => bool) public isExcludedFromLimits; // 免交易限制地址列表

    // 流动性池相关变量
    IUniswapV2Router02 public immutable uniswapV2Router;
    address public uniswapV2Pair;
    mapping(address => bool) public isWhitelistedPair;
    address public liquidityWallet; //流动性钱包

    event TaxDistribution(uint256 marketingAmount, uint256 liquidityAmount, uint256 taxWalletAmount);// 税费处理事件
    event LiquidityAdded(uint256 tokenAmount, uint256 ethAmount);// 添加流动性事件
    event TaxUpdated(uint256 buyTax, uint256 sellTax, uint256 transferTax);// 税率更新事件
    event TransactionLimitsUpdated(uint256 maxTransactionAmount, uint256 maxWalletBalance, uint256 cooldownPeriod);// 交易限制更新事件

    constructor(string memory name, string memory symbol, uint256 initialSupply,  address uniswapRouter) ERC20(name, symbol) Ownable(msg.sender) {
        buyTax = 5; // 初始税率5%
        sellTax = 10; // 初始税率10%
        transferTax = 2; // 初始税率2%
        taxRecipient = msg.sender; // 初始税费接收地址为合约拥有者
        liquidityWallet = msg.sender; // 初始流动性钱包为合约拥有者
        
        uniswapV2Router = IUniswapV2Router02(uniswapRouter); 
        // 创建交易对
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
            isWhitelistedPair[uniswapV2Pair] = true;
        
        _mint(msg.sender, initialSupply);
    }

    /** * 税费和交易限制相关函数===================================================================== */

    // 检查交易限制
    function _checkTransferLimits(address from, address to, uint256 amount) internal view {
        require(amount > 0, "Transfer amount must be greater than zero");
        require(from != address(0), "Transfer from the zero address:");
        require(to != address(0), "Transfer to the zero address");
       
       // 检查交易冷却时间
        require(
            block.timestamp >= _lastTransactionTime[from]+cooldownPeriod,
            "Cooldown period not elapsed"
        );

        // 最大交易量限制
        if (from == uniswapV2Pair || to == uniswapV2Pair) {
            require(amount <= maxTransactionAmount, "Exceeds max transaction amount");
        }
        
        // 最大持币量限制
        if (to != uniswapV2Pair && to != address(uniswapV2Router)) {
            require(balanceOf(to) + amount <= maxWalletBalance, "Exceeds max wallet amount");
        }
    }
    
    // 重写 transfer 函数以实现交易税和交易限制功能
    function transfer(address to, uint256 value) public override virtual returns (bool) {
         // 应用交易限制
        if (!isExcludedFromLimits[_msgSender()] && !isExcludedFromLimits[to]) {
            _checkTransferLimits(_msgSender(), to, value);
        }
         _lastTransactionTime[_msgSender()] = block.timestamp;
        require(to != address(0), "Invalid recipient address");
        // 如果在免税地址中，或者合约本身调用，则不进行税费计算直接转账
        if (isExcludedFromTax[_msgSender()] || isExcludedFromTax[to] || _msgSender() == address(this)) {
            return super.transfer(to, value);
        }
        // 计算税费
        uint256 tax = _calculateSellTax(_msgSender(), to, value);
        uint256 amountAfterTax = value - tax;
        // 转账
        super.transfer(to, amountAfterTax);
        super.transfer(address(this), tax);
        // 处理税费
        _handleTax(tax);
        return true;
    }

    // 重写 transferFrom 函数以实现交易税和交易限制功能
    function transferFrom(address from, address to, uint256 value) public override virtual returns (bool) {
         // 应用交易限制
        if (!isExcludedFromLimits[from] && !isExcludedFromLimits[to]) {
            _checkTransferLimits(from, to, value);
        }
         _lastTransactionTime[from] = block.timestamp;
        // 如果在免税地址中，或者合约本身调用，则不进行税费计算直接转账
        if (isExcludedFromTax[_msgSender()] || isExcludedFromTax[to] || _msgSender() == address(this)) {
            return super.transferFrom(from, to, value);
        }
        require(to != address(0), "Invalid recipient address");
        // 计算税费
        uint256 tax = _calculateSellTax(from, to, value);
        uint256 amountAfterTax = value - tax;
        // 转账
        super.transferFrom(from, to, amountAfterTax);

        // 处理税费
        _handleTax(tax);
        return true;
    }

  /** * 税费相关函数===================================================================== */
    // 计算税费
    function _calculateSellTax(address from, address to, uint256 amount) internal view returns (uint256) {
        // 判断是流动性买入、卖出还是普通转账，并应用相应的税率
        if (to == uniswapV2Pair) {
            return (amount * sellTax) / 100;
        } else  if (from == uniswapV2Pair) {
            return (amount * buyTax) / 100;
        } else {
            return (amount * transferTax) / 100;
        }
    }

    // 处理税费
    function _handleTax(uint256 taxAmount) internal {
        uint256 burnAmount = (taxAmount * burnedTax) / 100;
        uint256 liquidityAmount = (taxAmount * liquidityTax) / 100;
        uint256 recipientAmount = taxAmount - burnAmount - liquidityAmount;

        // 销毁代币
        if (burnAmount > 0) {
            _burn(address(this), burnAmount);
        }

        // 添加流动性
        if (liquidityAmount > 0) {
            // 这里可以添加流动性到Uniswap的逻辑
            _transfer(address(this), liquidityWallet, liquidityAmount);
        }

        // 转账给税费接收地址
        if (recipientAmount > 0) {
            _transfer(address(this), taxRecipient, recipientAmount);
        }
        emit TaxDistribution(recipientAmount, liquidityAmount, burnAmount);
    }


  /**添加流动性相关函数=====================================================================*/
    // 添加流动性
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) internal  {
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            msg.sender,
            block.timestamp
        );
    }

    // todo 移除流动性 


    // 紧急暂停交易
    function emergencyPause() external onlyOwner {
        maxTransactionAmount = 0;
        cooldownPeriod = type(uint256).max;
    }

    // 恢复交易
    function emergencyUnpause(uint256 maxTx, uint256 cooldown) external onlyOwner {
        maxTransactionAmount = maxTx;
        cooldownPeriod = cooldown;
    }

    /*** 管理员操作相关函数===================================================================== */
    // 更新税费接收地址
    function setTaxRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid address");
        taxRecipient = newRecipient;
    }

    // 设置新的税费
    function setTaxRate(uint256 newBuyRate, uint256 newSellRate, uint256 newTransferRate) external onlyOwner {
        require(newBuyRate + newSellRate + newTransferRate <= 30, "Shares must sum to 100");
        buyTax = newBuyRate;
        sellTax = newSellRate;
        transferTax = newTransferRate;
        emit TaxUpdated(buyTax, sellTax, transferTax);
    }

    // 添加/删除免交易限制地址
    function excludeFromLimits(address account, bool excluded) external onlyOwner {
        isExcludedFromLimits[account] = excluded;
    }

    // 添加/删除免税地址
    function excludeFromTax(address account, bool excluded) external onlyOwner {
        isExcludedFromTax[account] = excluded;
    }

    // 交易限制参数设置
    function setTransactionLimits(uint256 maxTxAmount, uint256 maxWalletAmt, uint256 cooldownSec) external onlyOwner {
        // 参数合法性校验
        require(maxTxAmount > 0, "Invalid max transaction amount");
        require(maxWalletAmt > 0, "Invalid max wallet amount");
        require(cooldownSec > 0, "Invalid cooldown period");

        maxTransactionAmount = maxTxAmount;
        maxWalletBalance = maxWalletAmt;
        cooldownPeriod = cooldownSec;
        emit TransactionLimitsUpdated(maxTransactionAmount, maxWalletBalance, cooldownPeriod);
    }

}