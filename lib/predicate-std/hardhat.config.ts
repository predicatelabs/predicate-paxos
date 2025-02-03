import "@nomicfoundation/hardhat-foundry";

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.12",
  paths: {
    sources: "./src/",
    cache: "./cache_hardhat",
  }
};