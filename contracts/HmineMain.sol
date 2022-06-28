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

    address public management;
    address public bankroll;
    address rewardGiver;
    address public currencyToken;
    address public hmineToken;

    uint256 public startTime;
    uint256 public index;
    uint256 public totalSold = 100000e18;
    uint256 public totalStaked = 100000e18;
    uint256 public maxSupply = 200000e18;
    uint256 public currentPrice = 7e18; // The price is divisible by 100.  So in this case 7.00 is the current price.
    uint256 public roundIncrement = 1000e18;

    mapping(address => uint256) userIndex;
    mapping(uint256 => User) public users;

    constructor(
        address _management,
        address _bankroll,
        address _rewardGiver,
        address _currenctyToken,
        address _hmineToken
    ) {
        management = _management;
        bankroll = _bankroll;
        rewardGiver = _rewardGiver;
        currencyToken = _currenctyToken;
        hmineToken = _hmineToken;
    }

    // Initiate contract by sending HMINE to the contract then schedule the start time.
    // Will not initialize if already started.
    function initialize(uint256 _amount, uint256 time)
        external
        onlyOwner
        nonReentrant
    {
        require(time > startTime || startTime == 0, "Invalid start");
        require(block.timestamp < startTime, "Already started");
        IERC20(hmineToken).safeTransferFrom(msg.sender, address(this), _amount);
        startTime = time;
    }

    // An external function to calculate the buy price and selling price.
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

    // Input the amount a HMINE and return the MOR value.
    // Every 1000 represents a round.  For every round the price goes up 3 MOR.
    function getBuyValue(uint256 _amount)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 modTotal = totalSold % roundIncrement;
        uint256 value;
        uint256 _initPrice = currentPrice;
        uint256 _total = totalSold;

        // There are less than 100,000 sold even after this buy transaction.
        if (_total + _amount < 101000e18) {
            return ((7e18 * _amount) / 1e18, 7e18);
        }

        // Still in current round.
        if (_amount + modTotal < roundIncrement) {
            return ((currentPrice * _amount) / 1e18, _initPrice);
        }
        // Amount plus the mod total tells us tha the round or rounds will most likely be reached.
        else {
            uint256 modDiff = roundIncrement - modTotal;
            uint256 amountLeftOver = _amount - modDiff;
            value += (modDiff * currentPrice) / 1e18;

            uint256 amountMod = amountLeftOver % roundIncrement;
            uint256 _round = (amountLeftOver - amountMod) / roundIncrement;

            while (_round > 0) {
                _total += 1000e18;

                if (_total > 101000e18) {
                    _initPrice += 3e18;
                }

                value += (roundIncrement * _initPrice) / 1e18;
                _round = _round - 1;
            }

            if (amountMod > 0) {
                _total += amountMod;

                if (_total > 101000e18) {
                    _initPrice += 3e18;
                }

                value += (amountMod * _initPrice) / 1e18;
            }
        }
        return (value, _initPrice);
    }

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
        require(totalSold + _amount <= maxSupply, "Exceeded supply");

        (uint256 buyValue, uint256 _price) = getBuyValue(_amount);
        uint256 amountToStakers = (buyValue * 10) / 100;
        uint256 _stakeIndex = index;

        // Reward the stake holders
        while (_stakeIndex > 0) {
            users[_stakeIndex].reward +=
                (amountToStakers * users[_stakeIndex].amount) /
                totalStaked;
            _stakeIndex = _stakeIndex - 1;
        }

        // Update user's stake entry.
        uint256 _index = assignUserIndex(msg.sender);
        users[_index].amount += _amount;

        // Update global values.
        totalSold += _amount;
        totalStaked += _amount;
        currentPrice = _price;

        // Sends 10% to management
        IERC20(currencyToken).safeTransferFrom(
            msg.sender,
            management,
            (buyValue * 10) / 100
        );
        // Sends 80% to bankroll
        IERC20(currencyToken).safeTransferFrom(
            msg.sender,
            bankroll,
            (buyValue * 80) / 100
        );
    }

    // Sell HMINE for MOR
    function sell(uint256 _amount) external nonReentrant {
        (uint256 sellValue, uint256 _price) = getSellValue(_amount);
        // Sends HMINE to contract
        IERC20(hmineToken).safeTransferFrom(msg.sender, address(this), _amount);

        // Send MOR to user.  User only get's 60% of the selling price.
        IERC20(currencyToken).safeTransferFrom(
            msg.sender,
            address(this),
            (sellValue * 60) / 100
        );

        // Update global values.
        totalSold -= _amount;
        currentPrice = _price;
    }

    // Stake HMINE
    function stake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Invalid amount");
        uint256 _index = assignUserIndex(msg.sender);

        // Update user's staking amount
        users[_index].amount += _amount;
        // Update total staking amount
        totalStaked += _amount;

        // User sends HMINE to the contract to stake
        IERC20(currencyToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
    }

    // Unstake HMINE
    function unstake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Invalid amount");
        require(userIndex[msg.sender] != 0, "Not staked yet");

        uint256 _index = userIndex[msg.sender];

        require(
            users[_index].amount - _amount >= 0,
            "Inefficient stake balance"
        );

        // Update user's staking amount
        users[_index].amount -= _amount;

        // Update total staking amount
        totalStaked -= _amount;

        // Goes to burn address
        IERC20(currencyToken).safeTransfer(address(0), (_amount * 10) / 100);
        // Goes to bankroll
        IERC20(currencyToken).safeTransfer(bankroll, (_amount * 10) / 100);
        // User only gets 80%
        IERC20(currencyToken).safeTransfer(msg.sender, (_amount * 80) / 100);
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
        uint256 claimAmount = users[_index].reward;
        users[_index].reward = 0;
        IERC20(currencyToken).safeTransfer(msg.sender, claimAmount);
    }

    // Reward giver sends bonus DIV to top 20 holders
    function sendBonus() external nonReentrant {
        require(msg.sender == rewardGiver, "Unauthorized");
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
    function updateManagement(address _rewardGiver, address _management)
        external
        onlyOwner
    {
        rewardGiver = _rewardGiver;
        management = _management;
    }

    event Buy(
        address indexed _user,
        address indexed _nickname,
        uint256 _amount,
        uint256 _price,
        uint256 _round
    );

    event Sell(
        address indexed _user,
        address indexed _nickname,
        uint256 _amount,
        uint256 _price,
        uint256 _round
    );
}
