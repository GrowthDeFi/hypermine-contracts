// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface IOraclePair {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

interface IOracleTwap {
    function consultAveragePrice(
        address _pair,
        address _token,
        uint256 _amountIn
    ) external view returns (uint256 _amountOut);

    function updateAveragePrice(address _pair) external;
}

contract HmineSacrifice is Ownable, ReentrancyGuard {
    using Address for address payable;
    using SafeERC20 for IERC20;

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

    mapping(address => Sacrifice) public sacrifices;
    uint256 public startTime = 0;
    uint256 constant roundPeriod = 48 hours;
    uint256 public hminePerRound = 50000e18; // Hmine per round is 50K
    uint256 public totalHmine;
    uint256 constant initPrice = 600; // The price is dvisible by 100.  So in this case 600 is actually $6.00
    uint256 public index = 0;
    mapping(address => uint256) userIndex;
    mapping(uint256 => User) public users;
    address payable public immutable sacrificesTo;
    address public immutable wbnb;
    address public twap;
    uint256 public twapMax = 30;

    constructor(
        address payable _sacTo,
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

    // Returns the users data by address lookup.
    function getUserByAddress(address _user)
        external
        view
        returns (User memory)
    {
        uint256 _index = userIndex[_user];
        return users[_index];
    }

    // Returns the users data by Index.
    function getUserByIndex(uint256 _index)
        external
        view
        returns (User memory)
    {
        return users[_index];
    }

    // Returns the current round.
    function getCurrentRound() external view returns (uint16) {
        if (startTime == 0) return 0;
        if (block.timestamp <= startTime + roundPeriod) return 1;
        return 2;
    }

    function updateNickname(string memory nickname) external {
        uint256 _index = userIndex[msg.sender];
        require(index != 0, "User does not exist");
        users[_index].nickname = nickname;
    }

    function sacrificeERC20(address _token, uint256 _amount)
        external
        nonReentrant
    {
        require(hasSacrifice(_token), "Sacrifice not supported");
        require(_amount > 0, "Amount cannot be less than zero");

        uint256 price = initPrice;
        if (
            totalHmine >= hminePerRound ||
            block.timestamp > startTime + roundPeriod
        ) {
            price = initPrice + 50;
        }

        uint256 _hmineAmount;
        if (sacrifices[_token].isStable) {
            _hmineAmount = (_amount * 100) / price;
        } else {
            _hmineAmount =
                (getAmountInStable(
                    _token,
                    sacrifices[_token].oracleAddress,
                    _amount
                ) * 100) /
                price;
        }

        require(validateRound(_hmineAmount), "Round ended or not started yet");

        uint256 _index = assignUserIndex(msg.sender);
        users[_index].user = msg.sender;
        users[_index].amount += _hmineAmount;
        totalHmine += _hmineAmount;
        IERC20(_token).safeTransferFrom(msg.sender, sacrificesTo, _amount);

        emit UserSacrifice(msg.sender, _token, _amount, _hmineAmount);
    }

    function sacrificeBNB() external payable nonReentrant {
        uint256 _amount = msg.value;
        require(hasSacrifice(wbnb), "Sacrifice not supported");
        require(_amount > 0, "Amount cannot be less than zero");

        uint256 price = initPrice;
        if (
            totalHmine >= hminePerRound ||
            block.timestamp > startTime + roundPeriod
        ) {
            price = initPrice + 50;
        }

        uint256 _hmineAmount = (getAmountInStable(
            wbnb,
            sacrifices[wbnb].oracleAddress,
            _amount
        ) * 100) / price;

        require(validateRound(_hmineAmount), "Round ended or not started yet");

        uint256 _index = assignUserIndex(msg.sender);
        users[_index].user = msg.sender;
        users[_index].amount += _hmineAmount;
        totalHmine += _hmineAmount;
        sacrificesTo.sendValue(_amount);

        emit UserSacrifice(msg.sender, wbnb, _amount, _hmineAmount);
    }

    function updateRoundMax(uint256 _max) external onlyOwner {
        require(startTime == 0, "Cannot update after round started");
        hminePerRound = _max;
    }

    function updateTwap(address _twap) external onlyOwner {
        require(address(0) != _twap, "Cannot be contract.");
        twap = _twap;
    }

    function updateTwapMax(uint256 _twapMax) external onlyOwner {
        require(_twapMax > 0, "Cannot be less than zero");
        twapMax = _twapMax;
    }

    function startFirstRound(uint256 _time) external onlyOwner {
        require(
            startTime > block.timestamp || startTime == 0,
            "Rounds were already started"
        );
        startTime = _time;
    }

    function addSacToken(
        address _token,
        bool _isStable,
        address _lpAddress
    ) external onlyOwner {
        require(address(0) != _token, "Cannot be contract.");
        require(!hasSacrifice(_token), "Sacrifice is already supported");

        if (address(0) != _lpAddress) {
            address _token0 = IOraclePair(_lpAddress).token0();
            address _token1 = IOraclePair(_lpAddress).token1();
            require(
                (_token == _token0 || _token == _token1) &&
                    IERC20Metadata(_token0).decimals() == 18 &&
                    IERC20Metadata(_token1).decimals() == 18,
                "Invalid lp"
            );
        } else {
            require(IERC20Metadata(_token).decimals() == 18, "Invalid decimal");
        }

        _addSac(_token, _isStable, _lpAddress);
    }

    function updateSacrifice(
        address _token,
        bool _isStable,
        address _lpAddress
    ) public onlyOwner {
        require(address(0) != _lpAddress, "Cannot be contract.");
        require(hasSacrifice(_token), "Sacrifice not supported");
        address _token0 = IOraclePair(_lpAddress).token0();
        address _token1 = IOraclePair(_lpAddress).token1();
        require(
            (_token == _token0 || _token == _token1) &&
                IERC20Metadata(_token0).decimals() == 18 &&
                IERC20Metadata(_token1).decimals() == 18,
            "Invalid lp"
        );
        sacrifices[_token].isStable = _isStable;
        sacrifices[_token].oracleAddress = _lpAddress;
    }

    function removeSacrifice(address _token) external onlyOwner {
        require(hasSacrifice(_token), "Sacrifice not supported");
        delete sacrifices[_token];
    }

    // Checks if token is a supported asset to sacrifice.
    function hasSacrifice(address _token) internal view returns (bool) {
        return sacrifices[_token].isEnabled;
    }

    function _addSac(
        address _token,
        bool _isStable,
        address _lpAddress
    ) internal {
        sacrifices[_token] = Sacrifice(true, _isStable, _lpAddress);
    }

    // Takes in a user address and finds an existing index that is corelated to the user.
    // If index not found (ZERO) then it assigns an index to the user.
    function assignUserIndex(address _user) internal returns (uint256) {
        if (userIndex[_user] == 0) userIndex[_user] = ++index;
        return userIndex[_user];
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
            _price = (reserve1 * _amount) / reserve0;
        } else {
            _price = (reserve0 * _amount) / reserve1;
        }

        // twap protection
        IOracleTwap(twap).updateAveragePrice(_lp);
        uint256 twapPrice = IOracleTwap(twap).consultAveragePrice(
            _lp,
            _token,
            _amount
        );
        require(
            _price < (twapPrice * (1000 + twapMax)) / 1000,
            "TWAP Price Error"
        );
    }

    /* Check to make sure that conditions are met for the transaction to go through.
     ** Cannot start sacrifice unless startTime has been specified.
     ** Cannot sacrifice for anymore if 50K HMINE met before round 1 ends.
     ** Cannot sacrifice if 100K HMINE met or round2 ends.
     */
    function validateRound(uint256 _hmineAmount) internal view returns (bool) {
        // No start time yet.
        if (startTime == 0 || block.timestamp < startTime) return false;

        // HMINE for first round met, but it's still not 48 hours yet.
        if (
            totalHmine + _hmineAmount > hminePerRound &&
            block.timestamp < startTime + roundPeriod
        ) return false;

        // HMINE cap has been met or block time has passed the 4 day period.
        if (
            totalHmine + _hmineAmount > 2 * hminePerRound ||
            block.timestamp >= startTime + 2 * roundPeriod
        ) return false;

        return true;
    }

    event UserSacrifice(
        address indexed _user,
        address indexed _token,
        uint256 _amount,
        uint256 _hmineAmount
    );
}
