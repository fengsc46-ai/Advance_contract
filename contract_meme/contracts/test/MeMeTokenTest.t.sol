// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {MeMeToken} from "../MeMeToken.sol";
import "hardhat/console.sol"; 

// 模拟 Uniswap V2 Factory
contract MockUniswapV2Factory {
    mapping(address => mapping(address => address)) public pairs;
    
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        pair = address(uint160(uint256(keccak256(abi.encodePacked(tokenA, tokenB, block.timestamp)))));
        pairs[tokenA][tokenB] = pair;
        pairs[tokenB][tokenA] = pair;
        return pair;
    }
    
    function getPair(address tokenA, address tokenB) external view returns (address pair) {
        return pairs[tokenA][tokenB];
    }
}

// 模拟 Uniswap V2 Router
contract MockUniswapV2Router02 {
    address public immutable factory;
    address public immutable WETH;
    
    constructor(address _factory) {
        factory = _factory;
        WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    }
    
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity) {
        return (amountTokenDesired, msg.value, 1);
    }
}

contract MeMeTokenTransferTest is Test {
    MeMeToken public memeToken;
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    address public uniswapV2Pair;
    
    MockUniswapV2Factory public mockFactory;
    MockUniswapV2Router02 public mockRouter;
    
    string constant NAME = "TestToken";
    string constant SYMBOL = "TEST";
    uint256 constant INITIAL_SUPPLY = 10_000_000 * 10**18;

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        
        vm.deal(owner, 1000 ether);
        console.log("Owner address:",owner);
        console.log("user1 address:",user1);
        console.log("user2 address:",user2);
        console.log("user3 address:",user3);
        console.log("contract address:",address(this));
        
        // 部署模拟的 Uniswap 合约
        mockFactory = new MockUniswapV2Factory();
        mockRouter = new MockUniswapV2Router02(address(mockFactory));
        
        // 使用模拟路由器部署代币合约
        vm.prank(owner);
        memeToken = new MeMeToken(NAME, SYMBOL, INITIAL_SUPPLY, address(mockRouter));
        
        // 只给owner设置免限制，其他用户保持受限状态
        vm.prank(owner);
        memeToken.excludeFromLimits(owner, true);
        vm.prank(owner);
        memeToken.excludeFromTax(owner, true);
        vm.prank(owner);
        memeToken.excludeFromLimits(user1, false);
        
        // 给测试用户分配初始代币
        uint256 userAmount = 1000 * 10**18;
        vm.prank(owner);
        memeToken.transfer(user1, userAmount);
        
        vm.prank(owner);
        memeToken.transfer(user2, userAmount);
        
        vm.prank(owner);
        memeToken.transfer(user3, userAmount);

        uniswapV2Pair = memeToken.uniswapV2Pair();
        
    }

    // ========== 辅助函数 ==========
    
    function skipCooldown() internal {
        uint256 cooldown = memeToken.cooldownPeriod();
        if (cooldown < type(uint256).max - 1000) {
            vm.warp(block.timestamp + cooldown + 1);
        }
    }

    // ========== 基本转账功能测试 ==========

    function testBasicTransfer() public {
        uint256 transferAmount = 100 * 10**18;
        uint256 initialBalance1 = memeToken.balanceOf(user1);
        uint256 initialBalance2 = memeToken.balanceOf(user2);
        
        skipCooldown();
        
        vm.prank(user1);
        bool success = memeToken.transfer(user2, transferAmount);
        
        assertTrue(success);
        uint256 finalBalance1 = memeToken.balanceOf(user1);
        uint256 finalBalance2 = memeToken.balanceOf(user2);
        
        uint256 taxRate = memeToken.transferTax();
        uint256 taxAmount = (transferAmount * taxRate) / 10000;
        uint256 netAmount = transferAmount - taxAmount;
        
        assertEq(finalBalance1, initialBalance1 - transferAmount);
        assertEq(finalBalance2, initialBalance2 + netAmount);
    }

    function testTransferTaxCalculation() public {
        uint256 transferAmount = 100 * 10**18;
        uint256 taxRate = memeToken.transferTax();
        uint256 expectedTax = (transferAmount * taxRate) / 10000;
        uint256 expectedNetAmount = transferAmount - expectedTax;
        
        uint256 initialBalance1 = memeToken.balanceOf(user1);
        uint256 initialBalance2 = memeToken.balanceOf(user2);
        
        skipCooldown();
        
        vm.prank(user1);
        memeToken.transfer(user2, transferAmount);
        
        uint256 finalBalance1 = memeToken.balanceOf(user1);
        uint256 finalBalance2 = memeToken.balanceOf(user2);
        
        assertEq(finalBalance1, initialBalance1 - transferAmount);
        assertEq(finalBalance2, initialBalance2 + expectedNetAmount);
    }

    function testTaxExemptTransfer() public {
        uint256 transferAmount = 100 * 10**18;
        
        // 设置用户免税
        vm.prank(owner);
        memeToken.excludeFromTax(user1, true);
        vm.prank(owner);
        memeToken.excludeFromTax(user2, true);
        
        uint256 initialBalance1 = memeToken.balanceOf(user1);
        uint256 initialBalance2 = memeToken.balanceOf(user2);
        
        skipCooldown();
        
        vm.prank(user1);
        memeToken.transfer(user2, transferAmount);
        
        uint256 finalBalance1 = memeToken.balanceOf(user1);
        uint256 finalBalance2 = memeToken.balanceOf(user2);
        
        // 免税转账应该没有税费扣除
        assertEq(finalBalance1, initialBalance1 - transferAmount);
        assertEq(finalBalance2, initialBalance2 + transferAmount);
    }

    // ========== 交易限制测试 ==========

    function testMaxTransactionAmount() public {
        
        uint256 maxTx = memeToken.maxTransactionAmount();
        uint256 exceedAmount = maxTx + 1000000;
        console.log("maxTx: ",maxTx / 1e18);
        // 给user1足够代币
        vm.prank(owner);
        memeToken.transfer(user1, exceedAmount + 1000000 * 10**18);
        
        skipCooldown();
        //打印user1的余额
        console.log("1111  User1 balance:",memeToken.balanceOf(user1) / 1e18);
        
        vm.prank(user1);
        vm.expectRevert("Exceeds max transaction amount");
        // 向mockRouter的WETH地址转账，触发最大交易量限制
        memeToken.transfer(uniswapV2Pair, exceedAmount);
        // 测试正好等于最大交易量应该成功
        skipCooldown();
        //打印user1的余额
        console.log("22222  User1 balance:",memeToken.balanceOf(user1) / 1e18);
        vm.prank(user1);
        bool success = memeToken.transfer(uniswapV2Pair, maxTx);
        assertTrue(success);
    }

    function testMaxWalletBalance() public {
        uint256 maxWallet = memeToken.maxWalletBalance();
        uint256 currentBalance = memeToken.balanceOf(user2);
        uint256 exceedAmount = maxWallet - currentBalance + 1;
        

        uint256 ownerBalance = memeToken.balanceOf(owner);
        // 如果owner余额不足，调整测试金额
        uint256 testAmount = (exceedAmount + 1000 * 10**18 > ownerBalance) 
            ? ownerBalance - 1000 * 10**18  // 使用owner实际可转金额
            : exceedAmount + 1000 * 10**18; // 使用原计划金额

        console.log("exceedAmount: ",exceedAmount / 1e18);
        console.log("Owner balance:",ownerBalance / 1e18);
        console.log("User1 balance:",memeToken.balanceOf(user1) / 1e18);
        
        // 给user1足够代币进行测试
        vm.prank(owner);
        
        memeToken.transfer(user1, testAmount);
        
        skipCooldown();
        
        vm.prank(user1);
        
        vm.expectRevert("Exceeds max wallet amount");
        memeToken.transfer(user2, exceedAmount);
        
        // 测试正好等于最大持币量应该成功
        skipCooldown();
        vm.prank(user1);
        bool success = memeToken.transfer(user2, maxWallet - currentBalance);
        assertTrue(success);
    }

    function testCooldownPeriod() public {
        uint256 transferAmount = 100 * 10**18;
        uint256 cooldown = memeToken.cooldownPeriod();
        
        // 第一次转账应该成功
        skipCooldown();
        uint256 initialBalance1 = memeToken.balanceOf(user1);
        uint256 initialBalance2 = memeToken.balanceOf(user2);
        
        vm.prank(user1);
        memeToken.transfer(user2, transferAmount);
        
        // 验证第一次转账成功
        uint256 finalBalance1 = memeToken.balanceOf(user1);
        uint256 finalBalance2 = memeToken.balanceOf(user2);
        uint256 taxRate = memeToken.transferTax();
        uint256 taxAmount = (transferAmount * taxRate) / 10000;
        uint256 netAmount = transferAmount - taxAmount;
        
        assertEq(finalBalance1, initialBalance1 - transferAmount);
        assertEq(finalBalance2, initialBalance2 + netAmount);
        
        // 立即尝试第二次转账（应该失败，因为冷却时间未过）
        vm.prank(user1);
        vm.expectRevert("Cooldown period not elapsed");
        memeToken.transfer(user2, transferAmount);
        
        // 等待冷却时间过后再次尝试（应该成功）
        vm.warp(block.timestamp + cooldown + 1);
        vm.prank(user1);
        bool success = memeToken.transfer(user2, transferAmount);
        assertTrue(success);
    }

    // ========== 紧急暂停功能测试 ==========

    function testEmergencyPause() public {
        // 暂停合约
        vm.warp(block.timestamp + memeToken.cooldownPeriod() + 1);
         // 3. 设置紧急暂停
        vm.prank(owner);
        memeToken.emergencyPause();
        
        assertEq(memeToken.maxTransactionAmount(), 0);
        assertEq(memeToken.cooldownPeriod(), type(uint256).max);
        
        // 测试：任何非零金额的转账都应该失败（因为最大交易量为0）
        vm.prank(user1);
        vm.expectRevert("Cooldown period not elapsed");
        memeToken.transfer(uniswapV2Pair, 1); // 即使是1个代币也应该失败
    }

    function testEmergencyUnpause() public {
        // 先暂停
        vm.prank(owner);
        memeToken.emergencyPause();
        
        // 再恢复
        uint256 newMaxTx = 500000 * 10**18;
        uint256 newCooldown = 60;
        vm.prank(owner);
        memeToken.emergencyUnpause(newMaxTx, newCooldown);
        
        assertEq(memeToken.maxTransactionAmount(), newMaxTx);
        assertEq(memeToken.cooldownPeriod(), newCooldown);
        
        // 测试恢复后转账应该正常工作
        skipCooldown();
        vm.prank(user1);
        bool success = memeToken.transfer(user2, 100 * 10**18);
        assertTrue(success);
    }

    // ========== 边界情况测试 ==========

    function testTransferToZeroAddress() public {
        uint256 transferAmount = 100 * 10**18;
        
        skipCooldown();
        vm.prank(user1);
        vm.expectRevert("Transfer to the zero address");
        memeToken.transfer(address(0), transferAmount);
    }

    function testTransferZeroAmount() public {
        skipCooldown();
        vm.prank(user1);
        vm.expectRevert("Transfer amount must be greater than zero");
        memeToken.transfer(user2, 0);
    }

    function testInsufficientBalance() public {
        uint256 userBalance = memeToken.balanceOf(user1);
        uint256 exceedAmount = userBalance + 1;
        
        skipCooldown();
        vm.prank(user1);
        vm.expectRevert();
        memeToken.transfer(user2, exceedAmount);
    }

    // ========== 管理员功能测试 ==========

    function testOwnerCanUpdateTaxRates() public {
        uint256 newBuyTax = 3;
        uint256 newSellTax = 6;
        uint256 newTransferTax = 1;
        
        vm.prank(owner);
        memeToken.setTaxRate(newBuyTax, newSellTax, newTransferTax);
        
        assertEq(memeToken.buyTax(), newBuyTax);
        assertEq(memeToken.sellTax(), newSellTax);
        assertEq(memeToken.transferTax(), newTransferTax);
    }

    function testNonOwnerCannotUpdateTaxRates() public {
        uint256 newBuyTax = 3;
        uint256 newSellTax = 6;
        uint256 newTransferTax = 1;
        
        vm.prank(user1);
        vm.expectRevert();
        memeToken.setTaxRate(newBuyTax, newSellTax, newTransferTax);
    }

    function testSetTaxRecipient() public {
        address newRecipient = makeAddr("newTaxRecipient");
        
        vm.prank(owner);
        memeToken.setTaxRecipient(newRecipient);
        
        assertEq(memeToken.taxRecipient(), newRecipient);
    }

    function testNonOwnerCannotSetTaxRecipient() public {
        address newRecipient = makeAddr("newTaxRecipient");
        
        vm.prank(user1);
        vm.expectRevert();
        memeToken.setTaxRecipient(newRecipient);
    }

    function testSetTransactionLimits() public {
        uint256 newMaxTx = 2000000 * 10**18;
        uint256 newMaxWallet = 8000000 * 10**18;
        uint256 newCooldown = 600;
        
        vm.prank(owner);
        memeToken.setTransactionLimits(newMaxTx, newMaxWallet, newCooldown);
        
        assertEq(memeToken.maxTransactionAmount(), newMaxTx);
        assertEq(memeToken.maxWalletBalance(), newMaxWallet);
        assertEq(memeToken.cooldownPeriod(), newCooldown);
    }

    function testNonOwnerCannotSetTransactionLimits() public {
        uint256 newMaxTx = 2000000 * 10**18;
        uint256 newMaxWallet = 8000000 * 10**18;
        uint256 newCooldown = 600;
        
        vm.prank(user1);
        vm.expectRevert();
        memeToken.setTransactionLimits(newMaxTx, newMaxWallet, newCooldown);
    }

    // ========== 免税/免限制地址管理测试 ==========

    function testExcludeFromLimits() public {
        // 测试设置免限制
        vm.prank(owner);
        memeToken.excludeFromLimits(user1, true);
        assertTrue(memeToken.isExcludedFromLimits(user1));
        
        // 测试移除免限制
        vm.prank(owner);
        memeToken.excludeFromLimits(user1, false);
        assertFalse(memeToken.isExcludedFromLimits(user1));
    }

    function testExcludeFromTax() public {
        vm.prank(owner);
        memeToken.excludeFromTax(user1, true);
        assertTrue(memeToken.isExcludedFromTax(user1));
        
        vm.prank(owner);
        memeToken.excludeFromTax(user1, false);
        assertFalse(memeToken.isExcludedFromTax(user1));
    }

    // ========== 税费分配比例测试 ==========

    function testTaxDistributionRatios() public {
        assertEq(memeToken.burnedTax(), 20);
        assertEq(memeToken.liquidityTax(), 60);
        assertEq(memeToken.recipientTax(), 20);
    }

    // ========== 事件测试 ==========

    function testTaxUpdatedEvent() public {
        uint256 newBuyTax = 3;
        uint256 newSellTax = 6;
        uint256 newTransferTax = 1;
        
        vm.expectEmit(true, true, true, true);
        emit MeMeToken.TaxUpdated(newBuyTax, newSellTax, newTransferTax);
        
        vm.prank(owner);
        memeToken.setTaxRate(newBuyTax, newSellTax, newTransferTax);
    }

    function testTransactionLimitsUpdatedEvent() public {
        uint256 newMaxTx = 2000000 * 10**18;
        uint256 newMaxWallet = 8000000 * 10**18;
        uint256 newCooldown = 600;
        
        vm.expectEmit(true, true, true, true);
        emit MeMeToken.TransactionLimitsUpdated(newMaxTx, newMaxWallet, newCooldown);
        
        vm.prank(owner);
        memeToken.setTransactionLimits(newMaxTx, newMaxWallet, newCooldown);
    }

    // ========== 合约状态查询测试 ==========

    function testContractState() public {
        // 测试初始状态
        assertEq(memeToken.buyTax(), 5);
        assertEq(memeToken.sellTax(), 10);
        assertEq(memeToken.transferTax(), 2);
        assertEq(memeToken.maxTransactionAmount(), 1000000 * 10**18);
        assertEq(memeToken.maxWalletBalance(), 5000000 * 10**18);
        assertEq(memeToken.cooldownPeriod(), 300);
        assertEq(memeToken.taxRecipient(), owner);
        assertEq(memeToken.owner(), owner);
    }

    // ========== 免限制地址转账测试 ==========

    function testExcludedFromLimitsTransfer() public {
        // 设置用户免限制
        vm.prank(owner);
        memeToken.excludeFromLimits(user1, true);
        vm.prank(owner);
        memeToken.excludeFromLimits(user2, true);
        
        uint256 transferAmount = 100 * 10**18;
        uint256 initialBalance1 = memeToken.balanceOf(user1);
        uint256 initialBalance2 = memeToken.balanceOf(user2);
        
        // 免限制用户应该可以立即连续转账（不受冷却时间限制）
        vm.prank(user1);
        memeToken.transfer(user2, transferAmount);
        
        // 立即再次转账（应该成功，因为免限制）
        vm.prank(user1);
        bool success = memeToken.transfer(user2, transferAmount);
        assertTrue(success);
        
        uint256 finalBalance1 = memeToken.balanceOf(user1);
        uint256 finalBalance2 = memeToken.balanceOf(user2);
        
        uint256 taxRate = memeToken.transferTax();
        uint256 taxAmount = (transferAmount * taxRate) / 10000;
        uint256 netAmount = transferAmount - taxAmount;
        uint256 totalNetAmount = netAmount * 2;
        
        assertEq(finalBalance1, initialBalance1 - (transferAmount * 2));
        assertEq(finalBalance2, initialBalance2 + totalNetAmount);
    }

    // ========== 大额交易测试 ==========

    function testLargeAmountTransfer() public {
        uint256 largeAmount = 500000 * 10**18; // 50万代币
        
        // 给user1足够代币
        vm.prank(owner);
        memeToken.transfer(user1, largeAmount + 1000 * 10**18);
        skipCooldown();
        
        vm.prank(user1);
        bool success = memeToken.transfer(user2, largeAmount);
        assertTrue(success);
        
        // 验证余额变化
        uint256 taxRate = memeToken.transferTax();
        uint256 taxAmount = (largeAmount * taxRate) / 10000;
        uint256 netAmount = largeAmount - taxAmount;
        
        assertEq(memeToken.balanceOf(user2), 1000 * 10**18 + netAmount);
    }
}
