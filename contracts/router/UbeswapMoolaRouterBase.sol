// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../lending/LendingPoolWrapper.sol";
import "../interfaces/IUbeswapRouter.sol";
import "./UbeswapMoolaRouterLibrary.sol";

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
        _plan = UbeswapMoolaRouterLibrary.computeSwap(core, _path);

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

    /// @dev Ensures that the ERC20 token balances of this contract before and after
    /// the swap are equal
    /// TODO(igm): remove this once we get an audit
    /// This should NEVER get triggered, but it's better to be safe than sorry
    modifier balanceUnchanged(address[] calldata _path, address _to) {
        // Populate initial balances for comparison later
        uint256[] memory _initialBalances = new uint256[](_path.length);
        for (uint256 i = 0; i < _path.length; i++) {
            _initialBalances[i] = IERC20(_path[i]).balanceOf(address(this));
        }
        _;
        for (uint256 i = 0; i < _path.length - 1; i++) {
            uint256 newBalance = IERC20(_path[i]).balanceOf(address(this));
            require(
                // if triangular arb, ignore
                _path[i] == _path[0] ||
                    _path[i] == _path[_path.length - 1] ||
                    // ensure tokens balances haven't changed
                    newBalance == _initialBalances[i],
                "UbeswapMoolaRouter: tokens left over after swap"
            );
        }
        // sends the final tokens to `_to` address
        address lastAddress = _path[_path.length - 1];
        IERC20(lastAddress).safeTransfer(
            _to,
            // subtract the initial balance from this token
            IERC20(lastAddress).balanceOf(address(this)) -
                _initialBalances[_initialBalances.length - 1]
        );
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
    )
        external
        override
        balanceUnchanged(path, to)
        returns (uint256[] memory amounts)
    {
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
    )
        external
        override
        balanceUnchanged(path, to)
        returns (uint256[] memory amounts)
    {
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

    function getAmountsOut(uint256 _amountIn, address[] calldata _path)
        external
        view
        override
        returns (uint256[] memory)
    {
        return
            UbeswapMoolaRouterLibrary.getAmountsOut(
                core,
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
                core,
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
        return UbeswapMoolaRouterLibrary.computeSwap(core, _path);
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
