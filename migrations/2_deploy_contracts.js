const WBNB = artifacts.require("MockToken.sol");
const MOR = artifacts.require("MockToken.sol");
const DAI = artifacts.require("MockToken.sol");
const USDC = artifacts.require("MockToken.sol");
const BUSD = artifacts.require("MockToken.sol");
const SAFE = artifacts.require("MockToken.sol");
const MockOracle = artifacts.require("MockOracle.sol");
const MockOraclePair = artifacts.require("MockOraclePair.sol");
const HmineSacrifice = artifacts.require("HmineSacrifice.sol");

module.exports = async function (deployer, network, addresses) {
  if (network == "mumbai") {
    const sacrificesTo = addresses[0];

    await deployer.deploy(WBNB, "WBNB", "WBNB", 18);
    const wbnb = await WBNB.deployed();

    await deployer.deploy(MOR, "MOR", "MOR", 18);
    const mor = await MOR.deployed();

    await deployer.deploy(DAI, "DAI", "DAI", 18);
    const dai = await DAI.deployed();

    await deployer.deploy(USDC, "USDC", "USDC", 18);
    const usdc = await USDC.deployed();

    await deployer.deploy(BUSD, "BUSD", "BUSD", 18);
    const busd = await BUSD.deployed();

    await deployer.deploy(SAFE, "SAFE", "SAFE", 18);
    const safe = await SAFE.deployed();

    await deployer.deploy(MockOracle);
    const oracle = await MockOracle.deployed();

    await deployer.deploy(MockOraclePair, wbnb.address, busd.address);
    const oracleLP = await MockOraclePair.deployed();

    await deployer.deploy(
      HmineSacrifice,
      sacrificesTo,
      wbnb.address,
      oracleLP.address,
      oracle.address
    );
    const hmineSacrifice = await HmineSacrifice.deployed();
  }
};
