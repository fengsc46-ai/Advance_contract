import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

module.exports = buildModule("MeMeTokenDeployer", (m) => {
  const name = "myMeMeToken";
  const symbol = "MMTK";
  const initialSupply = m.getParameter("initialSupply", "90000000000000000000000000"); // 90M tokens
  const uniswapRouter = m.getParameter("uniswapRouter", "0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3");

  // 部署合约
  const meMeToken = m.contract("MeMeToken", [name, symbol, initialSupply, uniswapRouter]);


  return { meMeToken };
});