// import { network } from "hardhat";
// import { Contract, ContractFactory } from "ethers";
// const { ethers, networkName } = await network.connect();
// async function main() {
  
//   // 获取部署者账户
//   const [deployer] = await ethers.getSigners();
//   console.log("Deploying contracts with the account:", deployer.address);
//   console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());

//   // 部署参数配置
//   const tokenName = "MeMeToken";
//   const tokenSymbol = "MEME";
//   const initialSupply = ethers.parseEther("1000000000"); // 10亿个代币，根据实际情况调整
//   const uniswapRouterAddress = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"; // 以太坊主网Uniswap V2 Router地址

//   // 对于测试网，可能需要使用不同的路由器地址
//   // 例如 Goerli: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D (与主网相同)
  
//   console.log("\nDeployment Parameters:");
//   console.log("Token Name:", tokenName);
//   console.log("Token Symbol:", tokenSymbol);
//   console.log("Initial Supply:", initialSupply.toString());
//   console.log("Uniswap Router:", uniswapRouterAddress);

//   // 部署合约
//   console.log("\nDeploying MeMeToken contract...");
  
//   const MeMeTokenFactory: ContractFactory = await ethers.getContractFactory("MeMeToken");
//   const memeToken: Contract = await MeMeTokenFactory.deploy(
//     tokenName,
//     tokenSymbol,
//     initialSupply,
//     uniswapRouterAddress
//   );

//   // 等待合约部署完成
//   await memeToken.waitForDeployment();
//   const tokenAddress = await memeToken.getAddress();
  
//   console.log("MeMeToken deployed to:", tokenAddress);

//   // 验证合约部署
//   console.log("\nVerifying deployment...");
  
//   // 检查基本合约信息
//   const name = await memeToken.name();
//   const symbol = await memeToken.symbol();
//   const totalSupply = await memeToken.totalSupply();
//   const owner = await memeToken.owner();
//   const uniswapV2Pair = await memeToken.uniswapV2Pair();
  
//   console.log("Token Name:", name);
//   console.log("Token Symbol:", symbol);
//   console.log("Total Supply:", totalSupply.toString());
//   console.log("Contract Owner:", owner);
//   console.log("Uniswap V2 Pair:", uniswapV2Pair);

//   // 验证税费设置
//   const buyTax = await memeToken.buyTax();
//   const sellTax = await memeToken.sellTax();
//   const transferTax = await memeToken.transferTax();
//   const taxRecipient = await memeToken.taxRecipient();
  
//   console.log("\nTax Settings:");
//   console.log("Buy Tax:", buyTax.toString() + "%");
//   console.log("Sell Tax:", sellTax.toString() + "%");
//   console.log("Transfer Tax:", transferTax.toString() + "%");
//   console.log("Tax Recipient:", taxRecipient);

//   // 验证交易限制设置
//   const maxTransactionAmount = await memeToken.maxTransactionAmount();
//   const maxWalletBalance = await memeToken.maxWalletBalance();
//   const cooldownPeriod = await memeToken.cooldownPeriod();
  
//   console.log("\nTransaction Limits:");
//   console.log("Max Transaction Amount:", maxTransactionAmount.toString());
//   console.log("Max Wallet Balance:", maxWalletBalance.toString());
//   console.log("Cooldown Period:", cooldownPeriod.toString() + " seconds");

//   // 验证税费分配设置
//   const burnedTax = await memeToken.burnedTax();
//   const liquidityTax = await memeToken.liquidityTax();
//   const recipientTax = await memeToken.recipientTax();
  
//   console.log("\nTax Distribution:");
//   console.log("Burned Tax Share:", burnedTax.toString() + "%");
//   console.log("Liquidity Tax Share:", liquidityTax.toString() + "%");
//   console.log("Recipient Tax Share:", recipientTax.toString() + "%");

//   // 保存部署信息到文件（可选）
//   const deploymentInfo = {
//     network: (await ethers.provider.getNetwork()).name,
//     timestamp: new Date().toISOString(),
//     contract: {
//       name: tokenName,
//       address: tokenAddress,
//       symbol: tokenSymbol,
//       deployer: deployer.address
//     },
//     parameters: {
//       initialSupply: initialSupply.toString(),
//       uniswapRouter: uniswapRouterAddress,
//       uniswapPair: uniswapV2Pair
//     },
//     taxSettings: {
//       buyTax: buyTax.toString(),
//       sellTax: sellTax.toString(),
//       transferTax: transferTax.toString(),
//       taxRecipient: taxRecipient
//     },
//     limits: {
//       maxTransactionAmount: maxTransactionAmount.toString(),
//       maxWalletBalance: maxWalletBalance.toString(),
//       cooldownPeriod: cooldownPeriod.toString()
//     }
//   };

//   // 可以保存到文件或输出为JSON
//   console.log("\nDeployment Info JSON:");
//   console.log(JSON.stringify(deploymentInfo, null, 2));

//   return {
//     memeToken,
//     deploymentInfo
//   };
// }

// // 错误处理
// main().catch((error) => {
//   console.error(error);
//   process.exitCode = 1;
// });

// export { main };