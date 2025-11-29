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

    uint256 public maxTransactionAmount; // 单笔交易最大额度
    uint256 public dailyTransactionLimit; // 每日交易次数限制
    mapping (address => bool) public isExcludedFromLimits; // 免交易限制地址列表
    mapping(address => uint256) public dailyTransactionCount; // 记录每日交易次数

    // liu
    IUniswapV2Router02 public immutable uniswapV2Router;
    address public uniswapV2Pair;
    mapping(address => bool) public isWhitelistedPair;
    address public liquidityWallet; //流动性钱包


    constructor(string memory name, string memory symbol, uint256 initialSupply,  address uniswapRouter) ERC20(name, symbol) Ownable(msg.sender) {
        buyTax = 5; // 初始税率5%
        sellTax = 10; // 初始税率10%
        transferTax = 2; // 初始税率2%
        taxRecipient = owner(); // 初始税费接收地址为合约拥有者
        maxTransactionAmount = 1000 * (10 ** decimals()); // 初始单笔交易最大额度1000代币
        dailyTransactionLimit = 10; // 初始每日交易次数限制10次

        uniswapV2Router = IUniswapV2Router02(uniswapRouter);
        
        // 创建交易对
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
            isWhitelistedPair[uniswapV2Pair] = true;
        
        _mint(msg.sender, initialSupply);
    }

    // 重写 transfer 函数以实现交易税和交易限制功能
    function transfer(address to, uint256 value) public override virtual returns (bool) {
        require(value <= maxTransactionAmount, "Exceeds max transaction amount");
        require(to != address(0), "Invalid recipient address");
        // 计算税费
        uint256 tax = _calculateSellTax(_msgSender(), to, value);
        uint256 amountAfterTax = value - tax;
        // 转账
        _transfer(_msgSender(), to, amountAfterTax);
        
        // 处理税费
        _handleTax(tax);
        return true;
    }

    // 计算税费
    function _calculateSellTax(address from, address to, uint256 amount) internal view returns (uint256) {
        // 判断是买入、卖出还是普通转账，并应用相应的税率
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
        }

        // 转账给税费接收地址
        if (recipientAmount > 0) {
            _transfer(address(this), taxRecipient, recipientAmount);
        }
    }

    // 设置新的税费
    function setTaxRate(uint256 newBuyRate, uint256 newSellRate, uint256 newTransferRate) external onlyOwner {
        require(newBuyRate <= 15, "Tax rate too high");
        require(newSellRate <= 25, "Tax rate too high");
        require(newTransferRate <= 10, "Tax rate too high");
        buyTax = newBuyRate;
        sellTax = newSellRate;
        transferTax = newTransferRate;
    }


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

    // function lockLiquidity(uint256 daysToLock) external onlyOwner {
    //     require(daysToLock <= 365, "Lock period too long");
    //     liquidityLock = block.timestamp + daysToLock * 1 days;
    // }

    // DEX 交易对验证修饰符
    modifier validateDexPair(address pair) {
        require(isWhitelistedPair[pair], "Invalid DEX pair");
        _;
    }
    
    // 安全交换函数
    function _safeSwap(
        address pair,
        uint256 amountOutMin,
        address[] memory path
    ) internal validateDexPair(pair) {
        uint256[] memory amounts = uniswapV2Router.getAmountsOut(msg.value, path);
        require(amounts[1] >= amountOutMin, "Insufficient output");
        
        (bool success,) = pair.call{value: msg.value}(
            abi.encodeWithSignature(
                "swap(uint256,uint256,address,bytes)",
                amounts[0],
                amounts[1],
                msg.sender,
                new bytes(0)
            )
        );
        require(success, "Swap failed");
    }
}