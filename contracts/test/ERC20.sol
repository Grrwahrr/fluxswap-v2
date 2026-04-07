pragma solidity =0.5.16;

import '../FluxERC20.sol';

contract ERC20 is FluxERC20 {
    constructor(uint _totalSupply) public {
        _mint(msg.sender, _totalSupply);
    }
}
