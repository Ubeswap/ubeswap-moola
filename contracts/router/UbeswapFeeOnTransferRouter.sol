// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./UbeswapMoolaRouterBase.sol";

interface IUbeswapFeeOnTransferRouter {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

/**
 * Router for Ubeswap supporting tokens that take a fee on transfer.
 */
contract UbeswapFeeOnTransferRouter is
    UbeswapMoolaRouterBase,
    IUbeswapFeeOnTransferRouter
{
    uint16 public constant MOOLA_ROUTER_FOT_REFERRAL_CODE = 0x0422;

    constructor(address router_)
        UbeswapMoolaRouterBase(router_, MOOLA_ROUTER_FOT_REFERRAL_CODE)
    // solhint-disable-next-line no-empty-blocks
    {

    }

    /// @notice Swaps exact tokens in supporting tokens that might take a fee on transfer
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override balanceUnchanged(path, to) {
        UbeswapMoolaRouterLibrary.SwapPlan memory plan =
            _initSwap(path, amountIn, 0);
        uint256 balanceDiff = 0;
        if (plan.nextPath.length > 0) {
            uint256 balanceBefore =
                IERC20(path[path.length - 1]).balanceOf(address(this));
            IUbeswapFeeOnTransferRouter(address(router))
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn,
                amountOutMin,
                plan.nextPath,
                address(this),
                deadline
            );
            uint256 balanceAfter =
                IERC20(path[path.length - 1]).balanceOf(address(this));
            balanceDiff = balanceAfter - balanceBefore;
        }

        if (plan.reserveOut != address(0)) {
            _convert(
                plan.reserveOut,
                balanceDiff,
                plan.depositOut,
                Reason.CONVERT_OUT
            );
        }

        emit TokensSwapped(msg.sender, path, to, amountIn, balanceDiff);
    }
}
