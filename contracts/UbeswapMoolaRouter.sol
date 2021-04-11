// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "openzeppelin-solidity/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/token/ERC20/utils/SafeERC20.sol";

import "./LendingPoolWrapper.sol";
import "./interfaces/ITokenRouter.sol";

import "./interfaces/IAToken.sol";
import "./interfaces/ILendingPool.sol";
import "./interfaces/ILendingPoolCore.sol";
import "./interfaces/IUbeswapRouter.sol";

/**
 * Router for allowing conversion to/from Moola before swapping.
 */
contract UbeswapMoolaRouter is LendingPoolWrapper, ITokenRouter {
    using SafeERC20 for IERC20;

    /// @notice Ubeswap router
    IUbeswapRouter public immutable router;

    constructor(
        address router_,
        address pool_,
        address core_
    ) LendingPoolWrapper(pool_, core_) {
        router = IUbeswapRouter(router_);
    }

    function _initSwap(address[] calldata _path, uint256 _inAmount)
        internal
        returns (
            address _reserveOut,
            bool _depositOut,
            address[] calldata _nextPath
        )
    {
        uint256 startIndex;
        uint256 endIndex = _path.length;

        // cAsset -> mcAsset (deposit)
        if (getReserveATokenAddress(_path[0]) == _path[1]) {
            _convert(_path[0], _inAmount, true, Reason.CONVERT_IN);
            startIndex += 1;
        }
        // mcAsset -> cAsset (withdraw)
        else if (_path[0] == getReserveATokenAddress(_path[1])) {
            _convert(_path[1], _inAmount, false, Reason.CONVERT_IN);
            startIndex += 1;
        }

        // only handle path swap if the path is long enough
        if (_path.length >= 3) {
            // cAsset -> mcAsset (deposit)
            if (
                getReserveATokenAddress(_path[_path.length - 2]) ==
                _path[_path.length - 1]
            ) {
                _reserveOut = _path[_path.length - 1];
                _depositOut = true;
                endIndex -= 1;
            }
            // mcAsset -> cAsset (withdraw)
            else if (
                _path[_path.length - 2] ==
                getReserveATokenAddress(_path[_path.length - 1])
            ) {
                _reserveOut = _path[_path.length - 2];
                endIndex -= 1;
                // not needed
                // _depositOut = false;
            }
        }

        _nextPath = _path[startIndex:endIndex];
    }

    function _convertTokensOut(
        address _reserveOut,
        bool _depositOut,
        address _to,
        uint256 _amount
    ) internal {
        if (_reserveOut != address(0)) {
            _convert(_reserveOut, _amount, _depositOut, Reason.CONVERT_OUT);
            IERC20(
                _depositOut ? getReserveATokenAddress(_reserveOut) : _reserveOut
            )
                .safeTransfer(_to, _amount);
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        uint256 inAmount = router.getAmountsOut(amountIn, path)[0];
        (address reserveOut, bool depositOut, address[] calldata nextPath) =
            _initSwap(path, inAmount);

        amounts = router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            nextPath,
            address(this),
            deadline
        );

        _convertTokensOut(
            reserveOut,
            depositOut,
            to,
            amounts[amounts.length - 1]
        );
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        uint256 inAmount = router.getAmountsIn(amountOut, path)[0];
        (address reserveOut, bool depositOut, address[] calldata nextPath) =
            _initSwap(path, inAmount);

        amounts = router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            nextPath,
            address(this),
            deadline
        );

        _convertTokensOut(
            reserveOut,
            depositOut,
            to,
            amounts[amounts.length - 1]
        );
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override {
        (address reserveOut, bool depositOut, address[] calldata nextPath) =
            _initSwap(path, amountIn);

        uint256 balanceBefore =
            IERC20(path[path.length - 1]).balanceOf(address(this));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            nextPath,
            address(this),
            deadline
        );
        uint256 balanceAfter =
            IERC20(path[path.length - 1]).balanceOf(address(this));

        _convertTokensOut(
            reserveOut,
            depositOut,
            to,
            balanceAfter - balanceBefore
        );
    }
}
