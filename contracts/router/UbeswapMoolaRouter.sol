// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "./UbeswapMoolaRouterBase.sol";
import "../util/RecoverERC20.sol";

/// @notice Router for allowing conversion to/from Moola before swapping.
contract UbeswapMoolaRouter is UbeswapMoolaRouterBase, RecoverERC20 {
    /// @notice Referral code for the default Moola router
    uint16 public constant MOOLA_ROUTER_REFERRAL_CODE = 0x0420;

    constructor(address router_, address owner_)
        UbeswapMoolaRouterBase(router_, MOOLA_ROUTER_REFERRAL_CODE)
        RecoverERC20(owner_)
    // solhint-disable-next-line no-empty-blocks
    {

    }
}
