// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../lending/MoolaLibrary.sol";

/// @dev Testing Celo Gold
interface IWrappedTestingGold {
    function unwrap(uint256 _amount) external;

    function wrap() external payable;
}

abstract contract UsesGold {
    /// @notice Address of Gold token
    address public immutable goldToken;

    /// @notice If true, this is on the hardhat network.
    bool public isHardhat;

    constructor() {
        isHardhat = block.chainid == 31337;
        goldToken = MoolaLibrary.getGoldToken();
    }

    /// @dev Ensures that gold is in native token format
    function ensureGoldUnwrapped(uint256 _amount) internal {
        // hardhat -- doesn't have celo erc20 so we need to handle it differently
        if (isHardhat) {
            IWrappedTestingGold(goldToken).unwrap(_amount);
        }
    }

    /// @dev Ensures that gold is in ERC20 format
    function ensureGoldWrapped() internal {
        // if hardhat, wrap the token so we can send it back to the user
        if (isHardhat) {
            IWrappedTestingGold(goldToken).wrap{value: msg.value}();
        }
    }

    /// @dev mock gold token can send tokens here on Hardhat
    modifier allowUnwrap {
        if (isHardhat && msg.sender == address(goldToken)) {
            return;
        }
        _;
    }
}
