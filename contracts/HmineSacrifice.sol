// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./interfaces/IOraclePair.sol";
import "./interfaces/IOracleTwap.sol";

struct Sacrifice {
    bool isEnabled;
    bool isStable;
    address oracleAddress;
}

struct User {
    string nickname;
    address user;
    uint256 amount;
}

contract HmineSacrifice is Ownable, ReentrancyGuard {
    mapping(address => Sacrifice) public sacrifices;
    uint256 public startTime;
    uint256 public roundPeriod = 48 hours;
    uint256 public hminePerRound = 50000e18; //Hmine per round is 50K
    uint256 public totalHmine;
    uint256 public initPrice = 600; // The price is dvisible by 100.  So in this case 600 is actually $6.00
    uint256 index = 0;
    mapping(address => uint256) userIndex;
    mapping(uint256 => User) public users;
    address public sacrificesTo;
    address public wbnb;
    address public twap;
    uint256 public twapMax = 30;

    constructor(
        address _sacTo,
        address _wbnb,
        address _bnbLP,
        address _twap
    ) {
        sacrificesTo = _sacTo;
        wbnb = _wbnb;
        twap = _twap;
        _addSac(_wbnb, false, _bnbLP);
    }

    function getSacrificeInfo(address _token)
        external
        view
        returns (Sacrifice memory)
    {
        return sacrifices[_token];
    }

    function updateRoundMax(uint256 _max) external onlyOwner {
        require(startTime == 0, "Cannot update after round started");
        hminePerRound = _max;
    }

    function sacrificeERC20(address _token, uint256 _amount)
        public
        nonReentrant
    {
        require(hasSacrifice(_token), "Sacrifice not supported. ");
        require(_amount > 0, "Amount cannot be less than zero");

        uint256 _hmineAmount;
        uint256 price = initPrice;

        if (
            totalHmine >= hminePerRound ||
            block.timestamp > startTime + (roundPeriod)
        ) {
            price = initPrice + (50);
        }

        if (sacrifices[_token].isStable) {
            _hmineAmount = (_amount * (100)) / (price);
        } else {
            _hmineAmount =
                (getAmountInStable(
                    _token,
                    sacrifices[_token].oracleAddress,
                    _amount
                ) * 100) /
                (price);
        }

        require(
            validateRound(_hmineAmount),
            "Round ended or not started yet. "
        );

        uint256 _index = assignUserIndex(msg.sender);
        users[_index].user = msg.sender;
        users[_index].amount = _hmineAmount + (users[_index].amount);
        totalHmine = _hmineAmount + (totalHmine);
        SafeERC20.safeTransferFrom(
            IERC20(_token),
            msg.sender,
            sacrificesTo,
            _amount
        );
    }

    function sacrificeBNB() public payable nonReentrant {
        uint256 _amount = msg.value;
        require(hasSacrifice(wbnb), "Sacrifice not supported. ");
        require(_amount > 0, "Amount cannot be less than zero");

        uint256 _hmineAmount;
        uint256 price = initPrice;

        if (
            totalHmine >= hminePerRound ||
            block.timestamp > startTime + (roundPeriod)
        ) {
            price = initPrice + (50);
        }

        _hmineAmount =
            (getAmountInStable(wbnb, sacrifices[wbnb].oracleAddress, _amount) *
                100) /
            (price);

        require(
            validateRound(_hmineAmount),
            "Round ended or not started yet. "
        );

        uint256 _index = assignUserIndex(msg.sender);
        users[_index].user = msg.sender;
        users[_index].amount = _hmineAmount + (users[_index].amount);
        totalHmine = _hmineAmount + (totalHmine);

        //Sends BNB to the multisig wallet.
        address payable receiver = payable(sacrificesTo);
        receiver.transfer(msg.value);
    }

    function startFirstRound(uint256 _time) public onlyOwner {
        require(
            startTime > block.timestamp || startTime == 0,
            "Rounds were already started"
        );
        startTime = _time;
    }

    function updateTwap(address _twap) public onlyOwner {
        require(address(this) != _twap, "Cannot be contract.");
        twap = _twap;
    }

    function updateSacrifice(
        address _token,
        bool _isStable,
        address _lpAddress
    ) public onlyOwner {
        require(address(this) != _lpAddress, "Cannot be contract.");
        require(hasSacrifice(_token), "Sacrifice not supported. ");
        sacrifices[_token].isStable = _isStable;
        sacrifices[_token].oracleAddress = _lpAddress;
    }

    function removeSacrifice(address _token) public onlyOwner {
        require(hasSacrifice(_token), "Sacrifice not supported. ");
        delete sacrifices[_token];
    }

    function updateNickname(string memory nickname) public {
        uint256 _index = userIndex[msg.sender];
        require(index != 0, "User does not exist");
        users[_index].nickname = nickname;
    }

    function addSacToken(
        address _token,
        bool _isStable,
        address _lpAddress
    ) public onlyOwner {
        require(
            address(this) != _token && address(this) != _lpAddress,
            "Cannot be contract."
        );
        require(!hasSacrifice(_token), "Sacrifice is already supported. ");
        _addSac(_token, _isStable, _lpAddress);
    }

    function _addSac(
        address _token,
        bool _isStable,
        address _lpAddress
    ) internal {
        sacrifices[_token] = Sacrifice(true, _isStable, _lpAddress);
    }

    // Returns the users data by address lookup.
    function getUserByAddress(address _user) public view returns (User memory) {
        uint256 _index = userIndex[_user];
        return users[_index];
    }

    // Returns the users data by Index.
    function getUserByIndex(uint256 _index) public view returns (User memory) {
        return users[_index];
    }

    // Returns the current round.
    function getCurrentRound() public view returns (uint16) {
        if (startTime == 0) {
            return 0;
        }
        if (block.timestamp <= startTime + (roundPeriod)) {
            return 1;
        }
        return 2;
    }

    /* Check to make sure that conditions are met for the transaction to go through.
     ** Cannot start sacrifice unless startTime has been specified.
     ** Cannot sacrifice for anymore if 50K HMINE met before round 1 ends.
     ** Cannot sacrifice if 100K HMINE met or round2 ends.
     */
    function validateRound(uint256 _hmineAmount) internal view returns (bool) {
        // No start time yet.
        if (startTime == 0 || block.timestamp < startTime) {
            return false;
        }

        // HMINE for first round met, but it's still not 48 hours yet.
        if (
            totalHmine + (_hmineAmount) > hminePerRound &&
            block.timestamp < startTime + (roundPeriod)
        ) {
            return false;
        }

        // HMINE cap has been met or block time has passed the 4 day period.
        if (
            totalHmine + (_hmineAmount) > hminePerRound * (2) ||
            block.timestamp >= (roundPeriod) * (2) + (startTime)
        ) {
            return false;
        }

        return true;
    }

    // Takes in a user address and finds an existing index that is corelated to the user.
    // If index not found (ZERO) then it assigns an index to the user.
    function assignUserIndex(address _user) internal returns (uint256) {
        if (userIndex[_user] != 0) {
            return userIndex[_user];
        }
        return index++;
    }

    // Checks if token is a supported asset to sacrifice.
    function hasSacrifice(address _token) internal view returns (bool) {
        if (sacrifices[_token].isEnabled) {
            return true;
        }
        return false;
    }

    // If token is not a stable token, use this to find the price for the token.
    // This uses an active LP approach.
    function getAmountInStable(
        address _token,
        address _lp,
        uint256 _amount
    ) internal returns (uint256 _price) {
        IOraclePair LP = IOraclePair(_lp);
        (uint256 reserve0, uint256 reserve1, ) = LP.getReserves();
        address token0 = LP.token0();

        if (token0 == _token) {
            _price = (reserve1 * (_amount)) / (reserve0);
        } else {
            _price = (reserve0 * (_amount)) / (reserve1);
        }

        IOracleTwap(twap).updateAveragePrice(_lp);

        uint256 twapPrice = IOracleTwap(twap).consultAveragePrice(
            _lp,
            _token,
            _amount
        );

        require(
            (_price * twapMax) / 1000 > _price - twapPrice,
            "TWAP Price Error"
        );

        _price = twapPrice;
    }

    function updateTwapMax(uint256 _twapMax) external onlyOwner {
        require(_twapMax > 0, "Cannot be less than zero");
        twapMax = _twapMax;
    }
}
