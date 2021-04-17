// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";
import "./UbeswapMoolaRouterBase.sol";

/**
 * Router for allowing conversion to/from Moola before swapping.
 */
contract UbeswapMoolaRouter is UbeswapMoolaRouterBase, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Emitted when tokens that were stuck in the router contract were recovered
    event Recovered(address indexed token, uint256 amount);

    uint16 public constant MOOLA_ROUTER_REFERRAL_CODE = 0x0420;

    constructor(address router_, address owner_)
        UbeswapMoolaRouterBase(router_, MOOLA_ROUTER_REFERRAL_CODE)
    {
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
