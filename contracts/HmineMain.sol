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
        uint amount;
        uint reward;
    }

    address public management;
    address public bankroll; 
    address rewardGiver; 
    address public currencyToken;
    address public hmineToken;

    uint public startTime; 
    uint public index;
    uint public totalSold = 100000e18; 
    uint public totalStaked = 100000e18; 
    uint public maxSupply = 200000e18; 
    uint public currentPrice = 7e18; // The price is divisible by 100.  So in this case 7.00 is the current price. 
    uint public roundIncrement = 1000e18;

    mapping(address => uint) userIndex;
    mapping(uint => User) public users;

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
    function initialize(uint _amount, uint time) external onlyOwner nonReentrant {
        require(time > startTime || startTime == 0,  "Invalid start");
        require(block.timestamp < startTime, "Already started");
        IERC20(hmineToken).safeTransferFrom(msg.sender, address(this), _amount);
        startTime = time;
    }    

    // An external function to calculate the buy price and selling price.  
    function calculateSwap(uint _amount, bool isBuy) external view returns(uint){
        if(isBuy){
            (uint _val,) = getBuyValue(_amount);
            return _val;
        }
        else {
            (uint _val,) = getSellValue(_amount);
            return _val;
        }
    }

    // Input the amount a HMINE and return the MOR value. 
    // Every 1000 represents a round.  For every round the price goes up 3 MOR. 
    function getBuyValue(uint _amount) internal view returns (uint, uint) {
        uint modTotal = totalSold % roundIncrement;
        uint value;
        uint _initPrice = currentPrice;
        
        // Still in current round.
        if(_amount + modTotal < roundIncrement){
            return (currentPrice * _amount / 1e18, _initPrice);
        }

        // Amount plus the mod total tells us tha the round or rounds will most likely be reached. 
        else {
            uint modDiff = roundIncrement - modTotal; 
            uint amountLeftOver = _amount - modDiff; 
            value += modDiff * currentPrice / 1e18; 

            uint amountMod = amountLeftOver % roundIncrement;
            uint _round = (amountLeftOver - amountMod) / roundIncrement; 


            while(_round > 0){
                _initPrice += 3e18;
                value += roundIncrement * _initPrice / 1e18;
                _round = _round - 1; 
            }

            if(amountMod > 0){
                _initPrice += 3e18;
                value += amountMod * _initPrice / 1e18;
            }
        }
        return (value, _initPrice);
    }

    function getSellValue(uint _amount) internal view returns (uint, uint) {
        uint modTotal = totalSold % roundIncrement;
        uint value;
        uint _initPrice = currentPrice;
        
        // Still in current round.
        if(_amount <= modTotal){
            return (currentPrice * _amount / 1e18, _initPrice);
        }

        // Amount plus the mod total tells us tha the round or rounds will most likely be reached. 
        else {
            uint modDiff = modTotal; 
            uint amountLeftOver = _amount - modDiff; 
            value += modDiff * currentPrice / 1e18; 

            while(amountLeftOver > 0){

                if(_initPrice > 7e18){
                    _initPrice -= 3e18;
                }

                if(amountLeftOver > roundIncrement){
                    value += roundIncrement * _initPrice / 1e18;
                    amountLeftOver -= roundIncrement;
                }
                else {
                    value += amountLeftOver * _initPrice / 1e18;
                    amountLeftOver = 0;
                }
            }

            return (value, _initPrice);
        }
    }

    // Buy HMINE with MOR
    function buy(uint _amount) external nonReentrant {
        require(totalSold + _amount <= maxSupply, "Exceeded supply");

        (uint buyValue, uint _price) = getBuyValue(_amount);
        uint amountToStakers = buyValue * 10 / 100;
        uint _stakeIndex = index;

        // Reward the stake holders
        while(_stakeIndex > 0){
            users[_stakeIndex].reward += amountToStakers * users[_stakeIndex].amount / totalStaked;
            _stakeIndex = _stakeIndex - 1; 
        }

        // Update user's stake entry. 
        uint _index = assignUserIndex(msg.sender);
        users[_index].amount += _amount;

        // Update global values.
        totalSold += _amount;
        totalStaked += _amount;
        currentPrice = _price;

        // Sends 10% to management
        IERC20(currencyToken).safeTransferFrom(msg.sender, management, buyValue * 10 / 100);
        // Sends 80% to bankroll
        IERC20(currencyToken).safeTransferFrom(msg.sender, bankroll, buyValue * 80 / 100);
    }


    // Sell HMINE for MOR
    function sell(uint _amount) external  nonReentrant{
        (uint sellValue, uint _price) = getSellValue(_amount);
        // Sends HMINE to contract
        IERC20(hmineToken).safeTransferFrom(msg.sender, address(this), _amount);

        // Send MOR to user.  User only get's 60% of the selling price. 
        IERC20(currencyToken).safeTransferFrom(msg.sender, address(this), sellValue * 60 / 100);

        // Update global values.
        totalSold -= _amount;
        currentPrice = _price;
    }

    // Stake HMINE
    function stake(uint _amount) external nonReentrant {
        require(_amount > 0, "Invalid amount");
        uint _index = assignUserIndex(msg.sender);

        // Update user's staking amount
        users[_index].amount += _amount;
        // Update total staking amount 
        totalStaked += _amount;

        // User sends HMINE to the contract to stake
        IERC20(currencyToken).safeTransferFrom(msg.sender, address(this), _amount);
    }

    // Unstake HMINE
    function unstake(uint _amount) external nonReentrant {
        require(_amount > 0, "Invalid amount");
        require(userIndex[msg.sender] != 0, "Not staked yet");

        uint _index = userIndex[msg.sender];

        require(users[_index].amount - _amount >= 0, "Inefficient stake balance");

        // Update user's staking amount
        users[_index].amount -= _amount;

        // Update total staking amount 
        totalStaked -= _amount;

        // Goes to burn address
        IERC20(currencyToken).safeTransfer(address(0),  _amount * 10 / 100);
        // Goes to bankroll
        IERC20(currencyToken).safeTransfer(bankroll, _amount * 10 / 100);
        // User only gets 80%
        IERC20(currencyToken).safeTransfer(msg.sender,  _amount * 80 / 100);
    }

    // Adds a nickname to the user. 
    function updateNickname(string memory nickname) external {
        uint256 _index = userIndex[msg.sender];
        require(index != 0, "User does not exist");
        users[_index].nickname = nickname;
    }

    // Claim DIV as MOR
    function claim() external {
        uint _index = userIndex[msg.sender];
        uint claimAmount = users[_index].reward; 
        users[_index].reward = 0;
        IERC20(currencyToken).safeTransfer(msg.sender, claimAmount);
    }


    // Reward giver sends bonus DIV to top 20 holders
    function sendBonus() external nonReentrant {
        require(msg.sender == rewardGiver, "Unauthorized");
    }

    // Show user by address
    function getUserByAddress(address _userAddress) external view returns (User memory _user) {
        uint _index = userIndex[_userAddress];  
        _user = users[_index];
    }


    // Show user by index 
    function getUserByIndex(uint _index) external view returns (User memory) {
        return users[_index];
    }

    // Takes in a user address and finds an existing index that is corelated to the user.
    // If index not found (ZERO) then it assigns an index to the user.
    function assignUserIndex(address _user) internal returns (uint256) {
        if (userIndex[_user] == 0) userIndex[_user] = ++index;
        return userIndex[_user];
    }

    // Updates the management and reward giver address. 
    function updateManagement(address _rewardGiver, address _management) external onlyOwner {
        rewardGiver = _rewardGiver; 
        management = _management;
    }


    event Buy(
        address indexed _user,
        address indexed _nickname,
        uint _amount,
        uint _price, 
        uint _round
    );


    event Sell(
        address indexed _user,
        address indexed _nickname,
        uint _amount,
        uint _price, 
        uint _round
    );

}