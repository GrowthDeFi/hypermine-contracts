const HmineSacrifice = artifacts.require("HmineSacrifice.sol");

module.exports = async function (deployer, network, addresses) {
  if (network == "mumbai") {
    const sacrificesTo = addresses[0];

    await deployer.deploy(
      HmineSacrifice,
      sacrificesTo,
      "0x9174f7b1b2588Cf4b830010A82B68345219D2B54",
      "0xf3d351cf746c9F41e30908432bC7A9Af22BCa65C",
      "0xC1C89d94B7e36E657F55F5Ae5eaDDd049B8C3129"
    );
    const hmineSacrifice = await HmineSacrifice.deployed();
    await hmineSacrifice.addSacToken(
      "0xedAf86e68Ea4a67681d7116f24564e39968006Cf",
      true,
      "0x0000000000000000000000000000000000000000"
    );

    await hmineSacrifice.addSacToken(
      "0x98D95eDc8FCfd17284A0F9f20FA75372D6282011",
      true,
      "0x0000000000000000000000000000000000000000"
    );

    await hmineSacrifice.addSacToken(
      "0x1bA00eDf85bDA74b1B20dc11F133fe893007C8Df",
      true,
      "0x0000000000000000000000000000000000000000"
    );
    await hmineSacrifice.addSacToken(
      "0xdBA305f84Fe1cc02bbc1B5185D3FdF1AF30e2C64",
      true,
      "0x0000000000000000000000000000000000000000"
    );
    await hmineSacrifice.addSacToken(
      "0xCEEAc2ca17D32DF5EB00ddE5C695Cb172aA954b3",
      true,
      "0x0000000000000000000000000000000000000000"
    );
  }

  if (network == "bsc") {
    const sacrificesTo = addresses[0];

    await deployer.deploy(
      HmineSacrifice,
      sacrificesTo,
      "0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c",
      "0x58f876857a02d6762e0101bb5c46a8c1ed44dc16",
      "0xA518DF59453d53bff35526c42A5C2d33438e75E5"
    );
    await HmineSacrifice.deployed();
   
  }
};
