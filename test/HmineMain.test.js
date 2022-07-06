const { assert } = require("chai");

const HmineMain = artifacts.require("HmineMain.sol");
const MockDai = artifacts.require("MockDai.sol");
const HmineToken = artifacts.require("HmineToken.sol");

const Data = require("../tupleData");

contract("HmineMainLaunchTest", ([admin, sacrificesTo, carol, dev, tester]) => {
  beforeEach(async () => {
    this.dai = await MockDai.new({ from: admin });
    this.hmine = await HmineToken.new({ from: admin });
    this.hmineMain = await HmineMain.new(this.dai.address, this.hmine.address, {
      from: admin,
    });

    await this.hmineMain.updateStateAddresses(admin, admin);
    await this.dai.approve(
      this.hmineMain.address,
      "1000000000000000000000000000000"
    );
    await this.hmine.approve(
      this.hmineMain.address,
      "1000000000000000000000000000000"
    );

    await this.hmineMain.migrateSacrifice([
      [
        "SavageFitnessCrypto",
        "0x16D088a79D7d36213618263184783fB4d6375e33",
        "11538461538461538461538",
        "3208715582174656064349",
      ],
      [
        "Ghost3d",
        "0x2165fa4a32B9c228cD55713f77d2e977297D03e8",
        "8637444159898078006557",
        "6768163705064454747195",
      ],
      [
        "Ante_Hodler",
        "0x52aB9D2e40F72caf62b4Bf587B91AD3675E99CFB",
        "5244816666666666666666",
        "3697531946112190059248",
      ],
    ]);
    const hmineBalance = await this.hmine.balanceOf(admin);
    await this.hmine.transfer(this.hmineMain.address, hmineBalance);
    await this.dai.transfer(
      this.hmineMain.address,
      "10000000000000000000000000"
    );
    await this.hmineMain.initialize(Math.trunc(Date.now() / 1000));
  });

  it("Successfully Initialized", async () => {
    const startTime = await this.hmineMain.startTime();

    assert.notEqual(startTime * 1, 0);
  });

  it("Check Initial Total", async () => {
    const totalSold = await this.hmineMain.totalSold();

    assert.equal(25420.722365026282, totalSold / 1e18);
  });

  it("Check Price after Buy 1", async () => {
    await this.hmineMain.buy("529054943444816026000000");
    const totalSold = await this.hmineMain.totalSold();
    const price = await this.hmineMain.currentPrice();
    assert.equal(101000, totalSold / 1e18);
    assert.equal(10, price / 1e18);
  });

  it("Check Price after Buy 2", async () => {
    await this.hmineMain.buy("539054943444816026000000");
    const totalSold = await this.hmineMain.totalSold();
    const price = await this.hmineMain.currentPrice();
    assert.equal(102000, totalSold / 1e18);
    assert.equal(13, price / 1e18);
  });

  it("Check Price after Sell", async () => {
    await this.hmineMain.buy("587054943444816026000000");
    let totalSold = await this.hmineMain.totalSold();
    let price = await this.hmineMain.currentPrice();
    assert.equal(105000, totalSold / 1e18);
    assert.equal(22, price / 1e18);

    await this.hmineMain.unstake("1000000000000000000000");
    const daiPreviousBalance = await this.dai.balanceOf(admin);

    await this.hmineMain.sell("600000000000000000000");
    totalSold = await this.hmineMain.totalSold();
    price = await this.hmineMain.currentPrice();

    const daiBalance = await this.dai.balanceOf(admin);

    assert.equal(104400, totalSold / 1e18);
    assert.equal(19, price / 1e18);
    assert.equal(
      6840 >= (daiBalance - daiPreviousBalance) / 1e18 &&
        6839.99 <= (daiBalance - daiPreviousBalance) / 1e18,
      true
    );
  });

  it("Check Reward", async () => {
    await this.hmineMain.buy("529054943444816026000000");
    let totalSold = await this.hmineMain.totalSold();
    let price = await this.hmineMain.currentPrice();

    await this.hmineMain.buy("10000000000000000000000");
    totalSold = await this.hmineMain.totalSold();
    price = await this.hmineMain.currentPrice();

    let reward = await this.hmineMain.userRewardBalance(admin);

    assert.equal(102000, totalSold / 1e18);
    assert.equal(13, price / 1e18);
    assert.equal(748.3096795534469, reward / 1e18);
  });

  it("Check Reward 2", async () => {
    await this.hmineMain.buy("529054943444816026000000");
    await this.hmineMain.sendDailyDiv("1000000000000000000000");

    let reward = await this.hmineMain.userRewardBalance(admin);
    assert.equal(748.3096795534469, reward / 1e18);

    await this.hmineMain.claim();
    reward = await this.hmineMain.userRewardBalance(admin);
    assert.equal(0, reward);

    await this.hmineMain.buy("10000000000000000000000");

    reward = await this.hmineMain.userRewardBalance(admin);
    assert.equal(748.3096795534469, reward / 1e18);
  });

  it("Check Compound", async () => {
    await this.hmineMain.buy("529054943444816026000000");
    await this.hmineMain.sendDailyDiv("10000000000000000000000");

    let reward = await this.hmineMain.userRewardBalance(admin);
    assert.equal(7483.0967955344695, reward / 1e18);

    const userStake0 = await this.hmineMain.getUserByAddress(admin);
    await this.hmineMain.compound();
    const userStake1 = await this.hmineMain.getUserByAddress(admin);
    assert.equal(true, userStake0.amount / 1e18 < userStake1.amount / 1e18);
    assert.equal(76327.58731452716, userStake1.amount / 1e18);
  });

  it("Check Unstake and Stake", async () => {
    await this.hmineMain.buy("529054943444816026000000");
    const userStake0 = await this.hmineMain.getUserByAddress(admin);

    await this.hmineMain.unstake("100000000000000000000");

    const userStake1 = await this.hmineMain.getUserByAddress(admin);

    userBalance = await this.hmine.balanceOf(admin);

    assert.equal(
      BigInt(userStake0.amount) - BigInt(userStake1.amount),
      BigInt("100000000000000000000")
    );
    // 80 as user and 10 as bankroll
    assert.equal(90, userBalance / 1e18);

    await this.hmineMain.stake("90000000000000000000");

    const userStake2 = await this.hmineMain.getUserByAddress(admin);
    userBalance = await this.hmine.balanceOf(admin);

    assert.equal(
      BigInt(userStake1.amount) + BigInt("90000000000000000000"),
      BigInt(userStake2.amount)
    );

    assert.equal(0, userBalance / 1e18);
  });
});
