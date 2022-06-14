const { assert } = require("chai");

const WBNB = artifacts.require("MockToken.sol");
const MOR = artifacts.require("MockToken.sol");
const DAI = artifacts.require("MockToken.sol");
const USDC = artifacts.require("MockToken.sol");
const BUSD = artifacts.require("MockToken.sol");
const SAFE = artifacts.require("MockToken.sol");
const MockOraclePair = artifacts.require("MockOraclePair.sol");
const HmineSacrifice = artifacts.require("HmineSacrifice.sol");

contract("Deployed&Test", ([admin, sacrificesTo, carol, dev, tester]) => {
  beforeEach(async () => {
    this.wbnb = await WBNB.new("WBNB", "WBNB", 18, { from: admin });
    this.mor = await MOR.new("MOR", "MOR", 18, { from: admin });
    this.dai = await DAI.new("DAI", "DAI", 18, { from: admin });
    this.usdc = await USDC.new("USDC", "USDC", 18, { from: admin });
    this.busd = await BUSD.new("BUSD", "BUSD", 18, { from: admin });
    this.safe = await SAFE.new("SAFE", "SAFE", 18, { from: admin });

    this.oracle = await MockOraclePair.new(
      this.wbnb.address,
      this.busd.address
    );
    this.hmine = await HmineSacrifice.new(
      sacrificesTo,
      this.wbnb.address,
      this.oracle.address,
      { from: admin }
    );
  });

  it("AdminHasTokens", async () => {
    assert.equal(
      (await this.wbnb.balanceOf(admin)).toString(),
      "1000000000000000000000000"
    );
    assert.equal(
      (await this.mor.balanceOf(admin)).toString(),
      "1000000000000000000000000"
    );
    assert.equal(
      (await this.dai.balanceOf(admin)).toString(),
      "1000000000000000000000000"
    );

    assert.equal(
      (await this.usdc.balanceOf(admin)).toString(),
      "1000000000000000000000000"
    );
    assert.equal(
      (await this.busd.balanceOf(admin)).toString(),
      "1000000000000000000000000"
    );
    assert.equal(
      (await this.safe.balanceOf(admin)).toString(),
      "1000000000000000000000000"
    );
  });

  it("OracleHasReserves", async () => {
    const reserves = await this.oracle.getReserves();
    assert.equal(reserves[1].toString(), "300000000000000000000");
    assert.equal(reserves[0].toString(), "1000000000000000000");
  });

  it("HmineSacrificeDeployed", async () => {
    const sacToAddress = await this.hmine.sacrificesTo();
    assert.equal(sacrificesTo, sacToAddress);
  });

  it("CorrectWBnbAddress", async () => {
    const wbnb = await this.hmine.wbnb();
    assert.equal(wbnb, this.wbnb.address);
  });

  it("OracleIsBNB&BUSD", async () => {
    const oracle = await this.hmine.getSacrificeInfo(this.wbnb.address);
    const token0 = await this.oracle.token0();
    const token1 = await this.oracle.token1();
    assert.equal(token0, this.wbnb.address);
    assert.equal(token1, this.busd.address);
    assert.equal(this.oracle.address, oracle.oracleAddress);
  });
});
