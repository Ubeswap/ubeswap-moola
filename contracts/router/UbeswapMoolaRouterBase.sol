// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../lending/LendingPoolWrapper.sol";
import "../interfaces/IUbeswapRouter.sol";
import "./UbeswapMoolaRouterLibrary.sol";
import "hardhat/console.sol";

/**
 * Router for allowing conversion to/from Moola before swapping.
 */
abstract contract UbeswapMoolaRouterBase is LendingPoolWrapper, IUbeswapRouter {
    using SafeERC20 for IERC20;

    /// @notice Ubeswap router
    IUbeswapRouter public immutable router;

    /// @notice Emitted when tokens are swapped
    event TokensSwapped(
        address indexed account,
        address[] indexed path,
        address indexed to,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(address router_, uint16 moolaReferralCode_)
        LendingPoolWrapper(moolaReferralCode_)
    {
        router = IUbeswapRouter(router_);
    }

    function _initSwap(
        address[] calldata _path,
        uint256 _inAmount,
        uint256 _outAmount
    ) internal returns (UbeswapMoolaRouterLibrary.SwapPlan memory _plan) {
        _plan = UbeswapMoolaRouterLibrary.computeSwap(dataProvider, _path);

        // if we have a path, approve the router to be able to trade
        if (_plan.nextPath.length > 0) {
            // if out amount is specified, compute the in amount from it
            if (_outAmount != 0) {
                _inAmount = router.getAmountsIn(_outAmount, _plan.nextPath)[0];
            }
            IERC20(_plan.nextPath[0]).safeApprove(address(router), _inAmount);
        }

        // Handle pulling the initial amount from the contract caller
        IERC20(_path[0]).safeTransferFrom(msg.sender, address(this), _inAmount);

        // If in reserve is specified, we must convert
        if (_plan.reserveIn != address(0)) {
            _convert(
                _plan.reserveIn,
                _inAmount,
                _plan.depositIn,
                Reason.CONVERT_IN
            );
        }
    }

    /// @dev Handles the swap after the plan is executed
    function _swapConvertOut(
        UbeswapMoolaRouterLibrary.SwapPlan memory _plan,
        uint256[] memory _routerAmounts,
        address[] calldata _path,
        address _to
    ) internal returns (uint256[] memory amounts) {
        amounts = UbeswapMoolaRouterLibrary.computeAmountsFromRouterAmounts(
            _routerAmounts,
            _plan.reserveIn,
            _plan.reserveOut
        );
        if (_plan.reserveOut != address(0)) {
            _convert(
                _plan.reserveOut,
                amounts[amounts.length - 1],
                _plan.depositOut,
                Reason.CONVERT_OUT
            );
        }
        IERC20(_path[_path.length - 1]).safeTransfer(
            _to,
            amounts[amounts.length - 1]
        );
        emit TokensSwapped(
            msg.sender,
            _path,
            _to,
            amounts[0],
            amounts[amounts.length - 1]
        );
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) public virtual override returns (uint256[] memory amounts) {
        UbeswapMoolaRouterLibrary.SwapPlan memory plan =
            _initSwap(path, amountIn, 0);
        if (plan.nextPath.length > 0) {
            amounts = router.swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                plan.nextPath,
                address(this),
                deadline
            );
        }
        amounts = _swapConvertOut(plan, amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) public virtual override returns (uint256[] memory amounts) {
        UbeswapMoolaRouterLibrary.SwapPlan memory plan =
            _initSwap(path, 0, amountOut);
        if (plan.nextPath.length > 0) {
            amounts = router.swapTokensForExactTokens(
                amountOut,
                amountInMax,
                plan.nextPath,
                address(this),
                deadline
            );
        }
        amounts = _swapConvertOut(plan, amounts, path, to);
    }

    /// @notice Swaps exact tokens in supporting tokens that might take a fee on transfer
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) public virtual override {
        UbeswapMoolaRouterLibrary.SwapPlan memory plan =
            _initSwap(path, amountIn, 0);
        uint256 balanceDiff = 0;
        if (plan.nextPath.length > 0) {
            uint256 balanceBefore =
                IERC20(path[path.length - 1]).balanceOf(address(this));
            router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
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
        IERC20(path[path.length - 1]).safeTransfer(to, balanceDiff);
        emit TokensSwapped(msg.sender, path, to, amountIn, balanceDiff);
    }

    function getAmountsOut(uint256 _amountIn, address[] calldata _path)
        external
        view
        override
        returns (uint256[] memory)
    {
        return
            UbeswapMoolaRouterLibrary.getAmountsOut(
                dataProvider,
                router,
                _amountIn,
                _path
            );
    }

    function getAmountsIn(uint256 _amountOut, address[] calldata _path)
        external
        view
        override
        returns (uint256[] memory)
    {
        return
            UbeswapMoolaRouterLibrary.getAmountsIn(
                dataProvider,
                router,
                _amountOut,
                _path
            );
    }

    function computeSwap(address[] calldata _path)
        external
        view
        returns (UbeswapMoolaRouterLibrary.SwapPlan memory)
    {
        return UbeswapMoolaRouterLibrary.computeSwap(dataProvider, _path);
    }

    function computeAmountsFromRouterAmounts(
        uint256[] memory _routerAmounts,
        address _reserveIn,
        address _reserveOut
    ) external pure returns (uint256[] memory) {
        return
            UbeswapMoolaRouterLibrary.computeAmountsFromRouterAmounts(
                _routerAmounts,
                _reserveIn,
                _reserveOut
            );
    }
}
