const axios = require("axios");
const Web3 = require("web3");
const SacData = require("./sacrificeData");

const api =
  "https://api.bscscan.com/api?module=logs&action=getLogs&fromBlock=4993830&toBlock=20000000000000&address=0x3f750f814df347800ed8bd869325da8a454ed964&topic0=0xfbfbee4122d97e8c0c0bae4824575d813ebd0192d6982f360ab56834b86abd2d&apikey=B7IYJD5B8SAFC671WPYIBXH214A6VI3XXJ";

const web3 = new Web3(
  new Web3.providers.HttpProvider("https://bsc-dataseed1.defibit.io")
);

const main = () => {
  axios.get(api).then((res) => {
    const data = res.data.result;

    const txArray = data.map((d) => {
      const address = web3.eth.abi.decodeParameters(["address"], d.topics[1]);
      const token = web3.eth.abi.decodeParameters(["address"], d.topics[2]);
      const info = web3.eth.abi.decodeParameters(
        ["uint256", "uint256"],
        d.data
      );

      let value = 0;
      if (Number(d.timeStamp) < 1656432000) {
        if (
          "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c".toLowerCase() ===
          token[0].toLowerCase()
        ) {
          value += (info[1] / 1e18) * 6;
        } else {
          value += info[0] / 1e18;
        }
      } else {
        if (
          "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c".toLowerCase() ===
          token[0].toLowerCase()
        ) {
          value += (info[1] / 1e18) * 6.5;
        } else {
          value += info[0] / 1e18;
        }
      }

      const Struct = {
        address: address[0],
        token: token[0],
        amount: info[0],
        hmine: info[1],
        value: value.toFixed(18) * 1e18,
        date: Number(d.timeStamp),
      };

      return Struct;
    });

    const userObject = [];
    let totalStaked = BigInt(0);
    let totalDiv = 0;

    txArray.forEach((tx, idx) => {
      if (idx > 0) {
        const amountTenth = BigInt(tx.value) / BigInt(10);
        totalDiv += amountTenth.toString() / 1e18;
        if (userObject.length) {
          userObject.forEach((u, i) => {
            userObject[i].reward = (
              BigInt(userObject[i].reward) +
              (amountTenth * BigInt(u.amount)) / totalStaked
            ).toString();
          });
        }
      }
      const index = userObject.findIndex((f) => f.user === tx.address);
      if (index == -1) {
        userObject.push({
          user: tx.address,
          nickname: tx.address,
          amount: BigInt(tx.hmine).toString(),
          reward: BigInt(0).toString(),
        });
      } else {
        userObject[index].amount = (
          BigInt(userObject[index].amount) + BigInt(tx.hmine)
        ).toString();
      }
      totalStaked += BigInt(tx.hmine);
    });

    console.log(totalDiv);
  });
};

//main();

const sortedData = () => {
  const sorted = SacData.array.sort(
    (a, b) => Number(b.amount) - Number(a.amount)
  );
  let total = 0;

  sorted.forEach((d) => {
    total += d.amount / 1e18;
  });

  console.log(total);
};

sortedData();
