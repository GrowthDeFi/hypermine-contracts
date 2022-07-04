// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract HmineMain is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct User {
        string nickname;
        address user;
        uint256 amount;
        uint256 reward;
    }

    // dead address to receive "burnt" tokens
    address public constant FURNACE =
        0x000000000000000000000000000000000000dEaD;

    address[4] public management = [
        0x5C9dE63470D0D6d8103f7c83F1Be4F55998706FC, // 0 Loft
        0x2165fa4a32B9c228cD55713f77d2e977297D03e8, // 1 Ghost
        0x70F5FB6BE943162545a496eD120495B05dC5ce07, // 2 Mike
        0x36b13280500AEBC5A75EbC1e9cB9Bf1b6A78a95e // 3 Miko
    ];

    address public constant safeHolders =
        0xcD8dDeE99C0c4Be4cD699661AE9c00C69D1Eb4A8;

    address public bankroll = 0x25be1fcF5F51c418a0C30357a4e8371dB9cf9369; // 4 Way Multisig wallet
    address public rewardGiver = 0x2165fa4a32B9c228cD55713f77d2e977297D03e8; // Ghost
    address public immutable currencyToken; // Will likely be DAI
    address public immutable hmineToken;

    uint256 public startTime;
    uint256 public index;
    uint256 public totalSold; // The contract will start with 100,000 Sold HMINE.
    uint256 public totalStaked; // The contract will start with 100,000 Staked HMINE.
    uint256 public currentPrice = 7e18; // The price is divisible by 1e18.  So in this case 7.00 is the current price.
    uint256 public constant roundIncrement = 1_000e18;
    uint256 public rewardTotal;
    uint256 public constant maxSupply = 200_000e18;
    uint256 public constant firstRound = 100_000e18;
    uint256 public constant secondRound = 101_000e18;

    mapping(address => uint256) public userIndex;
    mapping(uint256 => User) public users;

    // The user's pending reward is user's balance multiplied by the accumulated reward per share minus the user's reward debt.
    // The user's reward debt is always set to balance multiplied by the accumulated reward per share when reward's are distributed
    // (or balance changes, which also forces distribution), such that the diference immediately after distribution is always zero (nothing left)
    uint256 public accRewardPerShare;
    mapping(address => uint256) public userRewardDebt;

    modifier onlyRewardGiver() {
        require(msg.sender == rewardGiver, "Unauthorized");
        _;
    }

    modifier isRunning(bool _flag) {
        require(
            (startTime != 0 && startTime <= block.timestamp) == _flag,
            "Unavailable"
        );
        _;
    }

    constructor(address _currenctyToken, address _hmineToken) {
        currencyToken = _currenctyToken;
        hmineToken = _hmineToken;
    }

    // Start the contract.
    // Will not initialize if already started.
    function initialize(uint256 _startTime)
        external
        onlyOwner
        isRunning(false)
    {
        startTime = _startTime;

        // Admin is supposed to send an additional 100k HMINE to the contract
        uint256 _balance = IERC20(hmineToken).balanceOf(address(this));
        require(_balance == maxSupply, "Missing hmine balance");
    }

    // Used to initally migrate the user data from the sacrifice round. Can be run multiple times. Do 10 at a time.
    function migrateSacrifice(User[] memory _users)
        external
        onlyOwner
        nonReentrant
        isRunning(false)
    {
        uint256 _amountSum = 0;
        uint256 _rewardSum = 0;
        for (uint256 _i = 0; _i < _users.length; _i++) {
            address _userAddress = _users[_i].user;
            require(_userAddress != address(0), "Invalid address");
            require(userIndex[_userAddress] == 0, "Duplicate user");
            uint256 _index = _assignUserIndex(_userAddress);
            users[_index] = _users[_i];
            _amountSum += _users[_i].amount;
            _rewardSum += _users[_i].reward;
        }

        // Admin sends send initial token deposits to the contract
        IERC20(hmineToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amountSum
        );
        totalSold += _amountSum;
        totalStaked += _amountSum;

        // Admin must send initial rewards to the contract
        IERC20(currencyToken).safeTransferFrom(
            msg.sender,
            address(this),
            _rewardSum
        );
        rewardTotal += _rewardSum;

        // Sanity check, pre-sale must not exceed 100k
        require(totalSold <= 100_000e18, "Migration excess");
    }

    // Total liquidity of HMINE available for trades.
    function hmineReserve() external view returns (uint256 _hmineReserve) {
        uint256 _balance = IERC20(hmineToken).balanceOf(address(this));
        return _balance - totalStaked;
    }

    // Total liquidity of DAI available for trades.
    function currencyReserve()
        external
        view
        returns (uint256 _currencyReserve)
    {
        uint256 _balance = IERC20(currencyToken).balanceOf(address(this));
        return _balance - rewardTotal;
    }

    // Allows for withdrawing DAI liquidity.
    // Admin is supposed to send the DAI liquidity directly to the contract.
    function recoverReserve(uint256 _amount) external onlyOwner nonReentrant {
        // Checks to make sure there is enough dai on contract to fullfill the withdrawal.
        uint256 _balance = IERC20(currencyToken).balanceOf(address(this));
        uint256 _available = _balance - rewardTotal;
        require(_amount <= _available, "Insufficient DAI on Contract");

        // Send DAI to user.  User only get's 60% of the selling price.
        IERC20(currencyToken).safeTransfer(msg.sender, _amount);
    }

    // An external function to calculate the swap value.
    // If it's a buy then calculate the amount of HMINE you get for the DAI input.
    // If it's a sell then calculate the amount of DAI you get for the HMINE input.
    function calculateSwap(uint256 _amount, bool _isBuy)
        external
        view
        returns (uint256 _value)
    {
        (_value, ) = _isBuy ? _getBuyValue(_amount) : _getSellValue(_amount);
        return _value;
    }

    // Input the amount a DAI and return the HMINE value.
    // It takes into account the price upscale in case a round has been met during the buy.
    function _getBuyValue(uint256 _amount)
        internal
        view
        returns (uint256 _hmineValue, uint256 _price)
    {
        _price = currentPrice;
        _hmineValue = (_amount * 1e18) / _price;
        // Fixed price if below second round
        if (totalSold + _hmineValue <= secondRound) {
            // Increment price if second round is reached
            if (totalSold + _hmineValue == secondRound) {
                _price += 3e18;
            }
        }
        // Price calculation when beyond the second round
        else {
            _hmineValue = 0;
            uint256 _amountLeftOver = _amount;
            uint256 _roundAvailable = roundIncrement -
                (totalSold % roundIncrement);

            // If short of first round, adjust up to first round
            if (totalSold < firstRound) {
                _hmineValue += firstRound - totalSold;
                _amountLeftOver -= (_hmineValue * _price) / 1e18;
                _roundAvailable = roundIncrement;
            }

            uint256 _valueOfLeftOver = (_amountLeftOver * 1e18) / _price;
            if (_valueOfLeftOver < _roundAvailable) {
                _hmineValue += _valueOfLeftOver;
            } else {
                _hmineValue += _roundAvailable;
                _amountLeftOver =
                    ((_valueOfLeftOver - _roundAvailable) * _price) /
                    1e18;
                _price += 3e18;
                while (_amountLeftOver > 0) {
                    _valueOfLeftOver = (_amountLeftOver * 1e18) / _price;
                    if (_valueOfLeftOver >= roundIncrement) {
                        _hmineValue += roundIncrement;
                        _amountLeftOver =
                            ((_valueOfLeftOver - roundIncrement) * _price) /
                            1e18;
                        _price += 3e18;
                    } else {
                        _hmineValue += _valueOfLeftOver;
                        _amountLeftOver = 0;
                    }
                }
            }
        }
        return (_hmineValue, _price);
    }

    // This internal function is used to calculate the amount of DAI user will receive.
    // It takes into account the price reversal in case rounds have reversed during a sell order.
    function _getSellValue(uint256 _amount)
        internal
        view
        returns (uint256 _sellValue, uint256 _price)
    {
        _price = currentPrice;
        uint256 _roundAvailable = totalSold % roundIncrement;
        // Still in current round.
        if (_amount <= _roundAvailable) {
            _sellValue = (_amount * _price) / 1e18;
        }
        // Amount plus the mod total tells us tha the round or rounds will most likely be reached.
        else {
            _sellValue = (_roundAvailable * _price) / 1e18;
            uint256 _amountLeftOver = _amount - _roundAvailable;
            while (_amountLeftOver > 0) {
                if (_price > 7e18) {
                    _price -= 3e18;
                }
                if (_amountLeftOver > roundIncrement) {
                    _sellValue += (roundIncrement * _price) / 1e18;
                    _amountLeftOver -= roundIncrement;
                } else {
                    _sellValue += (_amountLeftOver * _price) / 1e18;
                    _amountLeftOver = 0;
                }
            }
        }
        return (_sellValue, _price);
    }

    // Buy HMINE with DAI
    function buy(uint256 _amount) external nonReentrant isRunning(true) {
        require(_amount > 0, "Invalid amount");

        (uint256 _hmineValue, uint256 _price) = _getBuyValue(_amount);

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
        // Checks to make sure supply is not exeeded.
        require(totalSold + _hmineValue <= maxSupply, "Exceeded supply");

        // Sends 7.5% / 4 to Loft, Ghost, Mike, Miko
        uint256 _managementAmount = ((_amount * 75) / 1000) / 4;
        for (uint256 _i = 0; _i < 4; _i++) {
            IERC20(currencyToken).safeTransferFrom(
                _sender,
                management[_i],
                _managementAmount
            );
        }

        // Sends 2.5% to SafeHolders
        uint256 _safeHoldersAmount = (_amount * 25) / 1000;
        IERC20(currencyToken).safeTransferFrom(
            _sender,
            safeHolders,
            _safeHoldersAmount
        );

        // Sends 80% to bankroll
        uint256 _bankrollAmount = (_amount * 80) / 100;
        IERC20(currencyToken).safeTransferFrom(
            _sender,
            bankroll,
            _bankrollAmount
        );

        // Sends 10% to contract for divs
        uint256 _amountToStakers = _amount -
            (4 * _managementAmount + _safeHoldersAmount + _bankrollAmount);
        if (_sender != address(this)) {
            IERC20(currencyToken).safeTransferFrom(
                _sender,
                address(this),
                _amountToStakers
            );
        }

        _distributeRewards(_amountToStakers);

        // Update user's stake entry.
        uint256 _index = _assignUserIndex(msg.sender);
        users[_index].user = msg.sender; // just in case it was not yet initialized
        _collectsUserRewardAndUpdatesBalance(
            users[_index],
            int256(_hmineValue)
        );

        // Update global values.
        totalSold += _hmineValue;
        totalStaked += _hmineValue;
        currentPrice = _price;
        rewardTotal += _amountToStakers;
    }

    // Sell HMINE for DAI
    function sell(uint256 _amount) external nonReentrant isRunning(true) {
        require(_amount > 0, "Invalid amount");

        (uint256 _sellValue, uint256 _price) = _getSellValue(_amount);

        // Sends HMINE to contract
        IERC20(hmineToken).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 _60percent = (_sellValue * 60) / 100;

        // Checks to make sure there is enough dai on contract to fullfill the swap.
        uint256 _balance = IERC20(currencyToken).balanceOf(address(this));
        uint256 _available = _balance - rewardTotal;
        require(_60percent <= _available, "Insufficient DAI on Contract");

        // Send DAI to user.  User only get's 60% of the selling price.
        IERC20(currencyToken).safeTransfer(msg.sender, _60percent);

        // Update global values.
        totalSold -= _amount;
        currentPrice = _price;

        emit Sell(msg.sender, _amount, _price);
    }

    // Stake HMINE
    function stake(uint256 _amount) external nonReentrant isRunning(true) {
        require(_amount > 0, "Invalid amount");
        uint256 _index = _assignUserIndex(msg.sender);
        users[_index].user = msg.sender; // just in case it was not yet initialized

        // User sends HMINE to the contract to stake
        IERC20(hmineToken).safeTransferFrom(msg.sender, address(this), _amount);

        // Update user's staking amount
        _collectsUserRewardAndUpdatesBalance(users[_index], int256(_amount));
        // Update total staking amount
        totalStaked += _amount;
    }

    // Unstake HMINE
    function unstake(uint256 _amount) external nonReentrant isRunning(true) {
        require(_amount > 0, "Invalid amount");
        uint256 _index = userIndex[msg.sender];
        require(_index != 0, "Not staked yet");
        require(users[_index].amount >= _amount, "Inefficient stake balance");

        uint256 _10percent = (_amount * 10) / 100;
        uint256 _80percent = _amount - 2 * _10percent;

        // Goes to burn address
        IERC20(hmineToken).safeTransfer(FURNACE, _10percent);
        // Goes to bankroll
        IERC20(hmineToken).safeTransfer(bankroll, _10percent);
        // User only gets 80% HMINE
        IERC20(hmineToken).safeTransfer(msg.sender, _80percent);

        // Update user's staking amount
        _collectsUserRewardAndUpdatesBalance(users[_index], -int256(_amount));
        // Update total staking amount
        totalStaked -= _amount;
    }

    // Adds a nickname to the user.
    function updateNickname(string memory _nickname) external {
        uint256 _index = userIndex[msg.sender];
        require(index != 0, "User does not exist");
        users[_index].nickname = _nickname;
    }

    // Claim DIV as DAI
    function claim() external nonReentrant {
        uint256 _index = userIndex[msg.sender];
        require(index != 0, "User does not exist");
        _collectsUserRewardAndUpdatesBalance(users[_index], 0);
        uint256 _claimAmount = users[_index].reward;
        require(_claimAmount > 0, "No rewards to claim");
        rewardTotal -= _claimAmount;
        users[_index].reward = 0;
        IERC20(currencyToken).safeTransfer(msg.sender, _claimAmount);
    }

    // Compound the divs.
    // Uses the div to buy more HMINE internally by calling the _buyInternal.
    function compound() external nonReentrant isRunning(true) {
        uint256 _index = userIndex[msg.sender];
        require(index != 0, "User does not exist");
        _collectsUserRewardAndUpdatesBalance(users[_index], 0);
        uint256 _claimAmount = users[_index].reward;
        require(_claimAmount > 0, "No rewards to claim");
        // Removes the the claim amount from total divs for tracing purposes.
        rewardTotal -= _claimAmount;
        // remove the div from the users reward pool.
        users[_index].reward = 0;

        (uint256 _hmineValue, uint256 _price) = _getBuyValue(_claimAmount);

        _buyInternal(address(this), _claimAmount, _hmineValue, _price);

        emit Compound(msg.sender, _hmineValue, _price);
    }

    // Reward giver sends bonus DIV to top 20 holders
    function sendBonusDiv(
        uint256 _amount,
        address[] memory _topTen,
        address[] memory _topTwenty
    ) external onlyRewardGiver nonReentrant isRunning(true) {
        require(_amount > 0, "Invalid amount");

        // Admin sends div to the contract
        IERC20(currencyToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        require(
            _topTen.length == 10 && _topTwenty.length == 10,
            "Invalid arrays"
        );

        // 75% split between topTen
        uint256 _topTenAmount = ((_amount * 75) / 100) / 10;
        // 25% split between topTwenty
        uint256 _topTwentyAmount = ((_amount * 25) / 100) / 10;

        for (uint256 _i = 0; _i < 10; _i++) {
            uint256 _index = userIndex[_topTen[_i]];
            require(_index != 0, "A user doesn't exist");
            users[_index].reward += _topTenAmount;
        }

        for (uint256 _i = 0; _i < 10; _i++) {
            uint256 _index = userIndex[_topTwenty[_i]];
            require(_index != 0, "A user doesn't exist");
            users[_index].reward += _topTwentyAmount;
        }

        uint256 _leftOver = _amount - 10 * (_topTenAmount + _topTwentyAmount);
        users[userIndex[_topTen[0]]].reward += _leftOver;

        rewardTotal += _amount;

        emit BonusReward(_amount);
    }

    // Reward giver sends daily divs to all holders
    function sendDailyDiv(uint256 _amount)
        external
        onlyRewardGiver
        nonReentrant
        isRunning(true)
    {
        require(_amount > 0, "Invalid amount");

        // Admin sends div to the contract
        IERC20(currencyToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );

        _distributeRewards(_amount);

        rewardTotal += _amount;
    }

    // Calculates actual user reward balance
    function userRewardBalance(address _userAddress)
        external
        view
        returns (uint256 _reward)
    {
        User storage _user = users[userIndex[_userAddress]];
        // The difference is the user's share of rewards distributed since the last collection
        uint256 _newReward = (_user.amount * accRewardPerShare) /
            1e12 -
            userRewardDebt[_user.user];
        return _user.reward + _newReward;
    }

    // Distributes reward amount to all users propotionally to their stake.
    function _distributeRewards(uint256 _amount) internal {
        accRewardPerShare += (_amount * 1e12) / totalStaked;
    }

    // Collects pending rewards and updates user balance.
    function _collectsUserRewardAndUpdatesBalance(
        User storage _user,
        int256 _amountDelta
    ) internal {
        // The difference is the user's share of rewards distributed since the last collection/reset
        uint256 _newReward = (_user.amount * accRewardPerShare) /
            1e12 -
            userRewardDebt[_user.user];
        _user.reward += _newReward;
        if (_amountDelta >= 0) {
            _user.amount += uint256(_amountDelta);
        } else {
            _user.amount -= uint256(-_amountDelta);
        }
        // Resets user's reward debt so that the difference is zero
        userRewardDebt[_user.user] = (_user.amount * accRewardPerShare) / 1e12;
    }

    // Show user by address
    function getUserByAddress(address _userAddress)
        external
        view
        returns (User memory _user)
    {
        return users[userIndex[_userAddress]];
    }

    // Show user by index
    function getUserByIndex(uint256 _index)
        external
        view
        returns (User memory _user)
    {
        return users[_index];
    }

    // Takes in a user address and finds an existing index that is corelated to the user.
    // If index not found (ZERO) then it assigns an index to the user.
    function _assignUserIndex(address _user) internal returns (uint256 _index) {
        if (userIndex[_user] == 0) userIndex[_user] = ++index;
        return userIndex[_user];
    }

    // Updates the management and reward giver address.
    function updateStateAddresses(address _rewardGiver, address _bankRoll)
        external
        onlyOwner
    {
        require(
            _bankRoll != address(0) && _bankRoll != address(this),
            "Invalid address"
        );
        require(
            _rewardGiver != address(0) && _rewardGiver != address(this),
            "Invalid address"
        );
        bankroll = _bankRoll;
        rewardGiver = _rewardGiver;
    }

    // Updates the management.
    function updateManagement(address _management, uint256 _i)
        external
        onlyOwner
    {
        require(
            _management != address(0) && _management != address(this),
            "Invalid address"
        );
        require(_i < 4, "Invalid entry");
        management[_i] = _management;
    }

    event Buy(address indexed _user, uint256 _amount, uint256 _price);
    event Sell(address indexed _user, uint256 _amount, uint256 _price);
    event Compound(address indexed _user, uint256 _amount, uint256 _price);
    event BonusReward(uint256 _amount);
}
