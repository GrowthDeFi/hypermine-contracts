// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockDai is ERC20("Mock Dai", "DAI")
{
	constructor()
	{
		_mint(msg.sender, 1_000_000_000e18);
	}
}