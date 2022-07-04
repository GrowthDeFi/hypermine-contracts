const Hmine = artifacts.require("HmineMain.sol");
const HmineToken = artifacts.require("HmineToken.sol");
const MockDai = artifacts.require("MockDai.sol");

module.exports = async function (deployer, network, addresses) {
  if (network == "mumbai") {
   
  }

  if (network == "bsc") {

    await deployer.deploy(
      HmineToken,
    );
    const hmineToken = await HmineToken.deployed();

    await deployer.deploy(
      MockDai,
    );
    const mockDai = await MockDai.deployed();

    await deployer.deploy(
      Hmine,
      mockDai.address,
      hmineToken.address
    );
    const hmine = await Hmine.deployed();
   
  }
};
