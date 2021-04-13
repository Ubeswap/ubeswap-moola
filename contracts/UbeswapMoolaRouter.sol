// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

import "./LendingPoolWrapper.sol";
import "./interfaces/IAToken.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/ILendingPoolCore.sol";
import "./interfaces/IUbeswapRouter.sol";

/**
 * Router for allowing conversion to/from Moola before swapping.
 */
contract UbeswapMoolaRouter is LendingPoolWrapper, IUbeswapRouter {
    using SafeERC20 for IERC20;

    /// @notice Ubeswap router
    IUbeswapRouter public immutable router;

    /// @notice Plan for executing a swap on the router.
    struct SwapPlan {
        address reserveIn;
        address reserveOut;
        bool depositIn;
        bool depositOut;
        address[] nextPath;
    }

    constructor(address router_, address registry_)
        LendingPoolWrapper(registry_)
    {
        router = IUbeswapRouter(router_);
    }

    // Computes the swap that will take place based on the path
    function computeSwap(address[] calldata _path)
        public
        view
        returns (SwapPlan memory _plan)
    {
        uint256 startIndex;
        uint256 endIndex = _path.length;

        // cAsset -> mcAsset (deposit)
        if (getReserveATokenAddress(_path[0]) == _path[1]) {
            _plan.reserveIn = _path[0];
            _plan.depositIn = true;
            startIndex += 1;
        }
        // mcAsset -> cAsset (withdraw)
        else if (_path[0] == getReserveATokenAddress(_path[1])) {
            _plan.reserveIn = _path[1];
            _plan.depositIn = false;
            startIndex += 1;
        }

        // only handle out path swap if the path is long enough
        if (
            _path.length >= 3 &&
            // if we already did a conversion and path length is 3, skip.
            !(_path.length == 3 && startIndex > 0)
        ) {
            // cAsset -> mcAsset (deposit)
            if (
                getReserveATokenAddress(_path[_path.length - 2]) ==
                _path[_path.length - 1]
            ) {
                _plan.reserveOut = _path[_path.length - 2];
                _plan.depositOut = true;
                endIndex -= 1;
            }
            // mcAsset -> cAsset (withdraw)
            else if (
                _path[_path.length - 2] ==
                getReserveATokenAddress(_path[_path.length - 1])
            ) {
                _plan.reserveOut = _path[_path.length - 1];
                endIndex -= 1;
                // not needed
                // _depositOut = false;
            }
        }

        _plan.nextPath = _path[startIndex:endIndex];
    }

    function _initSwap(
        address[] calldata _path,
        uint256 _inAmount,
        uint256 _outAmount
    )
        private
        returns (SwapPlan memory _plan, uint256[] memory _initialBalances)
    {
        _plan = computeSwap(_path);

        // if out amount is specified, compute the in amount from it
        if (_outAmount != 0) {
            _inAmount = router.getAmountsIn(_outAmount, _plan.nextPath)[0];
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

        // Populate initial balances for comparison later
        _initialBalances = new uint256[](_path.length);
        for (uint256 i = 0; i < _path.length; i++) {
            _initialBalances[i] = IERC20(_path[i]).balanceOf(address(this));
        }
    }

    // converts out tokens and computes the path amounts
    function _convertTokensOut(
        address _reserveOut,
        bool _depositOut,
        uint256 _amount
    ) private {
        if (_reserveOut != address(0)) {
            _convert(_reserveOut, _amount, _depositOut, Reason.CONVERT_OUT);
        }
    }

    // computes the amounts given the amounts returned by the router
    function _computeAmounts(
        uint256[] memory routerAmounts,
        address _reserveIn,
        address _reserveOut
    ) private pure returns (uint256[] memory amounts) {
        uint256 startOffset = _reserveIn != address(0) ? 1 : 0;
        uint256 endOffset = _reserveOut != address(0) ? 1 : 0;
        uint256 length = routerAmounts.length + startOffset + endOffset;

        amounts = new uint256[](length);
        if (startOffset > 0) {
            amounts[0] = routerAmounts[0];
        }
        if (endOffset > 0) {
            amounts[length - 1] = routerAmounts[routerAmounts.length - 1];
        }
        for (uint256 i = 0; i < routerAmounts.length; i++) {
            amounts[i + startOffset] = routerAmounts[i];
        }
    }

    // TODO(igm): remove this once we get an audit
    // This should NEVER get triggered, but it's better to be safe than sorry
    function _cleanupSwap(
        address[] calldata _path,
        address _to,
        uint256[] memory _balances
    ) internal {
        for (uint256 i = 0; i < _path.length; i++) {
            uint256 newBalance = IERC20(_path[i]).balanceOf(address(this));
            if (i == _path.length - 1) {
                IERC20(_path[_path.length - 1]).safeTransfer(
                    _to,
                    newBalance - _balances[i]
                );
            } else {
                require(
                    newBalance == _balances[i],
                    "UbeswapMoolaRouter: tokens left over after swap"
                );
            }
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        (SwapPlan memory plan, uint256[] memory initialBalances) =
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
        amounts = _computeAmounts(amounts, plan.reserveIn, plan.reserveOut);

        if (plan.reserveOut != address(0)) {
            _convert(
                plan.reserveOut,
                amounts[amounts.length - 1],
                plan.depositOut,
                Reason.CONVERT_OUT
            );
        }
        _cleanupSwap(path, to, initialBalances);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        (SwapPlan memory plan, uint256[] memory initialBalances) =
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
        amounts = _computeAmounts(amounts, plan.reserveIn, plan.reserveOut);

        if (plan.reserveOut != address(0)) {
            _convert(
                plan.reserveOut,
                amounts[amounts.length - 1],
                plan.depositOut,
                Reason.CONVERT_OUT
            );
        }
        _cleanupSwap(path, to, initialBalances);
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override {
        (SwapPlan memory plan, uint256[] memory initialBalances) =
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

        _convertTokensOut(plan.reserveOut, plan.depositOut, balanceDiff);
        _cleanupSwap(path, to, initialBalances);
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        SwapPlan memory plan = computeSwap(path);
        amounts = _computeAmounts(
            router.getAmountsOut(amountIn, plan.nextPath),
            plan.reserveIn,
            plan.reserveOut
        );
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        SwapPlan memory plan = computeSwap(path);
        amounts = _computeAmounts(
            router.getAmountsIn(amountOut, plan.nextPath),
            plan.reserveIn,
            plan.reserveOut
        );
    }
}
