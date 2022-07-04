// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract HmineToken is ERC20("HYPERMINE Token", "HMINE")
{
	constructor()
	{
		_mint(msg.sender, 200_000e18);
	}
}