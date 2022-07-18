// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IUbeswapRouter.sol";

/**
 * Router for incentivize referrers to run frontends.
 */
contract UbeswapReferrerRouter {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;
    uint256 public constant MAX_REFERRER_BPS = 5;

    /// @notice Ubeswap router
    IUbeswapRouter public immutable router;

    constructor(address router_) {
        router = IUbeswapRouter(router_);
    }

    function _takeReferrerFee(
        address referrer,
        uint256 referrerFeeBps,
        address feeToken,
        uint256 amountIn
    ) internal {
        if (referrerFeeBps > 0 && amountIn > 0) {
            require(
                referrerFeeBps <= MAX_REFERRER_BPS,
                "Referrer fee cannot be greater than 5 BPS"
            );
            uint256 fee = amountIn.mul(referrerFeeBps).div(BPS);
            IERC20(feeToken).safeTransferFrom(msg.sender, referrer, fee);
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        address referrer,
        uint256 referrerFeeBps
    ) public virtual returns (uint256[] memory amounts) {
        amounts = router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
        _takeReferrerFee(referrer, referrerFeeBps, path[0], amounts[0]);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline,
        address referrer,
        uint256 referrerFeeBps
    ) public virtual returns (uint256[] memory amounts) {
        amounts = router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            to,
            deadline
        );
        _takeReferrerFee(referrer, referrerFeeBps, path[0], amounts[0]);
    }

    /// @notice Swaps exact tokens in supporting tokens that might take a fee on transfer
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline,
        address referrer,
        uint256 referrerFeeBps
    ) public virtual {
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
        _takeReferrerFee(referrer, referrerFeeBps, path[0], amountIn);
    }

    function getAmountsOut(uint256 _amountIn, address[] calldata _path)
        external
        view
        returns (uint256[] memory)
    {
        return router.getAmountsOut(_amountIn, _path);
    }

    function getAmountsIn(uint256 _amountOut, address[] calldata _path)
        external
        view
        returns (uint256[] memory)
    {
        return router.getAmountsIn(_amountOut, _path);
    }
}
