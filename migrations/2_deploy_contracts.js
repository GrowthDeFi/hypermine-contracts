const Hmine = artifacts.require("HmineMain.sol");
const HmineToken = artifacts.require("HmineToken.sol");
const MockDai = artifacts.require("MockDai.sol");

module.exports = async function (deployer, network, addresses) {
  if (network == "mumbai") {
  }

  if (network == "bsc") {
    await deployer.deploy(HmineToken);
    const hmineToken = await HmineToken.deployed();

    const dai = "0x1af3f329e8be154074d8769d1ffa4ee058b1dbc3";

    await deployer.deploy(Hmine, dai, hmineToken.address);

    await Hmine.deployed();
  }
};
