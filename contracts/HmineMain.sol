// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract HmineSacrifice is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct User {
        string nickname;
        address user;
        uint256 amount;
        uint256 reward;
    }

    address management0 = 0x5C9dE63470D0D6d8103f7c83F1Be4F55998706FC;
    address management1 = 0x2165fa4a32B9c228cD55713f77d2e977297D03e8;
    address management2 = 0x70F5FB6BE943162545a496eD120495B05dC5ce07;
    address management3 = 0x36b13280500AEBC5A75EbC1e9cB9Bf1b6A78a95e;
    address safeHolders = 0xcD8dDeE99C0c4Be4cD699661AE9c00C69D1Eb4A8;
    address public bankroll;
    address rewardGiver;
    address public currencyToken; // Will likely be DAI
    address public hmineToken;

    uint256 public startTime;
    uint256 public index;
    uint256 public totalSold = 100000e18; // The contract will start with 100,000 Sold HMINE.
    uint256 public totalStaked = 100000e18; // The contract will start with 100,000 Staked HMINE.
    uint256 public currentPrice = 7e18; // The price is divisible by 1e18.  So in this case 7.00 is the current price.
    uint256 public roundIncrement = 1000e18;
    uint256 public rewardTotal;
    uint256 maxSupply = 200000e18;
    uint256 maxValue = 16250000e18;
    uint256 firstRound = 100000e18;
    uint256 secondRound = 101000e18;
    uint256 migrateTime;

    mapping(address => uint256) userIndex;
    mapping(uint256 => User) public users;

    constructor(
        address _bankroll,
        address _rewardGiver,
        address _currenctyToken,
        address _hmineToken
    ) {
        bankroll = _bankroll;
        rewardGiver = _rewardGiver;
        currencyToken = _currenctyToken;
        hmineToken = _hmineToken;
    }

    // Start the contract.  
    // Will not initialize if already started.
    function initialize(uint256 time)
        external
        onlyOwner
        nonReentrant
    {
        require(time > startTime || startTime == 0, "Invalid start");
        startTime = time;
    }

    // Used to initally migrate the user data from the sacrifice round. Can only be run once.
    function migrateSacrifice(User[] memory _users, uint256 userLength)
        external
        onlyOwner
    {
        require(migrateTime == 0, "Already migrated");
        migrateTime = block.timestamp;
        uint256 counter;
        //Work in progress
        while (counter < userLength) {
            uint256 _index = assignUserIndex(msg.sender);
            users[_index] = _users[counter];

            rewardTotal += _users[counter].reward;
            counter += 1;
        }
    }

    // An external function to calculate the swap value.
    // If it's a buy then calculate the amount of HMINE you get for the DAI input.
    //If it's a sell then calculate the amount of DAI you get for the HMINE input.
    function calculateSwap(uint256 _amount, bool isBuy)
        external
        view
        returns (uint256)
    {
        if (isBuy) {
            (uint256 _val, ) = getBuyValue(_amount);
            return _val;
        } else {
            (uint256 _val, ) = getSellValue(_amount);
            return _val;
        }
    }

    // Input the amount a MOR and return the HMINE value.
    // It takes into account the price upscale in case a round has been met during the buy.
    function getBuyValue(uint256 _amount)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 hmineValue;
        uint256 _initPrice = currentPrice / 1e18;
        uint256 _total = totalSold;
        uint256 amountLeftOver = _amount;

        if (_total + amountLeftOver / _initPrice < secondRound)
            return (amountLeftOver / _initPrice, currentPrice);
        if (_total + amountLeftOver / _initPrice == secondRound)
            return (amountLeftOver / _initPrice, 10e18);

        if (totalSold < firstRound) {
            uint256 initDiff = firstRound - totalSold;
            uint256 amountDiff = amountLeftOver / _initPrice - initDiff;
            hmineValue += initDiff;
            amountLeftOver = amountDiff * _initPrice;
            _total = 0;
        } else {
            _total -= firstRound;
        }

        uint256 modTotal = _total % roundIncrement;
        uint256 modDiff = roundIncrement - modTotal;

        if (amountLeftOver / _initPrice < modDiff)
            return (hmineValue + amountLeftOver / _initPrice, currentPrice);

        amountLeftOver = (amountLeftOver / _initPrice - modDiff) * _initPrice;
        hmineValue += modDiff;
        _initPrice += 3;

        while (amountLeftOver != 0) {
            if (amountLeftOver / _initPrice >= roundIncrement) {
                amountLeftOver =
                    (amountLeftOver / _initPrice - roundIncrement) *
                    _initPrice;
                hmineValue += roundIncrement;
                _initPrice += 3;
            } else {
                hmineValue += amountLeftOver / _initPrice;
                amountLeftOver = 0;
            }
        }

        return (hmineValue, _initPrice * 1e18);
    }

    // This internal function is used to calculate the amount of DAI user will receive.
    // It takes into account the price reversal in case rounds have reversed during a sell order.
    function getSellValue(uint256 _amount)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 modTotal = totalSold % roundIncrement;
        uint256 value;
        uint256 _initPrice = currentPrice;

        // Still in current round.
        if (_amount <= modTotal) {
            return ((currentPrice * _amount) / 1e18, _initPrice);
        }
        // Amount plus the mod total tells us tha the round or rounds will most likely be reached.
        else {
            uint256 modDiff = modTotal;
            uint256 amountLeftOver = _amount - modDiff;
            value += (modDiff * currentPrice) / 1e18;

            while (amountLeftOver > 0) {
                if (_initPrice > 7e18) {
                    _initPrice -= 3e18;
                }

                if (amountLeftOver > roundIncrement) {
                    value += (roundIncrement * _initPrice) / 1e18;
                    amountLeftOver -= roundIncrement;
                } else {
                    value += (amountLeftOver * _initPrice) / 1e18;
                    amountLeftOver = 0;
                }
            }

            return (value, _initPrice);
        }
    }

    // Buy HMINE with MOR
    function buy(uint256 _amount) external nonReentrant {
        require(
            startTime != 0 && block.timestamp >= startTime,
            "Not started yet"
        );
        require(_amount > 0, "Invalid amount");
        (uint256 _hmineValue, uint256 _price) = getBuyValue(_amount);
        //Checks to make sure supply is not exeeded.
        require(totalSold + _hmineValue <= maxSupply, "Exceeded supply");

        // Sends 10% to contract for divs
        IERC20(currencyToken).safeTransferFrom(
            msg.sender,
            address(this),
            (_amount * 10) / 100
        );

        // Used to send funds to the appropriate wallets and update global data
        _buyInternal(msg.sender, _amount, _hmineValue, _price);

        emit Buy(msg.sender, _hmineValue, _price);
    }

    // Used to send funds to the appropriate wallets and update global data
    // The buy and compound function calls this internal function.
    function _buyInternal(
        address _sender,
        uint256 _amount,
        uint256 _hmineValue,
        uint256 _price
    ) internal {
        uint256 amountToStakers = (_amount * 10) / 100;
        uint256 _stakeIndex = index;

        // Sends 7.5% / 4 to Loft
        IERC20(currencyToken).safeTransferFrom(
            _sender,
            management0,
            (_amount * 750) / 4000
        );
        // Sends 7.5% / 4 to Ghost
        IERC20(currencyToken).safeTransferFrom(
            _sender,
            management1,
            (_amount * 750) / 4000
        );
        // Sends 7.5% / 4 to Mike
        IERC20(currencyToken).safeTransferFrom(
            _sender,
            management2,
            (_amount * 750) / 4000
        );
        // Sends 7.5% / 4 to Miko
        IERC20(currencyToken).safeTransferFrom(
            _sender,
            management3,
            (_amount * 750) / 4000
        );

        // Sends 2.5% to SafeHolders
        IERC20(currencyToken).safeTransferFrom(
            _sender,
            management0,
            (_amount * 250) / 1000
        );

        // Sends 80% to bankroll
        IERC20(currencyToken).safeTransferFrom(
            _sender,
            bankroll,
            (_amount * 80) / 100
        );

        // Reward the stake holders
        while (_stakeIndex > 0) {
            users[_stakeIndex].reward +=
                (amountToStakers * users[_stakeIndex].amount) /
                totalStaked;
            _stakeIndex = _stakeIndex - 1;
        }

        // Update user's stake entry.
        uint256 _index = assignUserIndex(msg.sender);
        users[_index].amount += _hmineValue;
        users[_index].user = msg.sender;

        // Update global values.
        totalSold += _hmineValue;
        totalStaked += _hmineValue;
        currentPrice = _price;
        rewardTotal += amountToStakers;
    }

    // Sell HMINE for MOR
    function sell(uint256 _amount) external nonReentrant {
        require(
            startTime != 0 && block.timestamp >= startTime,
            "Not started yet"
        );
        require(_amount > 0, "Invalid amount");
        (uint256 sellValue, uint256 _price) = getSellValue(_amount);
        // Sends HMINE to contract
        IERC20(hmineToken).safeTransferFrom(msg.sender, address(this), _amount);

        // Checks to make sure there is enough dai on contract to fullfill the swap.
        require(
            IERC20(currencyToken).balanceOf(address(this)) -
                (sellValue * 60) /
                100 >=
                rewardTotal,
            "Insufficient DAI on Contract"
        );

        // Send MOR to user.  User only get's 60% of the selling price.
        IERC20(currencyToken).safeTransferFrom(
            msg.sender,
            address(this),
            (sellValue * 60) / 100
        );

        // Update global values.
        totalSold -= _amount;
        currentPrice = _price;

        emit Sell(msg.sender, _amount, currentPrice);
    }

    // Stake HMINE
    function stake(uint256 _amount) external nonReentrant {
        require(
            startTime != 0 && block.timestamp >= startTime,
            "Not started yet"
        );
        require(_amount > 0, "Invalid amount");
        uint256 _index = assignUserIndex(msg.sender);

        // User sends HMINE to the contract to stake
        IERC20(hmineToken).safeTransferFrom(msg.sender, address(this), _amount);

        // Update user's staking amount
        users[_index].amount += _amount;
        // Update total staking amount
        totalStaked += _amount;
    }

    // Unstake HMINE
    function unstake(uint256 _amount) external nonReentrant {
        require(
            startTime != 0 && block.timestamp >= startTime,
            "Not started yet"
        );
        require(_amount > 0, "Invalid amount");
        require(userIndex[msg.sender] != 0, "Not staked yet");

        uint256 _index = userIndex[msg.sender];

        require(users[_index].amount >= _amount, "Inefficient stake balance");

        require(_amount > 0, "Invalid amount");

        // Goes to burn address
        IERC20(hmineToken).safeTransfer(address(0), (_amount * 10) / 100);
        // Goes to bankroll
        IERC20(hmineToken).safeTransfer(bankroll, (_amount * 10) / 100);
        // User only gets 80% HMINE
        IERC20(hmineToken).safeTransfer(msg.sender, (_amount * 80) / 100);

        // Update user's staking amount
        users[_index].amount -= _amount;
        // Update total staking amount
        totalStaked -= _amount;
    }

    // Adds a nickname to the user.
    function updateNickname(string memory nickname) external {
        uint256 _index = userIndex[msg.sender];
        require(index != 0, "User does not exist");
        users[_index].nickname = nickname;
    }

    // Claim DIV as MOR
    function claim() external {
        uint256 _index = userIndex[msg.sender];
        require(users[_index].reward != 0, "No rewards to claim");
        uint256 claimAmount = users[_index].reward;
        rewardTotal -= users[_index].reward;
        users[_index].reward = 0;
        IERC20(currencyToken).safeTransfer(msg.sender, claimAmount);
    }

    // Compound the divs.
    // Uses the div to buy more HMINE internally by calling the _buyInternal.
    function compound() external {
        uint256 _index = userIndex[msg.sender];
        require(users[_index].reward != 0, "No rewards to claim");
        uint256 claimAmount = users[_index].reward;

        // Removes the the claim amount from total divs for tracing purposes.
        rewardTotal -= claimAmount;
        // remove the div from the users reward pool.
        users[_index].reward = 0;

        //WIP
        (uint256 _hmineValue, uint256 _price) = getBuyValue(claimAmount);
        _buyInternal(address(this), claimAmount, _hmineValue, _price);
        emit Compound(msg.sender, claimAmount, _price);
    }

    // Reward giver sends bonus DIV to top 20 holders
    function sendBonusDiv(
        uint256 _amount,
        address[] memory _topTen,
        address[] memory _topTwenty
    ) external nonReentrant {
        require(msg.sender == rewardGiver, "Unauthorized");
        require(_amount > 0, "Invalid amount");

        // Admin sends div to the contract
        IERC20(currencyToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        uint256 topTenLength = _topTen.length;
        uint256 topTwentyLength = _topTwenty.length;
        require(topTenLength == 10 && topTwentyLength == 10, "Invalid arrays");

        uint256 topTenAmount = (_amount * 75) / 1000;
        uint256 topTwentyAmount = (_amount * 25) / 1000;

        uint256 counter;
        while (counter < 10) {
            uint256 _index = userIndex[_topTen[counter]];
            require(_index != 0, "A user doesn't exist. ");
            users[_index].reward += topTenAmount;
        }

        counter = 0;
        while (counter < 10) {
            uint256 _index = userIndex[_topTwenty[counter]];
            require(_index != 0, "A user doesn't exist. ");
            users[_index].reward += topTwentyAmount;
        }

        rewardTotal += _amount;

        emit BonusReward(_amount);
    }

    // Reward giver sends daily divs to all holders
    function sendDailyDiv(uint256 _amount) external nonReentrant {
        require(msg.sender == rewardGiver, "Unauthorized");
        require(_amount > 0, "Invalid amount");

        // Admin sends div to the contract
        IERC20(currencyToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        uint256 _stakeIndex = index;

        // Reward the stake holders
        while (_stakeIndex > 0) {
            users[_stakeIndex].reward +=
                (_amount * users[_stakeIndex].amount) /
                totalStaked;
            _stakeIndex = _stakeIndex - 1;
        }

        rewardTotal += _amount;
    }

    // Show user by address
    function getUserByAddress(address _userAddress)
        external
        view
        returns (User memory _user)
    {
        uint256 _index = userIndex[_userAddress];
        _user = users[_index];
    }

    // Show user by index
    function getUserByIndex(uint256 _index)
        external
        view
        returns (User memory)
    {
        return users[_index];
    }

    // Takes in a user address and finds an existing index that is corelated to the user.
    // If index not found (ZERO) then it assigns an index to the user.
    function assignUserIndex(address _user) internal returns (uint256) {
        if (userIndex[_user] == 0) userIndex[_user] = ++index;
        return userIndex[_user];
    }

    // Updates the management and reward giver address.
    function updateRewardGiver(address _rewardGiver, address _bankRoll)
        external
        onlyOwner
    {
        require(
            _bankRoll != address(0) &&
                _bankRoll != address(this) &&
                _rewardGiver != address(0) &&
                _rewardGiver != address(this),
            "Invalid addresses"
        );
        bankroll = _bankRoll;
        rewardGiver = _rewardGiver;
    }

    // Updates the management.
    function updateManagement(address _management, uint256 _mgr)
        external
        onlyOwner
    {
        require(_mgr < 4 && _mgr >= 0, "Invalid entry");
        require(_management != address(0) && _management != address(this));
        if (_mgr == 0) {
            management0 = _management;
        } else if (_mgr == 1) {
            management1 = _management;
        } else if (_mgr == 2) {
            management2 = _management;
        } else {
            management3 = _management;
        }
    }

    event Buy(address indexed _user, uint256 _amount, uint256 _price);

    event Sell(address indexed _user, uint256 _amount, uint256 _price);

    event Compound(address indexed _user, uint256 _amount, uint256 _price);

    event BonusReward(uint256 _amount);
}
