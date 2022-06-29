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
    uint256 public currentPrice = 7e18; // The price is divisible by 100.  So in this case 7.00 is the current price.
    uint256 public roundIncrement = 1000e18;
    uint256 maxSupply = 200000e18;
    uint maxValue = 16250000e18;
    uint firstRound = 100000e18;
    uint secondRound = 101000e18;
    uint migrateTime;

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

    // Used to initally migrate the user data from the sacrifice round. Can only be run once. 
    function migrateSacrifice(User[] memory _users, uint userLength) external onlyOwner {
        require(migrateTime == 0, "Already migrated");
        migrateTime = block.timestamp;
        uint counter; 
        //Work in progress
        while(counter < userLength){
            uint256 _index = assignUserIndex(msg.sender);
            users[_index] = _users[counter];
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

    // Input the amount a HMINE and return the MOR value.
    // Every 1000 represents a round.  For every round the price goes up 3 MOR.
    function getBuyValue(uint256 _amount)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 hmineValue;
        uint256 _initPrice = currentPrice / 1e18;
        uint256 _total = totalSold;
        uint256 amountLeftOver = _amount;

        if(_total + amountLeftOver / _initPrice < secondRound) return (amountLeftOver / _initPrice, currentPrice);
        if(_total + amountLeftOver / _initPrice == secondRound) return (amountLeftOver / _initPrice, 10e18);

        if(totalSold < firstRound){
            uint initDiff = firstRound - totalSold; 
            uint amountDiff = amountLeftOver / _initPrice - initDiff;
            hmineValue += initDiff;
            amountLeftOver = amountDiff * _initPrice;
            _total = 0;
        }

        else {
            _total -= firstRound;
        }

        uint256 modTotal = _total % roundIncrement;
        uint256 modDiff = roundIncrement - modTotal;

        if(amountLeftOver / _initPrice < modDiff) return (hmineValue + amountLeftOver / _initPrice, currentPrice);

        amountLeftOver = (amountLeftOver / _initPrice - modDiff) * _initPrice;
        hmineValue += modDiff;
        _initPrice += 3;

        while(amountLeftOver != 0){
            if(amountLeftOver / _initPrice >= roundIncrement){
                amountLeftOver = (amountLeftOver / _initPrice - roundIncrement) * _initPrice;
                hmineValue += roundIncrement;
                _initPrice += 3; 
            }
            else {
                hmineValue += amountLeftOver / _initPrice;
                amountLeftOver = 0;
            }
        }
  
        return (hmineValue, _initPrice * 1e18);
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

        (uint256 hmineValue, uint256 _price) = getBuyValue(_amount);
        require(totalSold + hmineValue <= maxSupply, "Exceeded supply");

        uint256 amountToStakers = (_amount * 10) / 100;
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
        users[_index].amount += hmineValue;

        // Update global values.
        totalSold += hmineValue;
        totalStaked += hmineValue;
        currentPrice = _price;

        // Sends 10% to management
        IERC20(currencyToken).safeTransferFrom(
            msg.sender,
            management,
            (_amount * 10) / 100
        );
        // Sends 80% to bankroll
        IERC20(currencyToken).safeTransferFrom(
            msg.sender,
            bankroll,
            (_amount * 80) / 100
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
    function sendBonusDiv() external nonReentrant {
        require(msg.sender == rewardGiver, "Unauthorized");
        // Work in progress
    }

    // Reward giver sends bonus DIV to top 20 holders
    function sendDailyDiv() external nonReentrant {
        require(msg.sender == rewardGiver, "Unauthorized");
        // Work in progress
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
