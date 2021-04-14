// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

contract MockERC20 is ERC20PresetFixedSupply {
    constructor(string memory name, string memory symbol)
        ERC20PresetFixedSupply(name, symbol, 100_000_000 ether, msg.sender)
    {
        // empty
    }
}

contract MockGold is ERC20("Celo", "CELO") {
    function unwrapTestingOnly(uint256 _amount) external {
        address payable recipient = payable(msg.sender);
        _burn(recipient, _amount);
        Address.sendValue(recipient, _amount);
    }

    function wrap() external payable {
        _mint(msg.sender, msg.value);
    }
}
