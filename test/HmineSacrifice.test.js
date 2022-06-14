const { assert, expect } = require("chai");

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

  it("OracleIsBNB&BUSD", async () => {
    const oracle = await this.hmine.getSacrificeInfo(this.wbnb.address);
    const token0 = await this.oracle.token0();
    const token1 = await this.oracle.token1();
    assert.equal(token0, this.wbnb.address);
    assert.equal(token1, this.busd.address);
    assert.equal(this.oracle.address, oracle.oracleAddress);
  });

  it("BNBisThreeHundredDollars", async () => {
    const token0 = await this.oracle.token0();
    const reserves = await this.oracle.getReserves();

    if (token0 === this.wbnb.address) {
      assert.equal(300, reserves[1] / reserves[0]);
    } else {
      assert.equal(300, reserves[0] / reserves[1]);
    }
  });

  it("BNBisEnabled", async () => {
    const data = await this.hmine.getSacrificeInfo(this.wbnb.address);
    assert.equal(true, data.isEnabled);
  });

  it("BUSDisEnabled", async () => {
    await this.hmine.addSacToken(
      this.busd.address,
      true,
      "0x0000000000000000000000000000000000000000"
    );
    const data = await this.hmine.getSacrificeInfo(this.busd.address);
    assert.equal(true, data.isEnabled);
  });

  it("MORisEnabled", async () => {
    await this.hmine.addSacToken(
      this.mor.address,
      true,
      "0x0000000000000000000000000000000000000000"
    );
    const data = await this.hmine.getSacrificeInfo(this.mor.address);
    assert.equal(true, data.isEnabled);
  });

  it("DAIisEnabled", async () => {
    await this.hmine.addSacToken(
      this.dai.address,
      true,
      "0x0000000000000000000000000000000000000000"
    );
    const data = await this.hmine.getSacrificeInfo(this.dai.address);
    assert.equal(true, data.isEnabled);
  });

  it("USDCisEnabled", async () => {
    await this.hmine.addSacToken(
      this.usdc.address,
      true,
      "0x0000000000000000000000000000000000000000"
    );
    const data = await this.hmine.getSacrificeInfo(this.usdc.address);
    assert.equal(true, data.isEnabled);
  });

  it("SAFEisEnabled", async () => {
    await this.hmine.addSacToken(
      this.safe.address,
      true,
      "0x0000000000000000000000000000000000000000"
    );
    const data = await this.hmine.getSacrificeInfo(this.safe.address);
    assert.equal(true, data.isEnabled);
  });

  it("RoundNotStartedYet", async () => {
    await this.hmine.startFirstRound(Math.trunc(Date.now() / 1000 + 15000));
    await expect(
      this.hmine.sacrificeBNB({ from: dev, value: "10000000000000000000" })
    ).to.be.revertedWith("Round ended or not started yet.");
  });

  it("SacrificedBNBWorked", async () => {
    await this.hmine.startFirstRound(Math.trunc(Date.now() / 1000 - 15000));
    await this.hmine.sacrificeBNB({ from: dev, value: "10000000000000000000" });

    const data = await this.hmine.getUserByAddress(dev);
    const data2 = await this.hmine.getUserByIndex(0);

    assert.equal(data.user, data2.user);
    assert.equal(data.amount * 6, 10e18 * 300);
  });

  it("SacrificedStableWorked", async () => {
    await this.hmine.startFirstRound(Math.trunc(Date.now() / 1000 - 15000));
    await this.hmine.addSacToken(
      this.safe.address,
      true,
      "0x0000000000000000000000000000000000000000"
    );
    await this.safe.approve(this.hmine.address, "6000000000000000000000");
    await this.hmine.sacrificeERC20(this.safe.address, "6000000000000000000000");

    const data = await this.hmine.getUserByAddress(dev);
    const data2 = await this.hmine.getUserByIndex(0);

    assert.equal(data.user, data2.user);
    assert.equal(data.amount * 6, 6000e18);
  });

  it("AllRoundsHaveEnded", async () => {
    await this.hmine.startFirstRound(Math.trunc(Date.now() / 1000 - 86400 * 4));
    await expect(
      this.hmine.sacrificeBNB({ from: dev, value: "10000000000000000000" })
    ).to.be.revertedWith("Round ended or not started yet.");
  });

  it("MaxHmineReached", async () => {
    await this.hmine.updateRoundMax("200000000000000000000");
    await this.hmine.startFirstRound(Math.trunc(Date.now() / 1000 - 15000));
    await expect(
      this.hmine.sacrificeBNB({ from: dev, value: "10000000000000000000" })
    ).to.be.revertedWith("Round ended or not started yet.");
  });

  it("RoundValueCheck", async () => {
    await this.hmine.startFirstRound(Math.trunc(Date.now() / 1000 - 86400 * 3));
    await this.hmine.sacrificeBNB({ from: dev, value: "10000000000000000000" });

    const data = await this.hmine.getUserByAddress(dev);
    const data2 = await this.hmine.getUserByIndex(0);

    assert.equal(data.user, data2.user);
    assert.equal((data.amount / 1e18).toFixed(0), "462");
  });
});
