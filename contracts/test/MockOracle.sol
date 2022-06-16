// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

contract MockOracle {
    address private pair;

    // view functions
    function consultCurrentPrice(
        address _pair,
        address _token,
        uint256 _amountIn
    ) external view returns (uint256 _amountOut){
        return _amountIn * 294;
    }

    function consultAveragePrice(
        address _pair,
        address _token,
        uint256 _amountIn
    ) external view returns (uint256 _amountOut){
        return _amountIn * 294;
    }

    // open functions
    function updateAveragePrice(address _pair) external {
        pair = _pair;
    }
  
}
