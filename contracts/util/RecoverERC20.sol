// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

contract RecoverERC20 is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Emitted when tokens that were stuck in the router contract were recovered
    event Recovered(address indexed token, uint256 amount);

    constructor(address owner_) {
        transferOwnership(owner_);
    }

    /// @notice Added to support recovering tokens stuck in the contract
    /// This is to ensure that tokens can't get lost
    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
}
